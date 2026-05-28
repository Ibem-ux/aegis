import { Pool } from 'pg';
import { Invite } from '../../types';
import { EncryptionService } from '../../services/encryption.service';
import { NotFoundError } from '../../utils/errors';

export class InvitesService {
  /**
   * Creates a new invite code.
   */
  public static async createInvite(
    db: Pool,
    creatorId: string,
    payload: { max_uses?: number; expires_in_hours?: number }
  ): Promise<Invite> {
    // Generate secure random alphanumeric invite code (12 characters is secure and human friendly)
    const code = EncryptionService.generateSecureToken(6).toUpperCase();
    const maxUses = payload.max_uses || 1;
    
    let expiresAt: Date | null = null;
    if (payload.expires_in_hours) {
      expiresAt = new Date();
      expiresAt.setHours(expiresAt.getHours() + payload.expires_in_hours);
    }

    const res = await db.query<Invite>(
      `INSERT INTO invites (code, created_by, max_uses, expires_at)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [code, creatorId, maxUses, expiresAt]
    );

    return res.rows[0];
  }

  /**
   * Retrieves all active, unclaimed invite codes created by the user.
   */
  public static async getMyInvites(db: Pool, userId: string): Promise<Invite[]> {
    const res = await db.query<Invite>(
      `SELECT * FROM invites 
       WHERE created_by = $1 AND claimed_by IS NULL AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
       ORDER BY created_at DESC`,
      [userId]
    );
    return res.rows;
  }

  /**
   * Revoke an invite code.
   */
  public static async revokeInvite(db: Pool, inviteId: string, userId: string): Promise<void> {
    const res = await db.query(
      `UPDATE invites SET expires_at = CURRENT_TIMESTAMP 
       WHERE id = $1 AND created_by = $2 AND claimed_by IS NULL AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)`,
      [inviteId, userId]
    );

    if (res.rowCount === 0) {
      throw new NotFoundError('Invite not found or already claimed/expired');
    }
  }
}
