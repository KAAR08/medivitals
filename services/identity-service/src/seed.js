// Seeds the demo ward. The UUIDs match the biometric simulator and the app's
// mock data. The demo password comes from IDENTITY_SEED_PASSWORD; there is no
// built-in default, so no well-known password ships with the code.

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

export async function seed(store, password, cost) {
  for (const user of DEMO_USERS) {
    await store.upsertUser({ ...user, passwordHash: await hashPassword(password, cost), createdAt: new Date() });
  }
}

if (import.meta.url === `file://${process.argv[1].replace(/\\/g, '/')}` || process.argv[1]?.endsWith('seed.js')) {
  const password = secret('IDENTITY_SEED_PASSWORD');
  if (!password || password.length < 12) {
    console.error('Set IDENTITY_SEED_PASSWORD or IDENTITY_SEED_PASSWORD_FILE (12+ characters) to seed the demo users.');
    process.exit(1);
  }
  const config = loadConfig();
  const store = await MongoStore.connect(config.mongoUrl);
  await seed(store, password, config.scryptCost);
  console.log(`Seeded ${DEMO_USERS.length} demo users.`);
  await store.close();
}
