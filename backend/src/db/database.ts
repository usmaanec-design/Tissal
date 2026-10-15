import sqlite3 from 'sqlite3';
import { open, Database } from 'sqlite';
import path from 'path';

let dbInstance: Database | null = null;

export async function getDb(): Promise<Database> {
  if (dbInstance) {
    return dbInstance;
  }

  const dbPath = path.resolve(__dirname, '../../tisaal.sqlite');
  dbInstance = await open({
    filename: dbPath,
    driver: sqlite3.Database
  });

  await initSchema(dbInstance);
  return dbInstance;
}

async function initSchema(db: Database) {
  await db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      account_id TEXT UNIQUE NOT NULL,
      public_key TEXT NOT NULL,
      public_encryption_key TEXT NOT NULL DEFAULT '',
      username TEXT UNIQUE NOT NULL COLLATE NOCASE,
      display_name TEXT,
      bio TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
    CREATE INDEX IF NOT EXISTS idx_users_account_id ON users(account_id);

    CREATE TABLE IF NOT EXISTS auth_nonces (
      account_id TEXT PRIMARY KEY,
      nonce TEXT NOT NULL,
      expires_at DATETIME NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS contacts (
      id TEXT PRIMARY KEY,
      sender_account_id TEXT NOT NULL,
      receiver_account_id TEXT NOT NULL,
      status TEXT CHECK(status IN ('pending', 'accepted', 'rejected', 'blocked')) DEFAULT 'pending',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(sender_account_id, receiver_account_id),
      FOREIGN KEY(sender_account_id) REFERENCES users(account_id),
      FOREIGN KEY(receiver_account_id) REFERENCES users(account_id)
    );

    CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      conversation_id TEXT NOT NULL,
      sender_account_id TEXT NOT NULL,
      receiver_account_id TEXT NOT NULL,
      ephemeral_public_key TEXT NOT NULL,
      nonce TEXT NOT NULL,
      ciphertext TEXT NOT NULL,
      auth_tag TEXT NOT NULL,
      message_type TEXT DEFAULT 'text',
      is_delivered INTEGER DEFAULT 0,
      is_read INTEGER DEFAULT 0,
      client_temp_id TEXT DEFAULT '',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS call_logs (
      id TEXT PRIMARY KEY,
      caller_account_id TEXT NOT NULL,
      callee_account_id TEXT NOT NULL,
      call_type TEXT DEFAULT 'audio',
      status TEXT DEFAULT 'ringing',
      duration_seconds INTEGER DEFAULT 0,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  `);

  // Migrate existing tables gracefully if needed
  try {
    await db.exec(`ALTER TABLE users ADD COLUMN public_encryption_key TEXT NOT NULL DEFAULT ''`);
  } catch (_) {}

  try {
    await db.exec(`ALTER TABLE messages ADD COLUMN ephemeral_public_key TEXT NOT NULL DEFAULT ''`);
    await db.exec(`ALTER TABLE messages ADD COLUMN nonce TEXT NOT NULL DEFAULT ''`);
    await db.exec(`ALTER TABLE messages ADD COLUMN ciphertext TEXT NOT NULL DEFAULT ''`);
    await db.exec(`ALTER TABLE messages ADD COLUMN auth_tag TEXT NOT NULL DEFAULT ''`);
  } catch (_) {}

  try {
    await db.exec(`ALTER TABLE messages ADD COLUMN client_temp_id TEXT NOT NULL DEFAULT ''`);
  } catch (_) {}

  try {
    await db.exec(`CREATE INDEX IF NOT EXISTS idx_messages_temp_id ON messages(conversation_id, client_temp_id)`);
  } catch (_) {}
}
