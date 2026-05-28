import fp from 'fastify-plugin';
import { FastifyInstance } from 'fastify';
import { Server } from 'socket.io';
import { logger } from '../utils/logger';

declare module 'fastify' {
  interface FastifyInstance {
    io: Server;
  }
}

export default fp(async (fastify: FastifyInstance) => {
  // Attach Socket.IO to the fastify server on ready hook
  const io = new Server(fastify.server, {
    cors: {
      origin: '*', // In production, restrict to allowed client origins
      methods: ['GET', 'POST']
    },
    pingInterval: 10000,
    pingTimeout: 5000,
  });

  fastify.decorate('io', io);

  fastify.addHook('onClose', async () => {
    logger.info('Closing Socket.IO server');
    await new Promise<void>((resolve) => io.close(() => resolve()));
  });
});
