import { Pool, PoolClient } from 'pg';
import { Helpers } from '../../utils/helpers';
import { EncryptionService } from '../../services/encryption.service';
import { TokenService } from '../../services/token.service';
import { 
  BadRequestError, 
  ConflictError, 
  NotFoundError, 
  UnauthorizedError, 
  ForbiddenError 
} from '../../utils/errors';
import { User, Device, Session, Invite } from '../../types';
import { FastifyInstance } from 'fastify';
import { logger } from '../../utils/logger';

export class AuthService {
  /**
   * Registers a new user using a valid invite.
   */
  public static async register(
    db: Pool,
    payload: {
      username: string;
      password_hash: string;
      display_name?: string;
      invite_code: string;
      device_name: string;
      device_fingerprint: string;
      platform: 'ANDROID' | 'IOS' | 'DESKTOP' | 'WEB';
      public_key?: string;
    }
  ): Promise<{ user: Partial<User>; device: Device }> {
    const client = await db.connect();
    try {
      await client.query('BEGIN');

      // 1. Verify invite code
      const inviteRes = await client.query<Invite>(
        'SELECT * FROM invites WHERE code = $1 FOR UPDATE',
        [payload.invite_code]
      );
      const invite = inviteRes.rows[0];

      if (!invite) {
        throw new BadRequestError('Invalid invite code');
      }

      if (invite.claimed_by) {
        throw new BadRequestError('Invite code already claimed');
      }

      if (invite.expires_at && new Date(invite.expires_at) < new Date()) {
        throw new BadRequestError('Invite code has expired');
      }

      if (invite.use_count >= invite.max_uses) {
        throw new BadRequestError('Invite code usage limit reached');
      }

      // 2. Check if username exists
      const userCheck = await client.query(
        'SELECT id FROM users WHERE username = $1',
        [payload.username.toLowerCase()]
      );
      if (userCheck.rows.length > 0) {
        throw new ConflictError('Username already taken');
      }

      // 3. Create user
      const userInsert = await client.query<User>(
        `INSERT INTO users (username, display_name, password_hash, status) 
         VALUES ($1, $2, $3, 'ACTIVE') RETURNING *`,
        [payload.username.toLowerCase(), payload.display_name || payload.username, payload.password_hash]
      );
      const user = userInsert.rows[0];

      // 4. Create device
      // Since this is the first device for the user, we mark it as trusted automatically
      const deviceInsert = await client.query<Device>(
        `INSERT INTO devices (user_id, device_name, device_fingerprint, platform, public_key, is_trusted, trusted_at)
         VALUES ($1, $2, $3, $4, $5, TRUE, CURRENT_TIMESTAMP) RETURNING *`,
        [user.id, payload.device_name, payload.device_fingerprint, payload.platform, payload.public_key || null]
      );
      const device = deviceInsert.rows[0];

      // 5. Update invite status
      await client.query(
        `UPDATE invites SET claimed_by = $1, use_count = use_count + 1 WHERE id = $2`,
        [user.id, invite.id]
      );

      await client.query('COMMIT');

      // Strip sensitive password field
      const { password_hash, totp_secret, ...safeUser } = user;
      return { user: safeUser, device };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Login credentials validation, device mapping, and login attempt tracking.
   */
  public static async login(
    db: Pool,
    payload: {
      username: string;
      password_plaintext: string;
      device_name: string;
      device_fingerprint: string;
      platform: 'ANDROID' | 'IOS' | 'DESKTOP' | 'WEB';
      public_key?: string;
      ip: string;
    }
  ): Promise<{ user: User; device: Device; requiresTrust: boolean }> {
    const userRes = await db.query<User>(
      'SELECT * FROM users WHERE username = $1',
      [payload.username.toLowerCase()]
    );
    const user = userRes.rows[0];

    if (!user) {
      // Track failed attempt
      await db.query(
        `INSERT INTO login_attempts (user_identifier, ip_address, success, failure_reason)
         VALUES ($1, $2, $3, 'USER_NOT_FOUND')`,
        [payload.username.toLowerCase(), payload.ip, 0]
      );
      throw new UnauthorizedError('Invalid credentials');
    }

    if (user.status !== 'ACTIVE') {
      throw new ForbiddenError('Account is not active');
    }

    // Verify Password
    logger.info(`Login attempt for user '${payload.username}' — verifying password hash...`);
    const passwordValid = await Helpers.comparePassword(payload.password_plaintext, user.password_hash);
    logger.info(`Password verification result for '${payload.username}': ${passwordValid}`);
    if (!passwordValid) {
      // Track failed attempt
      await db.query(
        `INSERT INTO login_attempts (user_identifier, ip_address, success, failure_reason)
         VALUES ($1, $2, $3, 'INVALID_PASSWORD')`,
        [payload.username.toLowerCase(), payload.ip, 0]
      );
      throw new UnauthorizedError('Invalid credentials');
    }

    // Check device list
    const deviceRes = await db.query<Device>(
      'SELECT * FROM devices WHERE user_id = $1 AND device_fingerprint = $2',
      [user.id, payload.device_fingerprint]
    );
    let device = deviceRes.rows[0];
    let requiresTrust = false;

    if (!device) {
      // Check if this is the very first device for this user
      const deviceCountRes = await db.query('SELECT COUNT(*) as count FROM devices WHERE user_id = $1', [user.id]);
      const isFirstDevice = Number(deviceCountRes.rows[0].count) === 0;
      const isTrusted = isFirstDevice || user.role === 'admin';

      // Create new device
      const newDeviceRes = await db.query<Device>(
        `INSERT INTO devices (user_id, device_name, device_fingerprint, platform, public_key, is_trusted, trusted_at)
         VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP) RETURNING *`,
        [user.id, payload.device_name, payload.device_fingerprint, payload.platform, payload.public_key || null, isTrusted ? 1 : 0]
      );
      device = newDeviceRes.rows[0];
      requiresTrust = !isTrusted;
    } else {
      requiresTrust = !(device.is_trusted === true || (device.is_trusted as any) === 1);
      // Update last active
      await db.query(
        'UPDATE devices SET last_active = CURRENT_TIMESTAMP, device_name = $1, public_key = COALESCE($2, public_key) WHERE id = $3',
        [payload.device_name, payload.public_key || null, device.id]
      );
    }

    // Log successful attempt
    await db.query(
      `INSERT INTO login_attempts (user_identifier, ip_address, success, device_fingerprint)
       VALUES ($1, $2, $3, $4)`,
      [user.username, payload.ip, 1, payload.device_fingerprint]
    );

    return { user, device, requiresTrust };
  }

  /**
   * Starts a new session and returns access and refresh tokens.
   */
  public static async createSession(
    db: Pool,
    fastify: FastifyInstance,
    userId: string,
    deviceId: string,
    ip: string,
    userAgent: string
  ): Promise<{ accessToken: string; refreshToken: string }> {
    const rawRefreshToken = TokenService.generateRefreshToken();
    const refreshTokenHash = EncryptionService.hashToken(rawRefreshToken);
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 30); // 30 days expiry

    // Save session in DB
    const sessionRes = await db.query<Session>(
      `INSERT INTO sessions (user_id, device_id, refresh_token_hash, ip_address, user_agent, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [userId, deviceId, refreshTokenHash, ip, userAgent, expiresAt]
    );
    const session = sessionRes.rows[0];

    const accessToken = TokenService.generateAccessToken(fastify, {
      userId,
      deviceId,
      sessionId: session.id
    });

    return {
      accessToken,
      refreshToken: rawRefreshToken
    };
  }

  /**
   * Refreshes access token by validating refresh token.
   */
  public static async refreshSession(
    db: Pool,
    fastify: FastifyInstance,
    rawRefreshToken: string,
    ip: string,
    userAgent: string
  ): Promise<{ accessToken: string; refreshToken: string }> {
    const refreshTokenHash = EncryptionService.hashToken(rawRefreshToken);

    const sessionRes = await db.query<Session>(
      `SELECT * FROM sessions WHERE refresh_token_hash = $1 AND revoked_at IS NULL AND expires_at > CURRENT_TIMESTAMP`,
      [refreshTokenHash]
    );
    const oldSession = sessionRes.rows[0];

    if (!oldSession) {
      throw new UnauthorizedError('Invalid or expired refresh token');
    }

    // Revoke old session/token
    await db.query(
      'UPDATE sessions SET revoked_at = CURRENT_TIMESTAMP WHERE id = $1',
      [oldSession.id]
    );

    // Create a new session (Refresh Token Rotation)
    return this.createSession(db, fastify, oldSession.user_id, oldSession.device_id, ip, userAgent);
  }

  /**
   * Revoke session (logout)
   */
  public static async revokeSession(db: Pool, sessionId: string): Promise<void> {
    await db.query(
      'UPDATE sessions SET revoked_at = CURRENT_TIMESTAMP WHERE id = $1',
      [sessionId]
    );
  }
}
