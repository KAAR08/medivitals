// Runtime configuration from IDENTITY_* environment variables.

import { readFileSync } from 'node:fs';

const env = process.env;

// Secrets can be mounted as files (Docker/Kubernetes secrets) via *_FILE.
// The path and name come from the operator's deployment config, never from a
// request, so the generic "non-literal" security warnings don't apply here.
export function secret(name) {
  const file = env[`${name}_FILE`];
  // eslint-disable-next-line security/detect-non-literal-fs-filename, security/detect-object-injection
  return (file ? readFileSync(file, 'utf8') : env[name])?.trim();
}

// The database password is kept out of the URL (and out of `docker inspect`).
function withPassword(url, password) {
  if (!password) return url;
  const u = new URL(url);
  u.password = encodeURIComponent(password);
  return u.toString();
}

export function loadConfig(overrides = {}) {
  return {
    port: Number(env.IDENTITY_PORT ?? 4000),
    production: env.NODE_ENV === 'production',
    mongoUrl: withPassword(
      env.IDENTITY_MONGO_URL ?? 'mongodb://127.0.0.1:27017/medvitals_identity',
      secret('IDENTITY_MONGO_PASSWORD'),
    ),
    // PKCS#8 PEM. Required in production; generated per process otherwise.
    jwtPrivateKey: secret('IDENTITY_JWT_PRIVATE_KEY'),
    issuer: env.IDENTITY_ISSUER ?? 'medvitals-identity',
    audience: env.IDENTITY_AUDIENCE ?? 'medvitals-api',
    accessTokenTtlSeconds: Number(env.IDENTITY_ACCESS_TTL ?? 600), // 10 minutes
    refreshTokenTtlSeconds: Number(env.IDENTITY_REFRESH_TTL ?? 7 * 24 * 3600),
    // scrypt cost (N), used with r=8, p=5 (OWASP minimum; see passwords.js).
    // Tests lower it for speed.
    scryptCost: Number(env.IDENTITY_SCRYPT_COST ?? 2 ** 14),
    // Brute-force protection: attempts per IP per 15 minutes.
    loginRateLimit: Number(env.IDENTITY_LOGIN_RATE_LIMIT ?? 10),
    // Password hashes running at once, and how many more may wait (see passwords.js).
    maxConcurrentHashes: Number(env.IDENTITY_MAX_CONCURRENT_HASHES ?? 2),
    hashQueueLimit: Number(env.IDENTITY_HASH_QUEUE_LIMIT ?? 20),
    trustProxy: env.IDENTITY_TRUST_PROXY ?? 'loopback, uniquelocal',
    ...overrides,
  };
}
