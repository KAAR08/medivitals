// Seeds the ward's accounts.
//
// On a server: IDENTITY_SEED_ACCOUNTS(_FILE) is a JSON list of accounts, each
// with its own initial password (scripts/generate_dev_secrets.py writes one to
// secrets/accounts.json). Without it, the demo users below are seeded with the
// shared IDENTITY_SEED_PASSWORD. There is no built-in default password, so no
// well-known password ships with the code.
//
// Seeding only creates accounts that don't exist yet; it never changes an
// existing account or its password. Once the accounts exist, delete the
// "password" lines from the file: MongoDB then holds only scrypt hashes.
//
// The patient UUIDs match the biometric simulator and the app's mock data:
// renaming those patients is fine, changing their ids stops their vitals.

import { randomUUID } from 'node:crypto';

import { loadConfig, secret } from './config.js';
import { hashPassword } from './passwords.js';
import { MongoStore } from './store.js';

export const DEMO_USERS = [
  {
    id: 'b3f1c2e4-5d6a-4b7c-8e9f-0a1b2c3d4e5f',
    email: 'dr.sarah@medvitals.com',
    name: 'Dr. Sarah Mitchell',
    role: 'doctor',
    specialization: 'Cardiology',
  },
  {
    id: 'c4a2d3f5-6e7b-4c8d-9f0a-1b2c3d4e5f60',
    email: 'grace.wanjiru@medvitals.com',
    name: 'Nurse Grace Wanjiru',
    role: 'nurse',
    specialization: 'Cardiac triage',
  },
  { id: '7c9e6679-7425-40de-944b-e07fc1f90ae7', email: 'john.doe@example.com', name: 'John Doe', role: 'patient' },
  { id: '2f1a8b3c-9d4e-4f5a-8b6c-7d8e9f0a1b2c', email: 'jane.smith@example.com', name: 'Jane Smith', role: 'patient' },
  { id: '9a8b7c6d-5e4f-4a3b-9c2d-1e0f9a8b7c6d', email: 'bob.wilson@example.com', name: 'Bob Wilson', role: 'patient' },
];

const ROLES = new Set(['doctor', 'nurse', 'patient']);
const MIN_PASSWORD = 12;

/** Validates an accounts list; throws with every problem found. */
export function parseAccounts(json) {
  const accounts = JSON.parse(json);
  if (!Array.isArray(accounts) || accounts.length === 0) {
    throw new Error('accounts: expected a non-empty JSON list');
  }
  const problems = [];
  const emails = new Set();
  const ids = new Set();
  const parsed = accounts.map((a, i) => {
    const where = `account ${i + 1}${a?.email ? ` (${a.email})` : ''}`;
    if (typeof a?.email !== 'string' || !/^[^@\s]+@[^@\s]+$/.test(a.email)) problems.push(`${where}: email`);
    if (typeof a?.name !== 'string' || !a.name.trim()) problems.push(`${where}: name`);
    if (!ROLES.has(a?.role)) problems.push(`${where}: role must be doctor, nurse or patient`);
    // Optional: an account that already exists needs none (see seedAccounts).
    if (a?.password !== undefined && (typeof a.password !== 'string' || a.password.length < MIN_PASSWORD)) {
      problems.push(`${where}: password needs ${MIN_PASSWORD}+ characters`);
    }
    const email = String(a?.email ?? '').toLowerCase();
    const id = a?.id ?? randomUUID();
    if (emails.has(email)) problems.push(`${where}: duplicate email`);
    if (ids.has(id)) problems.push(`${where}: duplicate id`);
    emails.add(email);
    ids.add(id);
    return {
      id,
      email,
      name: a?.name?.trim(),
      role: a?.role,
      password: a?.password,
      ...(a?.specialization ? { specialization: a.specialization } : {}),
    };
  });
  if (problems.length) throw new Error(`accounts:\n  ${problems.join('\n  ')}`);
  return parsed;
}

/**
 * Creates the accounts that don't exist yet (matched by id or email), each with
 * its own password. Existing accounts are left exactly as they are.
 */
export async function seedAccounts(store, accounts, cost) {
  const created = [];
  const existing = [];
  const missingPassword = [];
  for (const account of accounts) {
    const found = (account.id && (await store.findUserById(account.id))) || (await store.findUserByEmail(account.email));
    if (found) existing.push(account.email);
    else if (!account.password) missingPassword.push(account.email);
  }
  if (missingPassword.length) {
    throw new Error(`accounts: new accounts need a password:\n  ${missingPassword.join('\n  ')}`);
  }
  for (const { password, ...user } of accounts) {
    if (existing.includes(user.email)) continue;
    await store.upsertUser({ ...user, passwordHash: await hashPassword(password, cost), createdAt: new Date() });
    created.push(user.email);
  }
  return { created, existing };
}

/** The demo users, all with one shared password (local development, tests). */
export async function seed(store, password, cost) {
  await seedAccounts(
    store,
    DEMO_USERS.map((u) => ({ ...u, password })),
    cost,
  );
}

if (import.meta.url === `file://${process.argv[1].replace(/\\/g, '/')}` || process.argv[1]?.endsWith('seed.js')) {
  const config = loadConfig();
  const accountsJson = secret('IDENTITY_SEED_ACCOUNTS');
  let accounts;
  try {
    if (accountsJson) {
      accounts = parseAccounts(accountsJson);
    } else {
      const password = secret('IDENTITY_SEED_PASSWORD');
      if (!password || password.length < MIN_PASSWORD) {
        throw new Error(
          'Set IDENTITY_SEED_ACCOUNTS_FILE (per-account passwords) or IDENTITY_SEED_PASSWORD_FILE (12+ characters).',
        );
      }
      accounts = DEMO_USERS.map((u) => ({ ...u, password }));
    }
  } catch (err) {
    console.error(err.message);
    process.exit(1);
  }
  const store = await MongoStore.connect(config.mongoUrl);
  try {
    const { created, existing } = await seedAccounts(store, accounts, config.scryptCost);
    console.log(`Accounts: ${created.length} created, ${existing.length} already existed (unchanged).`);
    for (const email of created) console.log(`  created ${email}`);
  } catch (err) {
    console.error(err.message);
    process.exitCode = 1;
  } finally {
    await store.close();
  }
}
