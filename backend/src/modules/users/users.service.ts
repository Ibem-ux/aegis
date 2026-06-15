import { Pool } from 'pg';
import { User, Role } from '../../types';
import { NotFoundError, BadRequestError, ForbiddenError } from '../../utils/errors';
import { SecurityUtils } from '../../utils/security';
import { hasCapability } from '../../utils/capabilities';

const ROLE_RANK: Record<Role, number> = {
  user: 1,
  admin: 2,
  super_user: 3,
  owner: 4,
};

const getRoleRank = (role: string): number => ROLE_RANK[role as Role] ?? 0;

export class UsersService {
  /**
   * Fetches user profile by ID.
   */
  public static async getProfile(
    db: Pool,
    userId: string,
    requesterId: string
  ): Promise<Partial<User>> {
    const targetRes = await db.query<User>(
      `SELECT id, username, display_name, full_name, avatar_url, email, phone, 
              role, status, password_updated_at, totp_enabled,
              last_seen, created_at, updated_at 
       FROM users WHERE id = $1`,
      [userId]
    );
    const target = targetRes.rows[0];
    if (!target) {
      throw new NotFoundError('User not found');
    }

    const requesterRes = await db.query<User>(
      `SELECT role FROM users WHERE id = $1`,
      [requesterId]
    );
    const requester = requesterRes.rows[0];
    if (!requester) {
      throw new NotFoundError('Requester not found');
    }

    const isSelf = userId === requesterId;
    const canViewExtended = hasCapability(requester.role, 'VIEW_EXTENDED_PROFILE');

    // Safe base user structure (publicly visible details)
    const profile: Partial<User> = {
      id: target.id,
      username: target.username,
      display_name: target.display_name,
      avatar_url: target.avatar_url,
      last_seen: target.last_seen,
      status: target.status,
      role: target.role,
      created_at: target.created_at,
    };

    // If viewing self or requester has VIEW_EXTENDED_PROFILE, expose extended profile fields
    if (isSelf || canViewExtended) {
      profile.full_name = target.full_name;
      profile.email = target.email;
      profile.phone = target.phone;
      profile.updated_at = target.updated_at;
      profile.password_updated_at = target.password_updated_at;
      profile.totp_enabled = target.totp_enabled;
    }

    return profile;
  }

  /**
   * Updates profile data. Users can only update their own details, unless they are Admin.
   */
  public static async updateProfile(
    db: Pool,
    userId: string,
    requesterId: string,
    payload: {
      display_name?: string;
      full_name?: string;
      avatar_url?: string;
      email?: string;
      phone?: string;
      role?: Role;
      status?: 'ACTIVE' | 'SUSPENDED' | 'PENDING';
    }
  ): Promise<Partial<User>> {
    const targetRes = await db.query<User>('SELECT role FROM users WHERE id = $1', [userId]);
    const target = targetRes.rows[0];
    if (!target) throw new NotFoundError('User not found');

    const requesterRes = await db.query<User>('SELECT role FROM users WHERE id = $1', [requesterId]);
    const requester = requesterRes.rows[0];
    if (!requester) throw new NotFoundError('Requester not found');

    const isSelf = userId === requesterId;
    const canEditAny = hasCapability(requester.role, 'EDIT_ANY_PROFILE');

    if (!isSelf && !canEditAny) {
      throw new ForbiddenError('You can only update your own profile');
    }

    if (!isSelf && canEditAny) {
      const targetRank = getRoleRank(target.role);
      const actorRank = getRoleRank(requester.role);
      if (targetRank > actorRank) {
        throw new ForbiddenError('You cannot edit a user with higher rank');
      }
    }

    const updates: string[] = [];
    const values: any[] = [];
    let idx = 1;

    const addUpdate = (field: string, val: any) => {
      updates.push(`${field} = $${idx++}`);
      values.push(val);
    };

    // Users (or those with EDIT_ANY_PROFILE) can update display name, full name, email, phone, and avatar
    if (payload.display_name !== undefined) addUpdate('display_name', payload.display_name);
    if (payload.full_name !== undefined) addUpdate('full_name', payload.full_name);
    if (payload.avatar_url !== undefined) addUpdate('avatar_url', payload.avatar_url);
    if (payload.email !== undefined) addUpdate('email', payload.email);
    if (payload.phone !== undefined) addUpdate('phone', payload.phone);

    // Only users with MANAGE_ROLES can update role, with rank-based escalation guard
    if (payload.role !== undefined && hasCapability(requester.role, 'MANAGE_ROLES')) {
      const targetRank = getRoleRank(target.role);
      const newRoleRank = getRoleRank(payload.role);
      const actorRank = getRoleRank(requester.role);

      if (isSelf) {
        throw new ForbiddenError('You cannot change your own role');
      }
      if (payload.role === 'owner') {
        throw new ForbiddenError('Assigning the owner role via API is not allowed');
      }
      if (payload.role === 'super_user' && !hasCapability(requester.role, 'GRANT_SUPER_USER')) {
        throw new ForbiddenError('Only the owner can assign the super_user role');
      }
      if (targetRank >= actorRank || newRoleRank >= actorRank) {
        throw new ForbiddenError('You cannot assign a role equal to or higher than your own');
      }

      addUpdate('role', payload.role);
    }

    // Only users with MANAGE_USER_STATUS can update status, with rank-based guard
    if (payload.status !== undefined && hasCapability(requester.role, 'MANAGE_USER_STATUS')) {
      const targetRank = getRoleRank(target.role);
      const actorRank = getRoleRank(requester.role);

      if (targetRank >= actorRank) {
        throw new ForbiddenError('You cannot modify the status of a user with equal or higher rank');
      }

      addUpdate('status', payload.status);
    }

    if (updates.length === 0) {
      return this.getProfile(db, userId, requesterId);
    }

    values.push(userId);
    const query = `
      UPDATE users 
      SET ${updates.join(', ')}, updated_at = CURRENT_TIMESTAMP 
      WHERE id = $${idx}
    `;

    await db.query(query, values);
    return this.getProfile(db, userId, requesterId);
  }

