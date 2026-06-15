import { Server } from 'socket.io';
import { FastifyInstance } from 'fastify';
import { socketAuthMiddleware, AuthenticatedSocket } from './middleware/auth.middleware';
import { registerChatHandlers } from './handlers/chat.handler';
import { registerPresenceHandlers } from './handlers/presence.handler';
import { registerSyncHandlers } from './handlers/sync.handler';
import { registerRelayHandlers, flushQueueForDevice } from './handlers/relay.handler';
import { logger } from '../utils/logger';

export function setupSocketServer(fastify: FastifyInstance) {
  const io = fastify.io;

  if (!io) {
    logger.error('Socket.IO is not initialized on Fastify instance');
    return;
  }

  // 1. Authenticate handshakes before allowing connections
  io.use(socketAuthMiddleware(fastify));

  // 2. Connection Handler
  io.on('connection', async (socket: AuthenticatedSocket) => {
    const { userId, deviceId } = socket.data.user;
    logger.info(`User ${userId} (Device ${deviceId}) connected via Socket.IO`);

    // Join room for this specific user so they receive messages targeting their identity
    await socket.join(`user:${userId}`);
    // Join room for this specific device (supports multi-device messaging targeting)
    await socket.join(`device:${deviceId}`);

    // Register handlers
    registerChatHandlers(io, socket, fastify);
    await registerPresenceHandlers(io, socket, fastify);
    registerSyncHandlers(io, socket, fastify);
    await registerRelayHandlers(io, socket, fastify);
    await flushQueueForDevice(io, fastify, deviceId, socket.id);
  });
}
