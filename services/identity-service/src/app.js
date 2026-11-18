// Identity service: accounts, roles, tokens, and the patient directory.

import { randomUUID } from 'node:crypto';

import express from 'express';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import { jwtVerify } from 'jose';
import { z } from 'zod';

import { BusyError, hashPassword, hashingGate, verifyPassword } from './passwords.js';
import { hashToken, newRefreshToken, signAccessToken } from './tokens.js';

const ROLES = ['patient', 'doctor', 'nurse'];

const loginBody = z.object({
  email: z.string().trim().toLowerCase().email().max(254),
  password: z.string().min(1).max(128),
  role: z.enum(ROLES),
});
const refreshBody = z.object({ refresh_token: z.string().min(20).max(200) });
const logoutBody = z.object({ refresh_token: z.string().min(20).max(200).optional() }).optional();

// One message for every login failure, so responses don't reveal whether an
// email exists or which role it has.
const BAD_CREDENTIALS = 'Email or password is incorrect';

class HttpError extends Error {
  constructor(status, message, error = 'error') {
    super(message);
    this.status = status;
    this.error = error;
  }
}

export function publicUser(u) {
  return {
    id: u.id,
    email: u.email,
    name: u.name,
    role: u.role,
    ...(u.specialization ? { specialization: u.specialization } : {}),
    profileImageUrl: null,
  };
}

export async function createApp({ config, store, keys }) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', config.trustProxy);
  app.use(helmet());
  app.use(express.json({ limit: '10kb' }));
  app.use((_req, res, next) => {
    res.set('Cache-Control', 'no-store');
    next();
  });

  // A fixed hash to verify against when the email is unknown, so a miss takes
  // as long as a hit (no user enumeration through response timing).
  const decoyHash = await hashPassword(randomUUID(), config.scryptCost);
  const hashing = hashingGate(config.maxConcurrentHashes, config.hashQueueLimit);

  const limiter = (limit) =>
    rateLimit({
      windowMs: 15 * 60 * 1000,
      limit,
      standardHeaders: 'draft-7',
      legacyHeaders: false,
      message: { error: 'rate_limited', message: 'Too many attempts. Try again in a few minutes.' },
    });

  const parse = (schema, body) => {
    const result = schema.safeParse(body);
    if (!result.success) throw new HttpError(400, 'Invalid request', 'validation_error');
    return result.data;
  };

  async function issueSession(user, familyId = randomUUID()) {
    const refreshToken = newRefreshToken();
    await store.insertRefreshToken({
      tokenHash: hashToken(refreshToken),
      userId: user.id,
      familyId,
      expiresAt: new Date(Date.now() + config.refreshTokenTtlSeconds * 1000),
    });
    return {
      access_token: await signAccessToken(keys, config, user),
      refresh_token: refreshToken,
      expires_in: config.accessTokenTtlSeconds,
    };
  }

  async function authenticate(req) {
    const header = req.get('authorization') ?? '';
    const [scheme, token] = header.split(' ');
    if (scheme !== 'Bearer' || !token) throw new HttpError(401, 'Missing access token', 'unauthorized');
    try {
      const { payload } = await jwtVerify(token, keys.publicKey, {
        algorithms: ['RS256'],
        issuer: config.issuer,
        audience: config.audience,
      });
      return { id: payload.sub, role: payload.role };
    } catch {
      throw new HttpError(401, 'Access token is invalid or expired', 'invalid_token');
    }
  }

  app.get('/.well-known/jwks.json', async (_req, res) => {
    res.set('Cache-Control', 'public, max-age=300');
    res.json(await keys.jwks());
  });

  app.post('/auth/login', limiter(config.loginRateLimit), async (req, res) => {
    const { email, password, role } = parse(loginBody, req.body);
    const user = await store.findUserByEmail(email);
    let ok;
    try {
      ok = await hashing(() => verifyPassword(password, user?.passwordHash ?? decoyHash));
    } catch (e) {
      if (e instanceof BusyError) throw new HttpError(503, 'Too many sign-ins right now. Try again in a moment.', 'busy');
      throw e;
    }
    if (!user || !ok || user.role !== role) throw new HttpError(401, BAD_CREDENTIALS, 'invalid_credentials');
    res.json({ user: publicUser(user), ...(await issueSession(user)) });
  });

  app.post('/auth/refresh', limiter(config.loginRateLimit * 6), async (req, res) => {
    const { refresh_token: token } = parse(refreshBody, req.body);
    const tokenHash = hashToken(token);
    const record = await store.findRefreshToken(tokenHash);
    const invalid = new HttpError(401, 'Invalid or expired refresh token', 'invalid_token');
    if (!record || record.revokedAt || record.expiresAt <= new Date()) throw invalid;

    if (!(await store.consumeRefreshToken(tokenHash, new Date()))) {
      // Already used: someone replayed it. Kill every token in this session.
      await store.revokeFamily(record.familyId, new Date());
      throw invalid;
    }
    const user = await store.findUserById(record.userId);
    if (!user) throw invalid;
    res.json(await issueSession(user, record.familyId));
  });

  app.post('/auth/logout', async (req, res) => {
    await authenticate(req);
    const body = parse(logoutBody, req.body);
    if (body?.refresh_token) {
      const record = await store.findRefreshToken(hashToken(body.refresh_token));
      if (record) await store.revokeFamily(record.familyId, new Date());
    }
    res.json({ message: 'Logout successful' });
  });

  app.get('/auth/me', async (req, res) => {
    const principal = await authenticate(req);
    const user = await store.findUserById(principal.id);
    if (!user) throw new HttpError(401, 'Account no longer exists', 'invalid_token');
    res.json(publicUser(user));
  });

  // Names for the pseudonymized IDs that telemetry carries. Care team only.
  app.get('/patients', async (req, res) => {
    const principal = await authenticate(req);
    if (principal.role === 'patient') throw new HttpError(403, 'Care team only', 'forbidden');
    const patients = await store.listUsersByRole('patient');
    res.json({ patients: patients.map((p) => ({ id: p.id, name: p.name, email: p.email })) });
  });

  app.get('/health', (_req, res) => res.json({ status: 'ok' }));

  app.get('/ready', async (_req, res) => {
    const db = await store.ping();
    res.status(db ? 200 : 503).json({ status: db ? 'ready' : 'degraded', database: db });
  });

  app.use((_req, _res, next) => next(new HttpError(404, 'Not found', 'not_found')));

  // Express recognizes error handlers by their 4-argument signature.
  app.use((err, _req, res, _next) => {
    if (err instanceof HttpError) {
      return res.status(err.status).json({ error: err.error, message: err.message });
    }
    if (err?.type === 'entity.parse.failed' || err?.type === 'entity.too.large') {
      return res.status(400).json({ error: 'validation_error', message: 'Invalid request' });
    }
    console.error(err); // details stay in the server log, never in the response
    return res.status(500).json({ error: 'internal_error', message: 'Something went wrong' });
  });

  return app;
}
