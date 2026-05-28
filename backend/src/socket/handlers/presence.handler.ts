import { Server } from 'socket.io';
import { AuthenticatedSocket } from '../middleware/auth.middleware';
import { FastifyInstance } from 'fastify';
import { logger } from '../../utils/logger';

export const registerPresenceHandlers = async (
  io: Server,
  socket: AuthenticatedSocket,
  fastify: FastifyInstance
) => {
  const { userId } = socket.data.user;
  const redisKey = 'presence:online_users';

  // 1. Mark user as online in Redis
  try {
    await fastify.redis.sAdd(redisKey, userId);
    
    // Broadcast status to all connected sockets
    io.emit('presence:update', {
      user_id: userId,
      status: 'online'
    });
  } catch (error) {
    logger.error('Failed to set online presence in Redis', error);
  }

  /**
   * Event: disconnect
   * Cleans up online status, sets last_seen in PostgreSQL, and broadcasts offline state.
   */
  socket.on('disconnect', async () => {
    logger.info(`User ${userId} disconnected from Socket.IO`);

    try {
      // Remove from Redis online set
      await fastify.redis.sRem(redisKey, userId);

      // Check if user has other active connections (e.g. from multi-device support)
      // Since a user can have multiple sockets if they have multiple devices or tabs open,
      // we check if they still have sockets connected.
      const userSockets = await io.in(`user:${userId}`).fetchSockets();
      
      if (userSockets.length === 0) {
        const lastSeen = new Date();
        
        // Update database last seen
        await fastify.db.query(
          'UPDATE users SET last_seen = $1 WHERE id = $2',
          [lastSeen, userId]
        );

        // Broadcast offline status
        io.emit('presence:update', {
          user_id: userId,
          status: 'offline',
          last_seen: lastSeen.toISOString()
        });
      }
    } catch (error) {
      logger.error('Failed to handle disconnect presence cleanup', error);
    }
  });

  /**
   * Event: presence:get_online
   * Returns a list of currently online user IDs.
   */
  socket.on('presence:get_online', async (callback) => {
    try {
      const onlineUserIds = await fastify.redis.sMembers(redisKey);
      if (callback) {
        callback({ success: true, online_users: onlineUserIds });
      }
    } catch (error: any) {
      logger.error('Failed to fetch online presence list', error);
      if (callback) {
        callback({ success: false, error: error.message || 'Internal server error' });
      }
    }
  });
};