  /**
   * Search users by username or display name.
   */
  public static async searchUsers(db: Pool, query: string, currentUserId: string): Promise<Partial<User>[]> {
    const res = await db.query<User>(
      `SELECT id, username, display_name, avatar_url, status, last_seen 
       FROM users 
       WHERE id != $1 AND (username ILIKE $2 OR display_name ILIKE $2)
       LIMIT 20`,
      [currentUserId, `%${query}%`]
    );
    return res.rows;
  }

  /**
   * Checks if password matches current or recent passwords in history.
   */
  private static async checkPasswordHistory(db: Pool, userId: string, newPasswordPlaintext: string, currentPasswordHash: string): Promise<void> {
    const bcrypt = await import('bcryptjs');
    
    // 1. Check against current password
    if (bcrypt.compareSync(newPasswordPlaintext, currentPasswordHash)) {
      throw new BadRequestError('New password cannot be the same as your current password');
    }

    // 2. Check against last 3 passwords in history
    const historyRes = await db.query(
      'SELECT password_hash FROM password_history WHERE user_id = $1 ORDER BY created_at DESC LIMIT 3',
      [userId]
    );

    for (const row of historyRes.rows) {
      if (bcrypt.compareSync(newPasswordPlaintext, row.password_hash)) {
        throw new BadRequestError('Password has been used recently. Please choose a different password.');
      }
    }
  }

