import { Pool } from 'pg';
import { Chat } from '../../types';
import { BadRequestError, NotFoundError, ForbiddenError } from '../../utils/errors';
import { EncryptionService } from '../../services/encryption.service';

export class ChatsService {
  /**
   * Retrieves all chat rooms/conversations for a user,
   * including details of the other participant and last message preview.
   */
  public static async getUserChats(db: Pool, userId: string): Promise<any[]> {
    const query = `
      SELECT 
        c.id AS chat_id,
        c.created_at,
        c.updated_at,
        c.last_message_at,
        c.last_message_preview,
        c.last_message_iv,
        c.last_message_tag,
        u.id AS recipient_id,
        u.username AS recipient_username,
        u.display_name AS recipient_display_name,
        u.avatar_url AS recipient_avatar_url,
        u.last_seen AS recipient_last_seen,
        cp.archived
      FROM chat_participants cp
      JOIN chats c ON cp.chat_id = c.id
      JOIN chat_participants cp2 ON c.id = cp2.chat_id AND cp2.user_id != $1
      JOIN users u ON cp2.user_id = u.id
      WHERE cp.user_id = $1
      ORDER BY c.last_message_at DESC
    `;

    const res = await db.query(query, [userId]);
    
    // Decrypt last message preview if present
    return res.rows.map((row) => {
      let lastMessage: string | null = null;
      if (row.last_message_preview && row.last_message_iv && row.last_message_tag) {
        try {
          lastMessage = EncryptionService.decrypt(
            row.last_message_preview,
            row.last_message_iv,
            row.last_message_tag
          );
        } catch (error) {
          lastMessage = '[Encrypted Message]';
        }
      }

      return {
        chat_id: row.chat_id,
        created_at: row.created_at,
        updated_at: row.updated_at,
        last_message_at: row.last_message_at,
        last_message_preview: lastMessage,
        archived: row.archived,
        recipient: {
          id: row.recipient_id,
          username: row.recipient_username,
          display_name: row.recipient_display_name,
          avatar_url: row.recipient_avatar_url,
          last_seen: row.recipient_last_seen,
        }
      };
    });
  }

  /**
   * Creates a new 1:1 chat room or retrieves the existing one.
   */
  public static async createOrGetChat(db: Pool, userId: string, recipientId: string): Promise<any> {
    if (userId === recipientId) {
      throw new BadRequestError('Cannot start a chat with yourself');
    }

    // 1. Verify recipient exists
    const userCheck = await db.query('SELECT id FROM users WHERE id = $1', [recipientId]);
    if (userCheck.rows.length === 0) {
      throw new NotFoundError('Recipient user not found');
    }

    // 2. Check if a 1:1 chat already exists between these two users
    const existingCheck = await db.query(
      `SELECT cp1.chat_id 
       FROM chat_participants cp1
       JOIN chat_participants cp2 ON cp1.chat_id = cp2.chat_id
       WHERE cp1.user_id = $1 AND cp2.user_id = $2`,
      [userId, recipientId]
    );

    if (existingCheck.rows.length > 0) {
      const chatId = existingCheck.rows[0].chat_id;
      return { chat_id: chatId, isNew: false };
    }

    // 3. Create a new chat transactionally
    const client = await db.connect();
    try {
      await client.query('BEGIN');

      const chatInsert = await client.query<Chat>(
        'INSERT INTO chats DEFAULT VALUES RETURNING *'
      );
      const chat = chatInsert.rows[0];

      // Add both participants
      await client.query(
        'INSERT INTO chat_participants (chat_id, user_id) VALUES ($1, $2), ($1, $3)',
        [chat.id, userId, recipientId]
      );

      await client.query('COMMIT');
      return { chat_id: chat.id, isNew: true };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Retrieves trusted device public keys for all participants in a chat room.
   * Verifies the requesting user is a participant.
   */
  public static async getChatParticipantPublicKeys(
    db: Pool,
    chatId: string,
    userId: string
  ): Promise<any[]> {
    // 1. Verify caller is participant
    const partCheck = await db.query(
      'SELECT chat_id FROM chat_participants WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );
    if (partCheck.rows.length === 0) {
      throw new ForbiddenError('Access to chat room is forbidden');
    }

    // 2. Fetch active trusted devices' public keys for all participants
    const keysRes = await db.query(
      `SELECT 
        d.user_id,
        d.id AS device_id,
        d.public_key
       FROM chat_participants cp
       JOIN devices d ON cp.user_id = d.user_id
       WHERE cp.chat_id = $1 
         AND d.is_trusted = TRUE 
         AND d.public_key IS NOT NULL`,
      [chatId]
    );
    return keysRes.rows;
  }
}

