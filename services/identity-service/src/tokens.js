// Access tokens: short-lived RS256 JWTs. Other services verify them with the
// public key published at /.well-known/jwks.json; only this service can sign.
//
// Refresh tokens: random 256-bit opaque strings. Only their SHA-256 hash is
// stored. Each one is single-use: refreshing returns a new pair, and presenting
// an already-used token revokes its whole family (stolen-token detection).

import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, randomBytes, randomUUID } from 'node:crypto';
import { exportJWK, SignJWT } from 'jose';

export class KeyRing {
  constructor(privateKeyPem) {
    if (privateKeyPem) {
      this.privateKey = createPrivateKey(privateKeyPem);
    } else {
      ({ privateKey: this.privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 }));
      this.ephemeral = true;
    }
    this.publicKey = createPublicKey(this.privateKey);
    // Key ID = fingerprint of the public key, so rotation is visible to verifiers.
    const der = this.publicKey.export({ type: 'spki', format: 'der' });
    this.kid = createHash('sha256').update(der).digest('base64url').slice(0, 16);
  }

  async jwks() {
    const jwk = await exportJWK(this.publicKey);
    return { keys: [{ ...jwk, kid: this.kid, alg: 'RS256', use: 'sig' }] };
  }
}

export async function signAccessToken(keys, config, user) {
  return new SignJWT({ role: user.role })
    .setProtectedHeader({ alg: 'RS256', kid: keys.kid, typ: 'JWT' })
    .setSubject(user.id)
    .setIssuer(config.issuer)
    .setAudience(config.audience)
    .setIssuedAt()
    .setJti(randomUUID())
    .setExpirationTime(`${config.accessTokenTtlSeconds}s`)
    .sign(keys.privateKey);
}

export function newRefreshToken() {
  return randomBytes(32).toString('base64url');
}

export function hashToken(token) {
  return createHash('sha256').update(token).digest('hex');
}
