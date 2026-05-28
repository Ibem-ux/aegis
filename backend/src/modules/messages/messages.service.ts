import { Pool } from 'pg';
import { Message, MessageType } from '../../types';
import { EncryptionService } from '../../services/encryption.service';
import { ForbiddenError, NotFoundError } from '../../utils/errors';

export class MessagesService {
  /**
   * Fetches messages in a chat with infinite scroll pagination.
   * Encrypted database contents are decrypted before returning.
   */
  public static async getChatMessages(
    db: Pool,
    chatId: string,
    userId: string,
    options: { limit?: number; before?: string }
  ): Promise<any[]> {
    // 1. Verify user is participant in the chat
    const partRes = await db.query(
      'SELECT chat_id FROM chat_participants WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );
    if (partRes.rows.length === 0) {
      throw new ForbiddenError('Access to chat room is forbidden');
    }

    const limit = options.limit || 50;
    const before = options.before ? new Date(options.before) : new Date();

    const query = `
      SELECT m.*, u.username, u.display_name, u.avatar_url
      FROM messages m
      JOIN users u ON m.sender_id = u.id
      WHERE m.chat_id = $1 AND m.created_at < $2 AND m.deleted_at IS NULL
      ORDER BY m.created_at DESC
      LIMIT $3
    `;

    const res = await db.query(query, [chatId, before, limit]);

    // Decrypt messages
    return res.rows.map((row) => {
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
        created_at: row.created_at,
        edited_at: row.edited_at,
      };
    });
  }

  /**
   * Sends a message in a chat room. Encrypts the plaintext content before storing it in DB.
   */
  public static async sendMessage(
    db: Pool,
    senderId: string,
    payload: {
      id?: string;
      chat_id: string;
      content: string;
      message_type?: MessageType;
      reply_to_id?: string;
      media_id?: string;
    }
  ): Promise<any> {
    // 1. Verify sender is in chat
    const partRes = await db.query(
      'SELECT user_id FROM chat_participants WHERE chat_id = $1',
      [payload.chat_id]
    );
    const participants = partRes.rows.map(r => r.user_id);
    if (!participants.includes(senderId)) {
      throw new ForbiddenError('Access to chat room is forbidden');
    }

    // 2. Encrypt message content
    const { ciphertext, iv, tag } = EncryptionService.encrypt(payload.content);
    const type = payload.message_type || 'TEXT';

    const client = await db.connect();
    try {
      await client.query('BEGIN');

      // 3. Insert message
      let queryStr: string;
      let queryParams: any[];

      if (payload.id) {
        queryStr = `INSERT INTO messages (id, chat_id, sender_id, encrypted_content, content_iv, content_tag, message_type, reply_to_id, media_id)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *`;
        queryParams = [payload.id, payload.chat_id, senderId, ciphertext, iv, tag, type, payload.reply_to_id || null, payload.media_id || null];
      } else {
        queryStr = `INSERT INTO messages (chat_id, sender_id, encrypted_content, content_iv, content_tag, message_type, reply_to_id, media_id)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`;
        queryParams = [payload.chat_id, senderId, ciphertext, iv, tag, type, payload.reply_to_id || null, payload.media_id || null];
      }

      const messageInsert = await client.query<Message>(queryStr, queryParams);
      const message = messageInsert.rows[0];

      // 4. Create message statuses for other participants
      const recipients = participants.filter(id => id !== senderId);
      for (const recId of recipients) {
        await client.query(
          'INSERT INTO message_statuses (message_id, user_id, status) VALUES ($1, $2, $3)',
          [message.id, recId, 'SENT']
        );
      }

      // 5. Update last message in chat preview
      const previewText = type === 'TEXT' ? payload.content : `[${type}]`;
      const { ciphertext: prevText, iv: prevIv, tag: prevTag } = EncryptionService.encrypt(previewText);

      await client.query(
        `UPDATE chats 
         SET last_message_at = CURRENT_TIMESTAMP, 
             updated_at = CURRENT_TIMESTAMP,
             last_message_preview = $1,
             last_message_iv = $2,
             last_message_tag = $3
         WHERE id = $4`,
        [prevText, prevIv, prevTag, payload.chat_id]
      );

      await client.query('COMMIT');

      // Fetch sender info for socket update
      const senderRes = await client.query('SELECT username, display_name, avatar_url FROM users WHERE id = $1', [senderId]);
      const sender = senderRes.rows[0];

      return {
        id: message.id,
        chat_id: message.chat_id,
        sender: {
          id: senderId,
          ...sender
        },
        content: payload.content,
        message_type: message.message_type,
        reply_to_id: message.reply_to_id,
        media_id: message.media_id,
        created_at: message.created_at,
        recipients
      };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Retrieve list of recipient user IDs in a chat room.
   */
  public static async getChatRecipients(db: Pool, chatId: string, senderId: string): Promise<string[]> {
    const res = await db.query(
      'SELECT user_id FROM chat_participants WHERE chat_id = $1 AND user_id != $2',
      [chatId, senderId]
    );
    return res.rows.map(row => row.user_id);
  }

  /**
   * Updates message status for a user.
   */
  public static async updateMessageStatus(
    db: Pool,
    messageId: string,
    userId: string,
    status: 'DELIVERED' | 'READ'
  ): Promise<void> {
    await db.query(
      `INSERT INTO message_statuses (message_id, user_id, status, status_changed_at)
       VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
       ON CONFLICT (message_id, user_id) 
       DO UPDATE SET status = EXCLUDED.status, status_changed_at = CURRENT_TIMESTAMP
       WHERE message_statuses.status != EXCLUDED.status`,
      [messageId, userId, status]
    );
  }
}
