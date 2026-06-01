import { FastifyReply, FastifyRequest } from 'fastify';
import { AuthService } from './auth.service';
import { OtpService } from '../../services/otp.service';
import { EmailService } from '../../services/email.service';
import { Helpers } from '../../utils/helpers';
import { RegisterBody, LoginBody, RefreshBody, VerifyOtpBody } from './auth.types';
import { BadRequestError, UnauthorizedError, ForbiddenError, NotFoundError } from '../../utils/errors';
import { logger } from '../../utils/logger';

interface OtpEntry {
  otp: string;
  expiresAt: number;
}
const emailOtpCache = new Map<string, OtpEntry>();

const OTP_EXPIRY_MS = 15 * 60 * 1000; // 15 minutes

export class AuthController {
  /**
   * Register endpoint controller.
   */
  public static async register(request: FastifyRequest<{ Body: RegisterBody }>, reply: FastifyReply) {
    const { username, password, display_name, invite_code, device_name, device_fingerprint, platform, public_key } = request.body;

    if (!password) {
      throw new BadRequestError('Password is required');
    }

    const password_hash = await Helpers.hashPassword(password);
    const { user, device } = await AuthService.register(request.server.db, {
      username,
      password_hash,
      display_name,
      invite_code,
      device_name,
      device_fingerprint,
      platform,
      public_key,
    });

    // Create session for registered user
    const ip = request.ip;
    const userAgent = request.headers['user-agent'] || 'unknown';
    const { accessToken, refreshToken } = await AuthService.createSession(
      request.server.db,
      request.server,
      user.id!,
      device.id,
      ip,
      userAgent
    );

    return reply.status(201).send({
      message: 'Registration successful',
      user,
      device,
      tokens: { accessToken, refreshToken }
    });
  }

  /**
   * Login endpoint controller.
   */
  public static async login(request: FastifyRequest<{ Body: LoginBody }>, reply: FastifyReply) {
    const { username, password, device_name, device_fingerprint, platform, public_key } = request.body;

    if (!password) {
      throw new BadRequestError('Password is required');
    }

    const ip = request.ip;
    const userAgent = request.headers['user-agent'] || 'unknown';

    // 1. Authenticate user credentials and check/register device
    const { user, device, requiresTrust } = await AuthService.login(request.server.db, {
      username,
      password_plaintext: password,
      device_name,
      device_fingerprint,
      platform,
      public_key,
      ip,
    });

    // 2. Check if device needs verification first
    if (requiresTrust) {
      return reply.status(403).send({
        error: 'Device Untrusted',
        message: 'This device is pending approval from a trusted device',
        device: { id: device.id, device_name: device.device_name }
      });
    }

    // 3. Check if 2FA is enabled
    if (user.totp_enabled && user.totp_secret) {
      // Return 2fa required flow details
      // Client needs to call verification endpoint with temp login session token
      const tempToken = request.server.jwt.sign(
        { userId: user.id, deviceId: device.id, isPre2fa: true },
        { expiresIn: '5m' }
      );
      return reply.status(200).send({
        requires2FA: true,
        tempToken,
        message: 'Two-Factor Authentication required'
      });
    }

    // 4. Successful login session creation
    const { accessToken, refreshToken } = await AuthService.createSession(
      request.server.db,
      request.server,
      user.id,
      device.id,
      ip,
      userAgent
    );

    const { password_hash, totp_secret, ...safeUser } = user;

    return reply.status(200).send({
      message: 'Login successful',
      user: safeUser,
      device,
      tokens: { accessToken, refreshToken }
    });
  }

  /**
   * Refresh session token endpoint controller.
   */
  public static async refresh(request: FastifyRequest<{ Body: RefreshBody }>, reply: FastifyReply) {
    const { refresh_token } = request.body;
    const ip = request.ip;
    const userAgent = request.headers['user-agent'] || 'unknown';

    const tokens = await AuthService.refreshSession(
      request.server.db,
      request.server,
      refresh_token,
      ip,
      userAgent
    );

    return reply.status(200).send({
      message: 'Tokens refreshed',
      tokens
    });
  }

  /**
   * Logout endpoint controller.
   */
  public static async logout(request: FastifyRequest, reply: FastifyReply) {
    const session = request.user as { sessionId?: string } | undefined;
    if (session?.sessionId) {
      await AuthService.revokeSession(request.server.db, session.sessionId);
    }
    return reply.status(200).send({ message: 'Logged out successfully' });
  }

  /**
   * 2FA Setup endpoint controller.
   */
  public static async setup2FA(request: FastifyRequest, reply: FastifyReply) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    // Fetch user details from DB
    const userRes = await request.server.db.query(
      'SELECT username, totp_enabled FROM users WHERE id = $1',
      [user.userId]
    );
    const dbUser = userRes.rows[0];

    if (!dbUser) throw new UnauthorizedError('User not found');
    if (dbUser.totp_enabled) {
      throw new BadRequestError('2FA is already enabled');
    }

