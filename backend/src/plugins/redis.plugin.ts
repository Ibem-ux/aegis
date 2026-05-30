import fp from 'fastify-plugin';
import { FastifyInstance } from 'fastify';
import { config } from '../config';
import { logger } from '../utils/logger';

declare module 'fastify' {
  interface FastifyInstance {
    redis: {
      sAdd(key: string, value: string): Promise<number>;
      sRem(key: string, value: string): Promise<number>;
      sMembers(key: string): Promise<string[]>;
    };
  }
}

export default fp(async (fastify: FastifyInstance) => {
  if (config.redis.enabled) {
    // ─── Real Redis Client ──────────────────────────────────────────────
    const Redis = (await import('ioredis')).default;

    logger.info(`Connecting to Redis at: ${config.redis.url}`);
    const redis = new Redis(config.redis.url);

    redis.on('connect', () => {
      logger.info('Redis client connected successfully');
    });

    redis.on('error', (err) => {
      logger.error(`Redis client error: ${err.message}`);
    });

    // Wait for initial connection
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Redis connection timeout after 5 seconds'));
      }, 5000);

      redis.once('ready', () => {
        clearTimeout(timeout);
        resolve();
      });

      redis.once('error', (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });

    // Gracefully close on shutdown
    fastify.addHook('onClose', async () => {
      logger.info('Closing Redis connection');
      await redis.quit();
    });

    const client = {
      sAdd: async (key: string, value: string): Promise<number> => {
        return redis.sadd(key, value);
      },
      sRem: async (key: string, value: string): Promise<number> => {
        return redis.srem(key, value);
      },
      sMembers: async (key: string): Promise<string[]> => {
        return redis.smembers(key);
      },
    };

    fastify.decorate('redis', client);
  } else {
    // ─── In-Memory Mock Client ──────────────────────────────────────────
    logger.info('Initializing In-Memory Redis Mock Client (REDIS_ENABLED=false)');

    const sets = new Map<string, Set<string>>();

    const client = {
      sAdd: async (key: string, value: string): Promise<number> => {
        if (!sets.has(key)) {
          sets.set(key, new Set<string>());
        }
        const set = sets.get(key)!;
        const sizeBefore = set.size;
        set.add(value);
        return set.size - sizeBefore;
      },
      sRem: async (key: string, value: string): Promise<number> => {
        const set = sets.get(key);
        if (!set) return 0;
        const success = set.delete(value);
        return success ? 1 : 0;
      },
      sMembers: async (key: string): Promise<string[]> => {
        const set = sets.get(key);
        return set ? Array.from(set) : [];
      },
    };

    fastify.decorate('redis', client);
  }
});
