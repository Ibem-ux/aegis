import fp from 'fastify-plugin';
import { FastifyInstance } from 'fastify';
import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import { config } from '../config';
import { logger } from '../utils/logger';

declare module 'fastify' {
  interface FastifyInstance {
    db: {
      query<T = any>(sql: string, params?: any[]): Promise<{ rows: T[]; rowCount: number }>;
      connect(): Promise<{
        query<T = any>(sql: string, params?: any[]): Promise<{ rows: T[]; rowCount: number }>;
        release(): void;
      }>;
    };
  }
}

export default fp(async (fastify: FastifyInstance) => {
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
});
