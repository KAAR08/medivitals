import { createApp } from './app.js';
import { loadConfig } from './config.js';
import { MongoStore } from './store.js';
import { KeyRing } from './tokens.js';

const config = loadConfig();

if (config.production && !config.jwtPrivateKey) {
  console.error('IDENTITY_JWT_PRIVATE_KEY is required in production');
  process.exit(1);
}

const keys = new KeyRing(config.jwtPrivateKey);
if (keys.ephemeral) {
  console.warn('No IDENTITY_JWT_PRIVATE_KEY: using a temporary key; all tokens die on restart.');
}

const store = await MongoStore.connect(config.mongoUrl);
const app = await createApp({ config, store, keys });

const server = app.listen(config.port, () => {
  console.log(`Identity service listening on :${config.port} (kid ${keys.kid})`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    server.close(async () => {
      await store.close();
      process.exit(0);
    });
  });
}
