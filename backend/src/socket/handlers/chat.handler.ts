import { Server } from 'socket.io';
import { AuthenticatedSocket } from '../middleware/auth.middleware';
import { FastifyInstance } from 'fastify';
import { MessagesService } from '../../modules/messages/messages.service';
import { logger } from '../../utils/logger';

export const registerChatHandlers = (
  io: Server,
  socket: AuthenticatedSocket,
  fastify: FastifyInstance
) => {
  const { userId } = socket.data.user;

  /**
   * Event: typing:start
   * Broadcast typing indicators to recipients.
   */
  socket.on('typing:start', async (payload: { chat_id: string }) => {
    try {
      const recipients = await MessagesService.getChatRecipients(fastify.db, payload.chat_id, userId);
      for (const recId of recipients) {
        io.to(`user:${recId}`).emit('typing:indicator', {
          chat_id: payload.chat_id,
          user_id: userId,
          is_typing: true
        });
      }
    } catch (error) {
      logger.error('Error handling typing:start indicator', error);
    }
  });

  /**
   * Event: typing:stop
   * Broadcast typing indicators to recipients.
   */
  socket.on('typing:stop', async (payload: { chat_id: string }) => {
    try {
      const recipients = await MessagesService.getChatRecipients(fastify.db, payload.chat_id, userId);
      for (const recId of recipients) {
        io.to(`user:${recId}`).emit('typing:indicator', {
          chat_id: payload.chat_id,
          user_id: userId,
          is_typing: false
        });
      }
    } catch (error) {
      logger.error('Error handling typing:stop indicator', error);
    }
  });
};
