import fp from 'fastify-plugin';
import { FastifyInstance } from 'fastify';
import { createClient, RedisClientType } from 'redis';
import { redisConfig } from '../config/redis';
import { logger } from '../utils/logger';

declare module 'fastify' {
  interface FastifyInstance {
    redis: RedisClientType;
  }
}

export default fp(async (fastify: FastifyInstance) => {
  const client = createClient(redisConfig);

  client.on('error', (err) => logger.error('Redis Client Error', err));
  client.on('connect', () => logger.info('Redis Client Connecting'));
  client.on('ready', () => logger.info('Redis Client Connected and Ready'));

  try {
    await client.connect();
  } catch (error) {
    logger.error('Failed to connect to Redis', error);
    throw error;
  }

  // Gracefully close redis on shutdown
  fastify.addHook('onClose', async () => {
    logger.info('Closing Redis client connection');
    await client.quit();
  });

  fastify.decorate('redis', client as any);
});