  /**
   * Safely changes a user's password and invalidates other sessions.
   */
  public static async changePassword(
    db: Pool,
    userId: string,
    currentPasswordPlaintext: string,
    newPasswordPlaintext: string,
    currentSessionId: string
  ): Promise<void> {
    const bcrypt = await import('bcryptjs');

    // 1. Fetch user current password hash
    const userRes = await db.query(
      'SELECT password_hash FROM users WHERE id = $1',
      [userId]
    );
    const user = userRes.rows[0];
    if (!user) {
      throw new NotFoundError('User not found');
    }

    // 2. Verify current password
    const isCurrentValid = bcrypt.compareSync(currentPasswordPlaintext, user.password_hash);
    if (!isCurrentValid) {
      throw new BadRequestError('Invalid current password');
    }

    // 3. Verify new password strength
    if (!SecurityUtils.validatePasswordStrength(newPasswordPlaintext)) {
      throw new BadRequestError('New password does not meet complexity requirements (min 12 chars, upper, lower, digit, special)');
    }

    // 4. Verify password history
    await this.checkPasswordHistory(db, userId, newPasswordPlaintext, user.password_hash);

    // 5. Update password and invalidate other sessions
    const newHash = bcrypt.hashSync(newPasswordPlaintext, 12);
    
    const client = await db.connect();
    try {
      await client.query('BEGIN');

      // Update password
      await client.query(
        'UPDATE users SET password_hash = $1, password_updated_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
        [newHash, userId]
      );

      // Save to password history
      await client.query(
        'INSERT INTO password_history (user_id, password_hash) VALUES ($1, $2)',
        [userId, newHash]
      );

      // Invalidate all other sessions for this user
      await client.query(
        'UPDATE sessions SET revoked_at = CURRENT_TIMESTAMP WHERE user_id = $1 AND id != $2 AND revoked_at IS NULL',
        [userId, currentSessionId]
      );

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Retrieves all active sessions for a user.
   */
  public static async getActiveSessions(db: Pool, userId: string): Promise<any[]> {
    const query = `
      SELECT 
        s.id as session_id,
        s.ip_address,
        s.user_agent,
        s.created_at,
        s.expires_at,
        d.id as device_id,
        d.device_name,
        d.platform,
        d.last_active
      FROM sessions s
      JOIN devices d ON s.device_id = d.id
      WHERE s.user_id = $1 AND s.revoked_at IS NULL AND s.expires_at > CURRENT_TIMESTAMP
      ORDER BY s.created_at DESC
    `;
    const res = await db.query(query, [userId]);
    return res.rows;
  }

  /**
   * Revokes a specific active session.
   */
  public static async revokeSession(
    db: Pool,
    userId: string,
    sessionId: string,
    currentSessionId: string
  ): Promise<void> {
    if (sessionId === currentSessionId) {
      throw new BadRequestError('Cannot revoke your active session from this endpoint. Use logout instead.');
    }

    const res = await db.query(
      'UPDATE sessions SET revoked_at = CURRENT_TIMESTAMP WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL',
      [sessionId, userId]
    );

    if (res.rowCount === 0) {
      throw new NotFoundError('Session not found or already revoked');
    }
  }

  /**
   * Regenerates a new Master Recovery Key for the user.
   */
  public static async generateMasterRecoveryKey(db: Pool, userId: string): Promise<string> {
    const crypto = await import('crypto');
    const rawKey = 'AEGIS-' + crypto.randomBytes(16).toString('hex').toUpperCase().match(/.{1,4}/g)?.join('-');
    const hash = crypto.createHash('sha256').update(rawKey).digest('hex');

    await db.query(
      'UPDATE users SET recovery_key_hash = $1 WHERE id = $2',
      [hash, userId]
    );

    return rawKey;
  }

  /**
   * Verifies the Master Recovery Key and returns user if valid.
   */
  public static async verifyMasterRecoveryKey(
    db: Pool,
    username: string,
    recoveryKey: string
  ): Promise<Partial<User>> {
    const crypto = await import('crypto');
    const hash = crypto.createHash('sha256').update(recoveryKey.trim()).digest('hex');

    const res = await db.query<User>(
      'SELECT id, username, display_name, role, status, password_hash, recovery_key_hash FROM users WHERE username = $1',
      [username.toLowerCase().trim()]
    );
    const user = res.rows[0];

    if (!user) {
      throw new NotFoundError('User not found');
    }

    if (user.status !== 'ACTIVE') {
      throw new ForbiddenError('User account is suspended or inactive');
    }

    if (!user.recovery_key_hash || user.recovery_key_hash !== hash) {
      throw new BadRequestError('Invalid recovery key');
    }

    return user;
  }

  /**
   * Recovers account via Master Recovery Key and updates to new password.
   */
  public static async recoverViaMasterKey(
    db: Pool,
    username: string,
    recoveryKey: string,
    newPasswordPlaintext: string
  ): Promise<void> {
    // 1. Verify master recovery key
    const user = await this.verifyMasterRecoveryKey(db, username, recoveryKey);
    if (!user || !user.id) {
      throw new BadRequestError('Invalid recovery key');
    }

    // 2. Fetch user's current password hash for validation
    const userRes = await db.query('SELECT password_hash FROM users WHERE id = $1', [user.id]);
    const fullUser = userRes.rows[0];

    // 3. Verify new password strength
    if (!SecurityUtils.validatePasswordStrength(newPasswordPlaintext)) {
      throw new BadRequestError('New password does not meet complexity requirements (min 12 chars, upper, lower, digit, special)');
    }

    // 4. Verify password history
    await this.checkPasswordHistory(db, user.id, newPasswordPlaintext, fullUser.password_hash);

    const bcrypt = await import('bcryptjs');
    const newHash = bcrypt.hashSync(newPasswordPlaintext, 12);

    const client = await db.connect();
    try {
      await client.query('BEGIN');

      // Update password
      await client.query(
        'UPDATE users SET password_hash = $1, password_updated_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
        [newHash, user.id]
      );

      // Record in history
      await client.query(
        'INSERT INTO password_history (user_id, password_hash) VALUES ($1, $2)',
        [user.id, newHash]
      );

      // Revoke all existing sessions (complete logout on reset)
      await client.query(
        'UPDATE sessions SET revoked_at = CURRENT_TIMESTAMP WHERE user_id = $1 AND revoked_at IS NULL',
        [user.id]
      );

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }
}
