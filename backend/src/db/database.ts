import sqlite3 from 'sqlite3';
import { open, Database } from 'sqlite';
import { Pool } from 'pg';
import path from 'path';

export interface AppDatabase {
  get<T = any>(sql: string, params?: any[]): Promise<T | undefined>;
  all<T = any>(sql: string, params?: any[]): Promise<T[]>;
  run(sql: string, params?: any[]): Promise<{ lastID?: number | bigint; changes?: number }>;
  exec(sql: string): Promise<void>;
}

class SqliteDatabase implements AppDatabase {
  constructor(private db: Database) {}

  async get<T = any>(sql: string, params: any[] = []): Promise<T | undefined> {
    return await this.db.get(sql, params);
  }

  async all<T = any>(sql: string, params: any[] = []): Promise<T[]> {
    return await this.db.all(sql, params);
  }

  async run(sql: string, params: any[] = []): Promise<{ lastID?: number | bigint; changes?: number }> {
    return await this.db.run(sql, params);
  }

  async exec(sql: string): Promise<void> {
    await this.db.exec(sql);
  }
}

class PostgresDatabase implements AppDatabase {
  constructor(private pool: Pool) {}

  private prepare(sql: string): string {
    let clean = sql.replace(/COLLATE\s+NOCASE/gi, '');
    let idx = 1;
    clean = clean.replace(/\?/g, () => `$${idx++}`);
    return clean;
  }

  async get<T = any>(sql: string, params: any[] = []): Promise<T | undefined> {
    const res = await this.pool.query(this.prepare(sql), params);
    return (res.rows[0] as T) || undefined;
  }

  async all<T = any>(sql: string, params: any[] = []): Promise<T[]> {
    const res = await this.pool.query(this.prepare(sql), params);
    return res.rows as T[];
  }

  async run(sql: string, params: any[] = []): Promise<{ lastID?: number | bigint; changes?: number }> {
    const res = await this.pool.query(this.prepare(sql), params);
    return { changes: res.rowCount ?? 0 };
  }

  async exec(sql: string): Promise<void> {
    const statements = sql
      .split(';')
      .map((s) => s.trim())
      .filter((s) => s.length > 0);

    for (const stmt of statements) {
      try {
        await this.pool.query(this.prepare(stmt));
      } catch (err: any) {
        // Ignore duplicate column errors during migrations
        if (!err.message?.includes('already exists')) {
          console.warn('[Postgres Migration Notice]', err.message);
        }
      }
    }
  }
}

let dbInstance: AppDatabase | null = null;

export async function getDb(): Promise<AppDatabase> {
  if (dbInstance) {
    return dbInstance;
  }

  const databaseUrl = process.env.DATABASE_URL;

  if (databaseUrl && (databaseUrl.startsWith('postgres://') || databaseUrl.startsWith('postgresql://'))) {
    console.log('[Database] Connecting to persistent cloud PostgreSQL database...');
    const pool = new Pool({
      connectionString: databaseUrl,
      ssl: databaseUrl.includes('localhost') ? false : { rejectUnauthorized: false }
    });
    dbInstance = new PostgresDatabase(pool);
  } else {
    console.log('[Database] Using local SQLite database engine (tisaal.sqlite)...');
    const dbPath = path.resolve(__dirname, '../../tisaal.sqlite');
    const sqliteDb = await open({
      filename: dbPath,
      driver: sqlite3.Database
    });
    dbInstance = new SqliteDatabase(sqliteDb);
  }

  await initSchema(dbInstance);
  return dbInstance;
}

async function initSchema(db: AppDatabase) {
  await db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      account_id TEXT UNIQUE NOT NULL,
      public_key TEXT NOT NULL,
      public_encryption_key TEXT NOT NULL DEFAULT '',
      username TEXT UNIQUE NOT NULL,
      display_name TEXT,
      bio TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
    CREATE INDEX IF NOT EXISTS idx_users_account_id ON users(account_id);

    CREATE TABLE IF NOT EXISTS auth_nonces (
      account_id TEXT PRIMARY KEY,
      nonce TEXT NOT NULL,
      expires_at TIMESTAMP NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS contacts (
      id TEXT PRIMARY KEY,
      sender_account_id TEXT NOT NULL,
      receiver_account_id TEXT NOT NULL,
      status TEXT CHECK(status IN ('pending', 'accepted', 'rejected', 'blocked')) DEFAULT 'pending',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(sender_account_id, receiver_account_id)
    );

    CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      conversation_id TEXT NOT NULL,
      sender_account_id TEXT NOT NULL,
      receiver_account_id TEXT NOT NULL,
      content TEXT DEFAULT '',
      ephemeral_public_key TEXT NOT NULL DEFAULT '',
      nonce TEXT NOT NULL DEFAULT '',
      ciphertext TEXT NOT NULL DEFAULT '',
      auth_tag TEXT NOT NULL DEFAULT '',
      message_type TEXT DEFAULT 'text',
      is_delivered INTEGER DEFAULT 0,
      is_read INTEGER DEFAULT 0,
      client_temp_id TEXT DEFAULT '',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id);
    CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages(receiver_account_id);

    CREATE TABLE IF NOT EXISTS call_logs (
      id TEXT PRIMARY KEY,
      caller_account_id TEXT NOT NULL,
      callee_account_id TEXT NOT NULL,
      call_type TEXT DEFAULT 'audio',
      status TEXT DEFAULT 'ringing',
      duration_seconds INTEGER DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_calls_caller ON call_logs(caller_account_id);
    CREATE INDEX IF NOT EXISTS idx_calls_callee ON call_logs(callee_account_id);
  `);

  // Migrate columns gracefully if needed
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
}
