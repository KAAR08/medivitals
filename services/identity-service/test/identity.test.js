import assert from 'node:assert/strict';
import { before, beforeEach, describe, it } from 'node:test';

import { createLocalJWKSet, decodeJwt, jwtVerify } from 'jose';
import request from 'supertest';

import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { DEMO_USERS, parseAccounts, seed, seedAccounts } from '../src/seed.js';
import { MemoryStore } from '../src/store.js';
import { KeyRing } from '../src/tokens.js';

const PASSWORD = 'correct horse battery staple';
const keys = new KeyRing();
const JOHN = DEMO_USERS.find((u) => u.name === 'John Doe');
const NURSE = DEMO_USERS.find((u) => u.role === 'nurse');

let app;
let store;

async function freshApp(overrides = {}) {
  store = new MemoryStore();
  const config = loadConfig({ scryptCost: 1024, loginRateLimit: 100, ...overrides });
  await seed(store, PASSWORD, config.scryptCost);
  return createApp({ config, store, keys });
}

const login = (email, role, password = PASSWORD) =>
  request(app).post('/auth/login').send({ email, password, role });

beforeEach(async () => {
  app = await freshApp();
});

describe('login', () => {
  it('returns the user and a token pair in the shape the app expects', async () => {
    const res = await login(JOHN.email, 'patient');
    assert.equal(res.status, 200);
    assert.deepEqual(Object.keys(res.body).sort(), ['access_token', 'expires_in', 'refresh_token', 'user']);
    assert.equal(res.body.user.id, JOHN.id);
    assert.equal(res.body.user.passwordHash, undefined, 'never leak the hash');
    assert.equal(res.headers['cache-control'], 'no-store');
  });

  it('is case-insensitive on email', async () => {
    assert.equal((await login(JOHN.email.toUpperCase(), 'patient')).status, 200);
  });

  it('gives one generic error for wrong password, unknown email and wrong role', async () => {
    const responses = await Promise.all([
      login(JOHN.email, 'patient', 'wrong password'),
      login('nobody@example.com', 'patient'),
      login(JOHN.email, 'doctor'),
    ]);
    for (const res of responses) {
      assert.equal(res.status, 401);
      assert.equal(res.body.message, 'Email or password is incorrect');
    }
  });

  it('rejects malformed and injection-shaped input', async () => {
    const bad = [
      {},
      { email: 'not-an-email', password: 'x', role: 'patient' },
      { email: JOHN.email, password: PASSWORD, role: 'admin' },
      { email: { $ne: null }, password: PASSWORD, role: 'patient' }, // NoSQL injection attempt
    ];
    for (const body of bad) {
      assert.equal((await request(app).post('/auth/login').send(body)).status, 400);
    }
  });

  it('rate-limits brute force attempts', async () => {
    app = await freshApp({ loginRateLimit: 3 });
    for (let i = 0; i < 3; i++) await login(JOHN.email, 'patient', 'guess');
    const blocked = await login(JOHN.email, 'patient');
    assert.equal(blocked.status, 429);
  });
});

describe('access tokens', () => {
  it('are RS256, short-lived, carry the role, and verify against the published JWKS', async () => {
    const { body } = await login(NURSE.email, 'nurse');
    const jwks = (await request(app).get('/.well-known/jwks.json')).body;
    assert.equal(jwks.keys[0].alg, 'RS256');
    assert.equal(jwks.keys[0].d, undefined, 'JWKS must never contain the private key');

    const { payload, protectedHeader } = await jwtVerify(body.access_token, createLocalJWKSet(jwks), {
      issuer: 'medvitals-identity',
      audience: 'medvitals-api',
    });
    assert.equal(protectedHeader.alg, 'RS256');
    assert.equal(payload.sub, NURSE.id);
    assert.equal(payload.role, 'nurse');
    assert.equal(payload.exp - payload.iat, 600);
  });

  it('authorize /auth/me and the care-team patient directory', async () => {
    const nurse = (await login(NURSE.email, 'nurse')).body.access_token;
    const patient = (await login(JOHN.email, 'patient')).body.access_token;

    const me = await request(app).get('/auth/me').set('Authorization', `Bearer ${patient}`);
    assert.equal(me.body.name, 'John Doe');

    const directory = await request(app).get('/patients').set('Authorization', `Bearer ${nurse}`);
    assert.equal(directory.status, 200);
    assert.deepEqual(directory.body.patients.map((p) => p.name).sort(), ['Bob Wilson', 'Jane Smith', 'John Doe']);

    const forbidden = await request(app).get('/patients').set('Authorization', `Bearer ${patient}`);
    assert.equal(forbidden.status, 403);
  });

  it('reject missing, tampered and foreign tokens', async () => {
    const token = (await login(JOHN.email, 'patient')).body.access_token;
    const [h, , s] = token.split('.');
    const claims = decodeJwt(token);
    const forgedPayload = Buffer.from(JSON.stringify({ ...claims, role: 'doctor' })).toString('base64url');

    for (const auth of [undefined, 'Bearer nonsense', `Bearer ${h}.${forgedPayload}.${s}`]) {
      const req = request(app).get('/auth/me');
      if (auth) req.set('Authorization', auth);
      assert.equal((await req).status, 401);
    }
  });
});

