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
   * Event: message:send
   * Persists a new message, relays to recipients, and tracks delivery status.
   * Accepts an optional client-generated `id` for offline-first reconciliation.
   */
  socket.on('message:send', async (payload: {
    id?: string;
    chat_id: string;
    content: string;
    message_type?: 'TEXT' | 'IMAGE' | 'VIDEO' | 'AUDIO' | 'FILE';
    reply_to_id?: string;
    media_id?: string;
  }, callback) => {
    try {
      const message = await MessagesService.sendMessage(fastify.db, userId, payload);

      const messagePayload = {
        id: message.id,
        chat_id: message.chat_id,
        sender: message.sender,
        content: message.content,
        message_type: message.message_type,
        reply_to_id: message.reply_to_id,
        media_id: message.media_id,
        created_at: message.created_at
      };

      // Relay to each recipient and check if they are online for delivery tracking
      for (const recId of message.recipients) {
        io.to(`user:${recId}`).emit('message:receive', messagePayload);

        // Check if recipient has active sockets in their room
        const recipientRoom = io.sockets.adapter.rooms.get(`user:${recId}`);
        if (recipientRoom && recipientRoom.size > 0) {
          // Recipient is online — mark as DELIVERED
          try {
            await MessagesService.updateMessageStatus(fastify.db, message.id, recId, 'DELIVERED');
            // Notify sender about delivery
            socket.emit('message:status', {
              message_id: message.id,
              chat_id: message.chat_id,
              status: 'DELIVERED',
              user_id: recId
            });
          } catch (statusErr) {
            logger.error('Error updating delivery status', statusErr);
          }
        }
      }

      // Return success to the sender with the created message ID/metadata
      if (callback) {
        callback({
          success: true,
          message: messagePayload
        });
      }
    } catch (error: any) {
      logger.error('Error sending socket message', error);
      if (callback) {
        callback({ success: false, error: error.message || 'Internal server error' });
      }
    }
  });

  /**
   * Event: message:delivered
   * Batch-marks messages as DELIVERED when a recipient comes online.
   * The client sends a list of message IDs it has received.
   */
  socket.on('message:delivered', async (payload: {
    message_ids: Array<{ message_id: string; chat_id: string; sender_id: string }>;
  }) => {
    try {
      for (const item of payload.message_ids) {
        await MessagesService.updateMessageStatus(fastify.db, item.message_id, userId, 'DELIVERED');
        // Notify original sender
        io.to(`user:${item.sender_id}`).emit('message:status', {
          message_id: item.message_id,
          chat_id: item.chat_id,
          status: 'DELIVERED',
          user_id: userId
        });
      }
    } catch (error) {
      logger.error('Error handling batch message:delivered', error);
    }
  });

  /**
   * Event: message:read
   * Marks a message as read and relays read receipt to the sender.
   */
  socket.on('message:read', async (payload: { message_id: string; chat_id: string; sender_id: string }) => {
    try {
      await MessagesService.updateMessageStatus(fastify.db, payload.message_id, userId, 'READ');

      // Notify sender that message has been read (via both legacy and new event)
      io.to(`user:${payload.sender_id}`).emit('message:read_ack', {
        message_id: payload.message_id,
        chat_id: payload.chat_id,
        user_id: userId
      });
      io.to(`user:${payload.sender_id}`).emit('message:status', {
        message_id: payload.message_id,
        chat_id: payload.chat_id,
        status: 'READ',
        user_id: userId
      });
    } catch (error) {
      logger.error('Error handling message:read status', error);
    }
  });

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

