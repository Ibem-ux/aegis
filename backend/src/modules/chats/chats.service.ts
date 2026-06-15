import { Pool } from 'pg';
import { Chat } from '../../types';
import { BadRequestError, NotFoundError, ForbiddenError } from '../../utils/errors';
import { EncryptionService } from '../../services/encryption.service';
import { logger } from '../../utils/logger';
import crypto from 'crypto';

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
    
    return res.rows.map((row) => ({
      chat_id: row.chat_id,
      created_at: row.created_at,
      updated_at: row.updated_at,
      last_message_at: row.last_message_at,
      last_message_preview: null,
      archived: row.archived === 1 || row.archived === true,
      recipient: {
        id: row.recipient_id,
        username: row.recipient_username,
        display_name: row.recipient_display_name,
        avatar_url: row.recipient_avatar_url,
        last_seen: row.recipient_last_seen,
      }
    }));
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

    // Log count of excluded devices for diagnostics
    const allDevicesRes = await db.query(
      `SELECT COUNT(*) as total FROM chat_participants cp
       JOIN devices d ON cp.user_id = d.user_id
       WHERE cp.chat_id = $1`,
      [chatId]
    );
    const totalDevices = Number(allDevicesRes.rows[0]?.total || 0);
    if (totalDevices > keysRes.rows.length) {
      logger.warn(`Chat ${chatId}: ${totalDevices - keysRes.rows.length} device(s) excluded from E2EE (untrusted or missing public key)`);
    }

    return keysRes.rows;
  }

  /**
   * Generates a secure invite link for the user.
   */
  public static async createInviteLink(
    db: Pool,
    creatorId: string,
    options: { max_uses?: number | null; expires_at?: string; label?: string }
  ): Promise<{ token: string; id: string }> {
    const token = crypto.randomBytes(32).toString('hex');
    const result = await db.query(
      `INSERT INTO user_invite_links (creator_id, token, label, max_uses, expires_at)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, token`,
      [creatorId, token, options.label || null, options.max_uses ?? null, options.expires_at || null]
    );
    return result.rows[0];
  }

  /**
   * Retrieves active invite links created by the user.
   */
  public static async getUserInviteLinks(db: Pool, userId: string): Promise<any[]> {
    const result = await db.query(
      `SELECT id, token, label, max_uses, use_count, expires_at, is_active, created_at
       FROM user_invite_links
       WHERE creator_id = $1
       ORDER BY created_at DESC`,
      [userId]
    );
    return result.rows.map((row) => ({
      ...row,
      is_active: row.is_active === 1 || row.is_active === true,
    }));
  }

  /**
   * Toggles the active status of an invite link.
   */
  public static async toggleInviteLinkActive(db: Pool, userId: string, inviteId: string, isActive: boolean): Promise<void> {
    const result = await db.query(
      `UPDATE user_invite_links SET is_active = $3, updated_at = CURRENT_TIMESTAMP
       WHERE id = $1 AND creator_id = $2`,
      [inviteId, userId, isActive]
    );
    if (result.rowCount === 0) {
      throw new NotFoundError('Invite link not found');
    }
  }

  /**
   * Permanently deletes an invite link.
   */
  public static async deleteInviteLink(db: Pool, userId: string, inviteId: string): Promise<void> {
    const result = await db.query(
      `DELETE FROM user_invite_links WHERE id = $1 AND creator_id = $2`,
      [inviteId, userId]
    );
    if (result.rowCount === 0) {
      throw new NotFoundError('Invite link not found');
    }
  }

  /**
   * Deletes inactive invite links that haven't been updated in 7 days.
   */
  public static async cleanupStaleInviteLinks(db: Pool): Promise<number> {
    const staleThreshold = new Date();
    staleThreshold.setDate(staleThreshold.getDate() - 7);
    const result = await db.query(
      `DELETE FROM user_invite_links 
       WHERE is_active = FALSE 
       AND updated_at < $1`,
       [staleThreshold]
    );
    return result.rowCount || 0;
  }

  /**
   * Accepts an invite link: blocks self-invites, checks validity, and creates/gets chat.
   */
  public static async acceptInviteLink(
    db: Pool,
    claimerId: string,
    token: string
  ): Promise<{ chat_id: string; isNew: boolean; creator_id: string; creator_keys: any[] }> {
    const client = await db.connect();
    let invite: any;
    try {
      await client.query('BEGIN');
      
      // 1. Validate token
      const inviteRes = await client.query(
        `SELECT id, creator_id, max_uses, use_count, expires_at, is_active
         FROM user_invite_links WHERE token = $1 FOR UPDATE`,
        [token]
      );

      if (inviteRes.rows.length === 0) {
        throw new NotFoundError('Invalid invite link');
      }

      invite = inviteRes.rows[0];

      const isActive = invite.is_active === 1 || invite.is_active === true;
      if (!isActive) {
        throw new BadRequestError('Invite link is no longer active');
      }
      if (invite.expires_at && new Date(invite.expires_at) < new Date()) {
        throw new BadRequestError('Invite link has expired');
      }
      if (invite.max_uses !== null && invite.use_count >= invite.max_uses) {
        throw new BadRequestError('Invite link maximum uses reached');
      }
      if (invite.creator_id === claimerId) {
        throw new BadRequestError('You cannot accept your own invite link');
      }

      // 2. Increment usage
      await client.query(
        `UPDATE user_invite_links 
         SET use_count = use_count + 1,
             is_active = CASE WHEN max_uses IS NOT NULL AND use_count + 1 >= max_uses THEN FALSE ELSE is_active END
         WHERE id = $1`,
        [invite.id]
      );

      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }

    // Proceed to create/get chat using the normal method (outside transaction block)
    const chatResult = await this.createOrGetChat(db, claimerId, invite.creator_id);

    // 4. Fetch the creator's E2EE public keys to return to the claimer
    const keysRes = await db.query(
      `SELECT id AS device_id, public_key
       FROM devices
       WHERE user_id = $1 AND is_trusted = TRUE AND public_key IS NOT NULL`,
      [invite.creator_id]
    );

    return {
      chat_id: chatResult.chat_id,
      isNew: chatResult.isNew,
      creator_id: invite.creator_id,
      creator_keys: keysRes.rows,
    };
  }
}