describe('refresh token rotation', () => {
  it('issues a new pair and makes the old refresh token single-use', async () => {
    const first = (await login(JOHN.email, 'patient')).body;
    const second = await request(app).post('/auth/refresh').send({ refresh_token: first.refresh_token });
    assert.equal(second.status, 200);
    assert.notEqual(second.body.refresh_token, first.refresh_token);

    // Reusing the old token is treated as theft: the whole session is revoked,
    // including the token that was just issued.
    const replay = await request(app).post('/auth/refresh').send({ refresh_token: first.refresh_token });
    assert.equal(replay.status, 401);
    const afterTheft = await request(app).post('/auth/refresh').send({ refresh_token: second.body.refresh_token });
    assert.equal(afterTheft.status, 401);
  });

  it('stores only hashes of refresh tokens', async () => {
    const { refresh_token: token } = (await login(JOHN.email, 'patient')).body;
    const stored = JSON.stringify([...store.tokens.values()]);
    assert.ok(!stored.includes(token));
  });

  it('logout revokes the session', async () => {
    const session = (await login(JOHN.email, 'patient')).body;
    const out = await request(app)
      .post('/auth/logout')
      .set('Authorization', `Bearer ${session.access_token}`)
      .send({ refresh_token: session.refresh_token });
    assert.equal(out.status, 200);
    const reuse = await request(app).post('/auth/refresh').send({ refresh_token: session.refresh_token });
    assert.equal(reuse.status, 401);
  });
});

describe('hardening', () => {
  before(async () => {
    app = await freshApp();
  });

  it('sends security headers and hides the framework', async () => {
    const res = await request(app).get('/health');
    assert.equal(res.headers['x-powered-by'], undefined);
    assert.equal(res.headers['x-content-type-options'], 'nosniff');
    assert.ok(res.headers['strict-transport-security']);
  });

  it('rejects oversized and malformed bodies without leaking internals', async () => {
    const huge = await request(app)
      .post('/auth/login')
      .set('Content-Type', 'application/json')
      .send(`{"email":"${'a'.repeat(20000)}"}`);
    assert.equal(huge.status, 400);
    const broken = await request(app).post('/auth/login').set('Content-Type', 'application/json').send('{oops');
    assert.equal(broken.status, 400);
    assert.ok(!JSON.stringify(broken.body).includes('SyntaxError'));
  });

  it('answers unknown routes with a JSON 404', async () => {
    const res = await request(app).get('/admin');
    assert.equal(res.status, 404);
    assert.equal(res.body.error, 'not_found');
  });
});

describe('password hashing under load', () => {
  it('turns a burst of sign-ins away fast instead of queueing them all', async () => {
    app = await freshApp({ scryptCost: 2 ** 14, maxConcurrentHashes: 1, hashQueueLimit: 1 });
    const burst = await Promise.all(
      Array.from({ length: 6 }, () => login('nobody@example.com', 'patient', 'wrong-password-123')),
    );
    const statuses = burst.map((r) => r.status);
    assert.ok(statuses.includes(503), `expected some 503s, got ${statuses}`);
    assert.ok(statuses.includes(401), 'the ones that ran still get the normal answer');
    const busy = burst.find((r) => r.status === 503);
    assert.equal(busy.body.error, 'busy');

    // Once the burst is over, sign-in works normally.
    assert.equal((await login(JOHN.email, 'patient')).status, 200);
  });

  it('never runs more hashes at once than allowed', async () => {
    const { hashingGate } = await import('../src/passwords.js');
    const gate = hashingGate(2, 10);
    let running = 0;
    let peak = 0;
    const task = () =>
      gate(async () => {
        running += 1;
        peak = Math.max(peak, running);
        await new Promise((r) => setTimeout(r, 5));
        running -= 1;
      });
    await Promise.all(Array.from({ length: 10 }, task));
    assert.equal(peak, 2);
  });
});

