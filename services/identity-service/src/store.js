// Persistence behind one small interface, so the routes don't know whether
// MongoDB (deployments) or memory (tests) is underneath.
//
// User:         { id (UUID), email, name, role, specialization?, passwordHash, createdAt }
// RefreshToken: { tokenHash, userId, familyId, expiresAt, usedAt, revokedAt }

export class MemoryStore {
  constructor() {
    this.users = new Map();
    this.tokens = new Map();
  }

  async findUserByEmail(email) {
    for (const u of this.users.values()) if (u.email === email) return u;
    return null;
  }

  async findUserById(id) {
    return this.users.get(id) ?? null;
  }

  async listUsersByRole(role) {
    return [...this.users.values()].filter((u) => u.role === role);
  }

  async upsertUser(user) {
    this.users.set(user.id, { ...user });
  }

  async insertRefreshToken(record) {
    this.tokens.set(record.tokenHash, { ...record, usedAt: null, revokedAt: null });
  }

  async findRefreshToken(tokenHash) {
    return this.tokens.get(tokenHash) ?? null;
  }

  // Atomically marks a token used; returns false if it was already used/revoked.
  async consumeRefreshToken(tokenHash, now) {
    const t = this.tokens.get(tokenHash);
    if (!t || t.usedAt || t.revokedAt) return false;
    t.usedAt = now;
    return true;
  }

  async revokeFamily(familyId, now) {
    for (const t of this.tokens.values()) if (t.familyId === familyId && !t.revokedAt) t.revokedAt = now;
  }

  async ping() {
    return true;
  }

  async close() {}
}

export class MongoStore {
  constructor(client) {
    this.client = client;
    const db = client.db();
    this.users = db.collection('users');
    this.tokens = db.collection('refresh_tokens');
  }

  static async connect(url) {
    const { MongoClient } = await import('mongodb');
    const client = new MongoClient(url, { serverSelectionTimeoutMS: 5000 });
    await client.connect();
    const store = new MongoStore(client);
    await store.users.createIndex({ email: 1 }, { unique: true });
    await store.users.createIndex({ role: 1 });
    await store.tokens.createIndex({ tokenHash: 1 }, { unique: true });
    await store.tokens.createIndex({ familyId: 1 });
    // MongoDB deletes expired refresh tokens on its own.
    await store.tokens.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });
    return store;
  }

  #fromDoc(doc) {
    if (!doc) return null;
    const { _id, ...rest } = doc;
    return { id: _id, ...rest };
  }

  async findUserByEmail(email) {
    // Typed query: the value is a string from the validated body, never an object,
    // so operator injection ({"$ne": ...}) is impossible.
    return this.#fromDoc(await this.users.findOne({ email: String(email) }));
  }

  async findUserById(id) {
    return this.#fromDoc(await this.users.findOne({ _id: String(id) }));
  }

  async listUsersByRole(role) {
    return (await this.users.find({ role: String(role) }).sort({ name: 1 }).toArray()).map((d) => this.#fromDoc(d));
  }

  async upsertUser(user) {
    const { id, ...rest } = user;
    await this.users.updateOne({ _id: id }, { $set: rest }, { upsert: true });
  }

  async insertRefreshToken(record) {
    await this.tokens.insertOne({ ...record, usedAt: null, revokedAt: null });
  }

  async findRefreshToken(tokenHash) {
    return this.tokens.findOne({ tokenHash: String(tokenHash) });
  }

  async consumeRefreshToken(tokenHash, now) {
    const result = await this.tokens.updateOne(
      { tokenHash: String(tokenHash), usedAt: null, revokedAt: null },
      { $set: { usedAt: now } },
    );
    return result.modifiedCount === 1;
  }

  async revokeFamily(familyId, now) {
    await this.tokens.updateMany({ familyId, revokedAt: null }, { $set: { revokedAt: now } });
  }

  async ping() {
    try {
      await this.client.db().command({ ping: 1 });
      return true;
    } catch {
      return false;
    }
  }

  async close() {
    await this.client.close();
  }
}
