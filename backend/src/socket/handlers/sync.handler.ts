import { Server } from 'socket.io';
import { AuthenticatedSocket } from '../middleware/auth.middleware';
import { FastifyInstance } from 'fastify';
import { EncryptionService } from '../../services/encryption.service';
import { logger } from '../../utils/logger';

export const registerSyncHandlers = (
  io: Server,
  socket: AuthenticatedSocket,
  fastify: FastifyInstance
) => {
  const { userId } = socket.data.user;

  /**
   * Event: sync:request
   * Returns all messages that the user missed while offline since the specified timestamp.
   */
  socket.on('sync:request', async (payload: { last_sync_timestamp: string }, callback) => {
    try {
      const lastSync = new Date(payload.last_sync_timestamp);
      
      // Query messages from chats the user is participant in, created after lastSync
      const query = `
        SELECT m.*, u.username, u.display_name, u.avatar_url
        FROM messages m
        JOIN chat_participants cp ON m.chat_id = cp.chat_id
        JOIN users u ON m.sender_id = u.id
        WHERE cp.user_id = $1 AND m.created_at > $2 AND m.deleted_at IS NULL
        ORDER BY m.created_at ASC
      `;

      const res = await fastify.db.query(query, [userId, lastSync]);

      // Decrypt each message content
      const missedMessages = res.rows.map((row) => {
        let content = '';
        try {
          content = EncryptionService.decrypt(
            row.encrypted_content,
            row.content_iv,
            row.content_tag
          );
        } catch (err) {
          content = '[Decryption Failed]';
        }

        return {
          id: row.id,
          chat_id: row.chat_id,
          sender: {
            id: row.sender_id,
            username: row.username,
            display_name: row.display_name,
            avatar_url: row.avatar_url,
          },
          content,
          message_type: row.message_type,
          reply_to_id: row.reply_to_id,
          media_id: row.media_id,
          created_at: row.created_at
        };
      });

      if (callback) {
        callback({
          success: true,
          messages: missedMessages
        });
      }
    } catch (error: any) {
      logger.error('Error handling sync:request', error);
      if (callback) {
        callback({ success: false, error: error.message || 'Internal server error' });
      }
    }
  });
};
