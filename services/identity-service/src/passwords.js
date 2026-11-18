// scrypt password hashes, stored as scrypt$N$r$p$salt$hash so the parameters
// can change without invalidating old hashes. N=2^14, r=8, p=5 is one of
// OWASP's recommended settings and needs 16 MiB per hash (N=2^17, p=1 needs
// 128 MiB), which matters on a small server.

import { randomBytes, scrypt as scryptCb, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCb);
const KEY_LENGTH = 64;
const BLOCK_SIZE = 8;
const PARALLELISM = 5;

function maxmem(cost) {
  // scrypt needs ~128 * N * r bytes; leave headroom.
  return 256 * cost * BLOCK_SIZE;
}

export async function hashPassword(password, cost) {
  const salt = randomBytes(16);
  const hash = await scrypt(password.normalize('NFKC'), salt, KEY_LENGTH, {
    N: cost,
    r: BLOCK_SIZE,
    p: PARALLELISM,
    maxmem: maxmem(cost),
  });
  return ['scrypt', cost, BLOCK_SIZE, PARALLELISM, salt.toString('base64url'), hash.toString('base64url')].join('$');
}

export async function verifyPassword(password, stored) {
  const [scheme, n, r, p, saltB64, hashB64] = stored.split('$');
  if (scheme !== 'scrypt') return false;
  const expected = Buffer.from(hashB64, 'base64url');
  const actual = await scrypt(password.normalize('NFKC'), Buffer.from(saltB64, 'base64url'), expected.length, {
    N: Number(n),
    r: Number(r),
    p: Number(p),
    maxmem: maxmem(Number(n)),
  });
  return timingSafeEqual(actual, expected);
}

export class BusyError extends Error {}

/**
 * Caps how many password hashes run at once. scrypt is deliberately
 * expensive and runs on libuv's small thread pool, so a burst of logins
 * (an attack, or a crowd) could starve everything else in the service. At
 * most `concurrency` run; up to `maxQueue` wait; beyond that a login fails
 * fast with BusyError instead of piling up.
 */
export function hashingGate(concurrency, maxQueue) {
  let active = 0;
  const waiting = [];
  return async function run(task) {
    if (active < concurrency) {
      active += 1;
    } else {
      if (waiting.length >= maxQueue) throw new BusyError('Too many sign-ins at once');
      await new Promise((resolve) => waiting.push(resolve)); // a finishing task hands us its slot
    }
    try {
      return await task();
    } finally {
      const next = waiting.shift();
      if (next) next();
      else active -= 1;
    }
  };
}

