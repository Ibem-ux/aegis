import fp from 'fastify-plugin';
import { FastifyInstance } from 'fastify';
import rateLimit from '@fastify/rate-limit';

export default fp(async (fastify: FastifyInstance) => {
  // Wait until Redis is initialized to use it for rate-limiting
  await fastify.register(rateLimit, {
    max: 100, // Maximum number of requests
    timeWindow: '1 minute', // Time window
    redis: fastify.redis, // Reuse redis client
    keyGenerator: (request) => {
      // Rate limit by IP address, or user ID if authenticated
      const user = request.user as { id?: string } | undefined;
      return user?.id || request.ip;
    },
    errorResponseBuilder: (request, context) => ({
      statusCode: 429,
      error: 'Too Many Requests',
      message: `Rate limit exceeded. Please try again in ${context.after}.`
    })
  });
});
