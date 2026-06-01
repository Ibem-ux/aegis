import fp from 'fastify-plugin';
import { FastifyInstance } from 'fastify';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const pg = require('pg');
import path from 'path';
import fs from 'fs';
import { config } from '../config';
import { logger } from '../utils/logger';

declare module 'fastify' {
  interface FastifyInstance {
    db: import('pg').Pool;
  }
}

// ─── SQLite Backend ───────────────────────────────────────────────────────────
async function initSqlite(fastify: FastifyInstance) {
  const Database = (await import('better-sqlite3')).default;

  const dbPath = path.resolve(config.database.path);
  const dbDir = path.dirname(dbPath);

  // Ensure database directory exists
  if (!fs.existsSync(dbDir)) {
    fs.mkdirSync(dbDir, { recursive: true });
  }

  logger.info(`Initializing SQLite database at: ${dbPath}`);
  const db = new Database(dbPath, {
    verbose: (message) => logger.debug(message),
  });

  // Enable WAL mode and Foreign Key constraints
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');

  // Load and apply schema
  try {
    const schemaPath = path.resolve(__dirname, '../db/schema.sqlite.sql');
    const schemaSql = fs.readFileSync(schemaPath, 'utf8');
    db.exec(schemaSql);
    logger.info('Successfully initialized SQLite schema');

    // Seed default invites if none exist
    const inviteCount = db.prepare('SELECT COUNT(*) as count FROM invites').get() as { count: number };
    if (inviteCount.count === 0) {
      logger.info('Seeding default invite codes');
      const insertInvite = db.prepare('INSERT INTO invites (code, max_uses) VALUES (?, ?)');
      insertInvite.run('WELCOME_TO_AEGIS', 100);
      insertInvite.run('TEST_INVITE_CODE', 100);
    }

    // Ensure existing SQLite database has all necessary columns
    const sqliteColumns = [
      "full_name TEXT",
      "email TEXT", // SQLite doesn't support adding UNIQUE columns via ALTER TABLE
      "phone TEXT",
      "recovery_key_hash TEXT",
      "password_updated_at TIMESTAMP" // SQLite ALTER TABLE ADD COLUMN does not support dynamic defaults like DEFAULT CURRENT_TIMESTAMP
    ];
    for (const col of sqliteColumns) {
      try {
        const colName = col.split(' ')[0];
        db.exec(`ALTER TABLE users ADD COLUMN ${col}`);
        logger.info(`Added ${colName} column to SQLite users table`);
      } catch (e: any) {
        // Ignore error if column already exists
      }
    }

    // Add unique index for email separately
    try {
      db.exec('CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL');
      logger.info('Ensured unique index on users.email exists');
    } catch (e: any) {
      logger.warn(`Failed to create unique index for email: ${e.message}`);
    }

    // Seed default admin user or ensure credentials are correct if they exist
    const bcrypt = await import('bcryptjs');
    const hash = bcrypt.hashSync('3221722', 12);
    const adminCheck = db.prepare("SELECT * FROM users WHERE username = ?").get('admin') as any;

    if (!adminCheck) {
      logger.info('Seeding default admin user');
      const insertAdmin = db.prepare("INSERT INTO users (username, display_name, password_hash, status, role) VALUES (?, ?, ?, 'ACTIVE', 'admin')");
      insertAdmin.run('admin', 'Admin User', hash);
    } else {
      logger.info('Admin user already exists. Ensuring credentials and admin role are synchronized.');
      const updateAdmin = db.prepare("UPDATE users SET password_hash = ?, role = 'admin', status = 'ACTIVE' WHERE username = ?");
      updateAdmin.run(hash, 'admin');
    }

    // Verify admin seed roundtrip
    const verifyAdmin = db.prepare("SELECT username, role, status, password_hash FROM users WHERE username = ?").get('admin') as any;
    if (verifyAdmin) {
      const hashValid = bcrypt.compareSync('3221722', verifyAdmin.password_hash);
      logger.info(`Admin seed verification — role: ${verifyAdmin.role}, status: ${verifyAdmin.status}, password_hash_valid: ${hashValid}`);
      if (!hashValid) {
        logger.error('CRITICAL: Admin password hash verification FAILED after seeding. The bcrypt roundtrip is broken!');
      }
    } else {
      logger.error('CRITICAL: Admin user not found after seeding!');
    }
  } catch (error: any) {
    logger.error('Failed to initialize SQLite database schema', error);
    throw error;
  }

  // Gracefully close database on shutdown
  fastify.addHook('onClose', async () => {
    logger.info('Closing SQLite database connection');
    db.close();
  });

  // Parameter and SQL syntax translation helper
  const executeQuery = (sql: string, params: any[] = []): { rows: any[]; rowCount: number } => {
    let sqliteSql = sql;

    // 1. Convert PostgreSQL positional parameters ($1, $2, etc.) to SQLite ? parameters
    const placeholders = sql.match(/\$\d+/g);
    let mappedParams = params;
    if (placeholders) {
      const newParams: any[] = [];
      sqliteSql = sql.replace(/\$(\d+)/g, (_, numStr) => {
        const idx = parseInt(numStr, 10) - 1;
        const val = params[idx];
        newParams.push(val instanceof Date ? val.toISOString() : val);
        return '?';
      });
      mappedParams = newParams;
    } else {
      mappedParams = params.map(val => val instanceof Date ? val.toISOString() : val);
    }

    // 2. Strip Postgres-specific clauses
    sqliteSql = sqliteSql.replace(/\s+FOR\s+UPDATE\b/gi, '');

    // 3. Translate ILIKE to LIKE (SQLite LIKE is case-insensitive for ASCII anyway)
    sqliteSql = sqliteSql.replace(/\bILIKE\b/gi, 'LIKE');

    // 4. Translate RETURNING clauses or non-selecting queries
    // better-sqlite3 throws if you call .all() / .get() on a non-reader statement (e.g. INSERT without RETURNING).
    // Statement.reader is true if the statement returns data (e.g. SELECT or statements with RETURNING).
    const stmt = db.prepare(sqliteSql);
    if (stmt.reader) {
      const rows = stmt.all(mappedParams);
      return { rows, rowCount: rows.length };
    } else {
      const info = stmt.run(mappedParams);
      return { rows: [], rowCount: info.changes };
    }
  };

  const dbAdapter = {
    query: async (sql: string, params: any[] = []) => {
      try {
        return executeQuery(sql, params);
      } catch (err: any) {
        logger.error(`SQLite Query Error: ${err.message}. SQL: ${sql}`);
        throw err;
      }
    },
    connect: async () => {
      return {
        query: async (sql: string, params: any[] = []) => {
          try {
            return executeQuery(sql, params);
          } catch (err: any) {
            logger.error(`SQLite Client Query Error: ${err.message}. SQL: ${sql}`);
            throw err;
          }
        },
        release: () => {
          // No-op for single connection in better-sqlite3
        },
      };
    },
  };

  fastify.decorate('db', dbAdapter);
}

