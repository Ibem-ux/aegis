import fp from 'fastify-plugin';
import { FastifyInstance } from 'fastify';
import { Pool } from 'pg';
import { dbConfig } from '../config/database';
import { logger } from '../utils/logger';

declare module 'fastify' {
  interface FastifyInstance {
    db: Pool;
  }
}

export default fp(async (fastify: FastifyInstance) => {
  const pool = new Pool(dbConfig);

  // Test the connection
  try {
    const client = await pool.connect();
    logger.info('Successfully connected to PostgreSQL database');
    client.release();
  } catch (error) {
    logger.error('Failed to connect to PostgreSQL database', error);
    throw error;
  }

  // Gracefully close pool on shutdown
  fastify.addHook('onClose', async () => {
    logger.info('Closing PostgreSQL database connection pool');
    await pool.end();
  });

  fastify.decorate('db', pool);
});