    // Generate TOTP secret
    const secret = OtpService.generateSecret();
    const keyUri = OtpService.getKeyUri(dbUser.username, secret);
    const qrCode = await OtpService.generateQrCodeDataUrl(keyUri);

    // Save temporary OTP secret
    await request.server.db.query(
      'UPDATE users SET totp_secret = $1 WHERE id = $2',
      [secret, user.userId]
    );

    return reply.status(200).send({
      secret,
      qrCode,
      message: 'Scan the QR code to set up 2FA'
    });
  }

  /**
   * 2FA verification and activation endpoint controller.
   */
  public static async verify2FA(request: FastifyRequest<{ Body: VerifyOtpBody }>, reply: FastifyReply) {
    const tokenUser = request.user as { userId: string; deviceId?: string; isPre2fa?: boolean } | undefined;
    if (!tokenUser) throw new UnauthorizedError();

    const { code } = request.body;

    const userRes = await request.server.db.query(
      'SELECT totp_secret, totp_enabled FROM users WHERE id = $1',
      [tokenUser.userId]
    );
    const user = userRes.rows[0];

    if (!user || !user.totp_secret) {
      throw new BadRequestError('2FA setup has not been initiated');
    }

    const isValid = OtpService.verifyToken(code, user.totp_secret);
    if (!isValid) {
      throw new UnauthorizedError('Invalid verification code');
    }

    // If pre-2fa login flow, complete and issue tokens
    if (tokenUser.isPre2fa && tokenUser.deviceId) {
      const ip = request.ip;
      const userAgent = request.headers['user-agent'] || 'unknown';
      
      const { accessToken, refreshToken } = await AuthService.createSession(
        request.server.db,
        request.server,
        tokenUser.userId,
        tokenUser.deviceId,
        ip,
        userAgent
      );

      return reply.status(200).send({
        message: '2FA verified',
        tokens: { accessToken, refreshToken }
      });
    }

    // Otherwise, this is setup verification, enable TOTP
    await request.server.db.query(
      'UPDATE users SET totp_enabled = TRUE WHERE id = $1',
      [tokenUser.userId]
    );

    return reply.status(200).send({
      message: '2FA successfully enabled'
    });
  }

  /**
   * Generates and sends a 6-digit OTP verification code to the target email.
   */
  public static async sendOtp(request: FastifyRequest<{ Body: { email: string } }>, reply: FastifyReply) {
    const { email } = request.body;
    if (!email || !email.includes('@')) {
      throw new BadRequestError('Invalid email address');
    }

    const normalizedEmail = email.trim().toLowerCase();

    // Generate 6 digit numeric code
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    emailOtpCache.set(normalizedEmail, {
      otp,
      expiresAt: Date.now() + OTP_EXPIRY_MS
    });

    const sent = await EmailService.sendOtp(normalizedEmail, otp);
    if (!sent) {
      // Clean up the cached OTP — no point keeping it if the email never arrived
      emailOtpCache.delete(normalizedEmail);
      logger.error(`OTP email delivery failed for ${normalizedEmail} — cleared OTP cache`);
      return reply.status(500).send({
        error: 'Email Delivery Failed',
        message: 'Failed to send verification email. Please check your email address and try again later.'
      });
    }

    return reply.status(200).send({
      message: 'Verification code sent to your email'
    });
  }

  /**
   * Verifies the email OTP, registers/logs in the user, and trusts the device.
   */
  public static async verifyOtp(
    request: FastifyRequest<{
      Body: {
        email: string;
        code: string;
        device_name: string;
        device_fingerprint: string;
        platform: 'ANDROID' | 'IOS' | 'DESKTOP' | 'WEB';
        public_key?: string;
      }
    }>,
    reply: FastifyReply
  ) {
    const { email, code, device_name, device_fingerprint, platform, public_key } = request.body;

    if (!email || !code) {
      throw new BadRequestError('Email and verification code are required');
    }

    const normalizedEmail = email.trim().toLowerCase();
    const normalizedCode = code.trim();

    const cached = emailOtpCache.get(normalizedEmail);
    if (!cached) {
      throw new UnauthorizedError('No verification code has been requested for this email');
    }

    const now = Date.now();
    if (now > cached.expiresAt) {
      const diffSec = Math.round((now - cached.expiresAt) / 1000);
      logger.warn(`OTP verification failed: Code expired ${diffSec} seconds ago for ${normalizedEmail}`);
      emailOtpCache.delete(normalizedEmail);
      throw new UnauthorizedError('Verification code has expired');
    }

    if (cached.otp.trim() !== normalizedCode) {
      logger.warn(`OTP mismatch for ${normalizedEmail}. Expected: '${cached.otp}' (len ${cached.otp.length}), Received: '${normalizedCode}' (len ${normalizedCode.length})`);
      throw new UnauthorizedError('Invalid verification code');
    }

    // Clear OTP after successful use
    emailOtpCache.delete(normalizedEmail);

    const db = request.server.db;
    const ip = request.ip;
    const userAgent = request.headers['user-agent'] || 'unknown';

    // 1. Check if user exists
    const userRes = await db.query('SELECT * FROM users WHERE username = $1', [normalizedEmail]);
    let user = userRes.rows[0];

    if (!user) {
      // Register user automatically! Use a random password hash since they use OTP
      const randomPassword = Helpers.hashPassword(Math.random().toString());
      const userInsert = await db.query(
        `INSERT INTO users (username, display_name, password_hash, status) 
         VALUES ($1, $2, $3, 'ACTIVE') RETURNING *`,
        [email.toLowerCase(), email.split('@')[0], await randomPassword]
      );
      user = userInsert.rows[0];
    }

    // 2. Check/insert device
    const deviceRes = await db.query(
      'SELECT * FROM devices WHERE user_id = $1 AND device_fingerprint = $2',
      [user.id, device_fingerprint]
    );
    let device = deviceRes.rows[0];

    if (!device) {
      // Mark as trusted immediately since they successfully verified their email
      const newDeviceRes = await db.query(
        `INSERT INTO devices (user_id, device_name, device_fingerprint, platform, public_key, is_trusted, trusted_at)
         VALUES ($1, $2, $3, $4, $5, TRUE, CURRENT_TIMESTAMP) RETURNING *`,
        [user.id, device_name, device_fingerprint, platform, public_key || null]
      );
      device = newDeviceRes.rows[0];
    } else {
      // Update device info and keep it trusted
      await db.query(
        'UPDATE devices SET last_active = CURRENT_TIMESTAMP, device_name = $1, public_key = COALESCE($2, public_key), is_trusted = TRUE, trusted_at = COALESCE(trusted_at, CURRENT_TIMESTAMP) WHERE id = $3',
        [device_name, public_key || null, device.id]
      );
      device.is_trusted = true; // Ensure local representation is true
    }

    // 3. Create session tokens
    const { accessToken, refreshToken } = await AuthService.createSession(
      db,
      request.server,
      user.id,
      device.id,
      ip,
      userAgent
    );

    const { password_hash, totp_secret, ...safeUser } = user;

    return reply.status(200).send({
      message: 'Verification successful',
      user: safeUser,
      device: {
        ...device,
        is_trusted: !!device.is_trusted
      },
      tokens: { accessToken, refreshToken }
    });
  }

  /**
   * TEMPORARY debug endpoint. Validates admin credentials without device/session logic.
   * Should be removed before production deployment.
   */
  public static async debugLogin(request: FastifyRequest<{ Body: { username: string; password: string } }>, reply: FastifyReply) {
    const { username, password } = request.body;
    const db = request.server.db;

    const userRes = await db.query('SELECT username, password_hash, role, status FROM users WHERE username = $1', [username.toLowerCase()]);
    const user = userRes.rows[0];

    if (!user) {
      return reply.status(200).send({ found: false, message: 'User not found in database' });
    }

    const passwordValid = await Helpers.comparePassword(password, user.password_hash);

    return reply.status(200).send({
      found: true,
      username: user.username,
      role: user.role,
      status: user.status,
      passwordValid,
      hashPrefix: user.password_hash?.substring(0, 20) + '...',
    });
  }

  /**
   * Diagnostic endpoint for checking E2EE status.
   */
  public static async e2eeDebugStatus(request: FastifyRequest, reply: FastifyReply) {
    const user = request.user as { userId: string; deviceId?: string } | undefined;
    if (!user || !user.deviceId) throw new UnauthorizedError();
    const db = request.server.db;

    const deviceRes = await db.query('SELECT * FROM devices WHERE id = $1', [user.deviceId]);
    const device = deviceRes.rows[0];

    if (!device) {
      throw new NotFoundError('Device not found');
    }

    const chatsRes = await db.query(`
      SELECT c.id as chat_id
      FROM chat_participants cp
      JOIN chats c ON cp.chat_id = c.id
      WHERE cp.user_id = $1
    `, [user.userId]);

    const chatStats = [];
    for (const chat of chatsRes.rows) {
      const chatDevices = await db.query(`
        SELECT COUNT(*) as total_devices,
               SUM(CASE WHEN d.public_key IS NOT NULL AND d.is_trusted = TRUE THEN 1 ELSE 0 END) as e2ee_capable_devices
        FROM chat_participants cp
        JOIN devices d ON cp.user_id = d.user_id
        WHERE cp.chat_id = $1
      `, [chat.chat_id]);
      
      const stats = chatDevices.rows[0];
      chatStats.push({
        chat_id: chat.chat_id,
        total_devices: Number(stats.total_devices),
        e2ee_capable_devices: Number(stats.e2ee_capable_devices)
      });
    }

    return reply.status(200).send({
      device_id: device.id,
      is_trusted: !!device.is_trusted,
      has_public_key: !!device.public_key,
      public_key: device.public_key,
      chat_stats: chatStats
    });
  }
}