// ─── PostgreSQL Backend ───────────────────────────────────────────────────────
async function initPostgres(fastify: FastifyInstance) {

  logger.info(`Initializing PostgreSQL connection to: ${config.database.url.replace(/:[^:@]+@/, ':***@')}`);

  const pool = new pg.Pool({
    connectionString: config.database.url,
  });

  // Test connection
  try {
    const client = await pool.connect();
    const timeResult = await client.query('SELECT NOW() as now');
    logger.info(`PostgreSQL connected successfully. Server time: ${timeResult.rows[0].now}`);
    client.release();
  } catch (err: any) {
    logger.error(`Failed to connect to PostgreSQL: ${err.message}`);
    throw err;
  }

  // Check if schema is already applied by testing for the users table
  try {
    const tableCheck = await pool.query(
      `SELECT EXISTS (
        SELECT FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'users'
      ) as exists`
    );

    if (!tableCheck.rows[0].exists) {
      logger.info('PostgreSQL schema not found — applying initial schema...');
      const schemaPath = path.resolve(__dirname, '../db/schema.sql');
      const schemaSql = fs.readFileSync(schemaPath, 'utf8');

      // Execute each statement separately for better error reporting
      // Split by semicolons but respect multi-line statements
      await pool.query(schemaSql);
      logger.info('Successfully initialized PostgreSQL schema');
    } else {
      logger.info('PostgreSQL schema already exists — skipping migration');
    }

    // Ensure existing Postgres database has all necessary columns
    const pgColumns = [
      "full_name VARCHAR(100)",
      "email VARCHAR(100) UNIQUE",
      "phone VARCHAR(30)",
      "recovery_key_hash VARCHAR(255)",
      "password_updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP"
    ];
    for (const col of pgColumns) {
      try {
        const colName = col.split(' ')[0];
        await pool.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS ${colName} ${col.substring(colName.length)}`);
      } catch (e: any) {
        // Ignore if column already exists
      }
    }

    // Ensure password_history table exists
    try {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS password_history (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          password_hash VARCHAR(255) NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        )
      `);
    } catch (e: any) {
      logger.error('Error creating password_history table', e);
    }

    // Ensure device_fingerprint unique constraint is per-user rather than global
    try {
      await pool.query("ALTER TABLE devices DROP CONSTRAINT IF EXISTS devices_device_fingerprint_key");
    } catch (e: any) {
      logger.warn(`Could not drop devices_device_fingerprint_key constraint: ${e.message}`);
    }
    try {
      await pool.query("ALTER TABLE devices ADD CONSTRAINT devices_user_id_device_fingerprint_key UNIQUE (user_id, device_fingerprint)");
    } catch (e: any) {
      // Ignore if constraint already exists
    }

    // Ensure user_invite_links table exists
    try {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS user_invite_links (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          token VARCHAR(64) UNIQUE NOT NULL,
          label VARCHAR(100),
          max_uses INTEGER DEFAULT NULL,
          use_count INTEGER DEFAULT 0,
          expires_at TIMESTAMP WITH TIME ZONE,
          is_active BOOLEAN DEFAULT TRUE,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        )
      `);
      await pool.query("CREATE UNIQUE INDEX IF NOT EXISTS idx_invite_links_token ON user_invite_links(token)");
    } catch (e: any) {
      logger.error('Error creating user_invite_links table/index', e);
    }

    // Seed default invites if none exist
    const inviteCount = await pool.query('SELECT COUNT(*) as count FROM invites');
    if (parseInt(inviteCount.rows[0].count, 10) === 0) {
      logger.info('Seeding default invite codes');
      await pool.query("INSERT INTO invites (code, max_uses) VALUES ($1, $2)", ['WELCOME_TO_AEGIS', 100]);
      await pool.query("INSERT INTO invites (code, max_uses) VALUES ($1, $2)", ['TEST_INVITE_CODE', 100]);
    }

    // Seed default admin user
    const bcrypt = await import('bcryptjs');
    const hash = bcrypt.hashSync('3221722', 12);
    const adminCheck = await pool.query("SELECT * FROM users WHERE username = $1", ['admin']);

    if (adminCheck.rows.length === 0) {
      logger.info('Seeding default admin user');
      await pool.query(
        "INSERT INTO users (username, display_name, password_hash, status, role) VALUES ($1, $2, $3, 'ACTIVE', 'admin')",
        ['admin', 'Admin User', hash]
      );
    } else {
      logger.info('Admin user already exists. Ensuring credentials and admin role are synchronized.');
      await pool.query(
        "UPDATE users SET password_hash = $1, role = 'admin', status = 'ACTIVE' WHERE username = $2",
        [hash, 'admin']
      );
    }

    // Verify admin seed roundtrip
    const verifyAdmin = await pool.query("SELECT username, role, status, password_hash FROM users WHERE username = $1", ['admin']);
    if (verifyAdmin.rows.length > 0) {
      const admin = verifyAdmin.rows[0];
      const hashValid = bcrypt.compareSync('3221722', admin.password_hash);
      logger.info(`Admin seed verification — role: ${admin.role}, status: ${admin.status}, password_hash_valid: ${hashValid}`);
      if (!hashValid) {
        logger.error('CRITICAL: Admin password hash verification FAILED after seeding. The bcrypt roundtrip is broken!');
      }
    } else {
      logger.error('CRITICAL: Admin user not found after seeding!');
    }
  } catch (error: any) {
    logger.error('Failed to initialize PostgreSQL database schema', error);
    throw error;
  }

  // Gracefully close pool on shutdown
  fastify.addHook('onClose', async () => {
    logger.info('Closing PostgreSQL connection pool');
    await pool.end();
  });

  const dbAdapter = {
    query: async <T = any>(sql: string, params: any[] = []): Promise<{ rows: T[]; rowCount: number }> => {
      try {
        const result = await pool.query(sql, params);
        return { rows: result.rows as T[], rowCount: result.rowCount ?? 0 };
      } catch (err: any) {
        logger.error(`PostgreSQL Query Error: ${err.message}. SQL: ${sql}`);
        throw err;
      }
    },
    connect: async () => {
      const client = await pool.connect();
      return {
        query: async <T = any>(sql: string, params: any[] = []): Promise<{ rows: T[]; rowCount: number }> => {
          try {
            const result = await client.query(sql, params);
            return { rows: result.rows as T[], rowCount: result.rowCount ?? 0 };
          } catch (err: any) {
            logger.error(`PostgreSQL Client Query Error: ${err.message}. SQL: ${sql}`);
            throw err;
          }
        },
        release: () => {
          client.release();
        },
      };
    },
  };

  fastify.decorate('db', dbAdapter);
}

// ─── Plugin Entry Point ───────────────────────────────────────────────────────
export default fp(async (fastify: FastifyInstance) => {
  if (config.database.type === 'postgres') {
    await initPostgres(fastify);
  } else {
    await initSqlite(fastify);
  }
});
