import { Pool } from 'pg';
import { logger } from '../../utils/logger';

export class MessagesService {
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
   * Updates message status for a recipient device.
   */
  public static async updateMessageStatus(
    db: Pool,
    messageId: string,
    recipientDeviceId: string,
    status: 'DELIVERED'
  ): Promise<void> {
    await db.query(
      `INSERT INTO message_statuses (message_id, recipient_device_id, status, status_changed_at)
       VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
       ON CONFLICT (message_id, recipient_device_id)
       DO UPDATE SET status = EXCLUDED.status, status_changed_at = CURRENT_TIMESTAMP
       WHERE message_statuses.status != EXCLUDED.status`,
      [messageId, recipientDeviceId, status]
    );
  }
}
