import fp from 'fastify-plugin';
import { FastifyInstance } from 'fastify';
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
  logger.info('Initializing In-Memory Redis Mock Client');

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
    }
  };

  fastify.decorate('redis', client);
});