describe('configuration', () => {
  it('puts a separately stored database password into the Mongo URL, encoded', async () => {
    process.env.IDENTITY_MONGO_URL = 'mongodb://medvitals@mongo:27017/medvitals_identity?authSource=admin';
    process.env.IDENTITY_MONGO_PASSWORD = 'p@ss/w:rd';
    try {
      const config = loadConfig();
      assert.equal(config.mongoUrl, 'mongodb://medvitals:p%40ss%2Fw%3Ard@mongo:27017/medvitals_identity?authSource=admin');
    } finally {
      delete process.env.IDENTITY_MONGO_URL;
      delete process.env.IDENTITY_MONGO_PASSWORD;
    }
  });
});

describe('seed accounts', () => {
  const account = (over = {}) => ({
    email: 'nurse.amina@hospital.test',
    name: 'Nurse Amina',
    role: 'nurse',
    password: 'amina-own-password',
    ...over,
  });

  it('gives every account its own password', async () => {
    store = new MemoryStore();
    const config = loadConfig({ scryptCost: 1024, loginRateLimit: 100 });
    const accounts = parseAccounts(
      JSON.stringify([
        account(),
        { ...account(), email: 'Dr.Omar@Hospital.test', name: 'Dr. Omar', role: 'doctor', password: 'omar-own-password' },
      ]),
    );
    await seedAccounts(store, accounts, config.scryptCost);
    app = await createApp({ config, store, keys });

    assert.equal((await login('nurse.amina@hospital.test', 'nurse', 'amina-own-password')).status, 200);
    assert.equal((await login('dr.omar@hospital.test', 'doctor', 'omar-own-password')).status, 200);
    assert.equal((await login('dr.omar@hospital.test', 'doctor', 'amina-own-password')).status, 401);
  });

  it('keeps a given id (patients linked to the simulator) and creates one otherwise', () => {
    const [kept, created] = parseAccounts(
      JSON.stringify([account({ id: JOHN.id, role: 'patient' }), account({ email: 'b@x.test' })]),
    );
    assert.equal(kept.id, JOHN.id);
    assert.match(created.id, /^[0-9a-f-]{36}$/);
  });

  it('rejects a file with short passwords, bad roles or duplicates, naming each problem', () => {
    const bad = JSON.stringify([account({ password: 'short' }), account({ role: 'admin' })]);
    assert.throws(() => parseAccounts(bad), (err) => {
      assert.match(err.message, /password needs 12\+ characters/);
      assert.match(err.message, /role must be doctor, nurse or patient/);
      assert.match(err.message, /duplicate email/);
      return true;
    });
    assert.throws(() => parseAccounts('[]'), /non-empty/);
  });

  it('never changes an existing account, so the passwords can be removed from the file', async () => {
    store = new MemoryStore();
    const config = loadConfig({ scryptCost: 1024, loginRateLimit: 100 });
    const first = await seedAccounts(store, parseAccounts(JSON.stringify([account()])), config.scryptCost);
    assert.deepEqual(first.created, ['nurse.amina@hospital.test']);

    // Re-run with another password, then with none: the stored hash stays.
    const changed = parseAccounts(JSON.stringify([account({ password: 'a-different-password' })]));
    assert.deepEqual((await seedAccounts(store, changed, config.scryptCost)).existing, ['nurse.amina@hospital.test']);
    const withoutPassword = account();
    delete withoutPassword.password;
    const again = await seedAccounts(store, parseAccounts(JSON.stringify([withoutPassword])), config.scryptCost);
    assert.deepEqual(again.created, []);

    app = await createApp({ config, store, keys });
    assert.equal((await login('nurse.amina@hospital.test', 'nurse', 'amina-own-password')).status, 200);
    assert.equal((await login('nurse.amina@hospital.test', 'nurse', 'a-different-password')).status, 401);
  });

  it('refuses to create a new account without a password', async () => {
    store = new MemoryStore();
    const withoutPassword = account();
    delete withoutPassword.password;
    await assert.rejects(
      seedAccounts(store, parseAccounts(JSON.stringify([withoutPassword])), 1024),
      /new accounts need a password:\n {2}nurse\.amina@hospital\.test/,
    );
    assert.equal(await store.findUserByEmail('nurse.amina@hospital.test'), null);
  });
});
