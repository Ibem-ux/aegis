import { FastifyReply, FastifyRequest } from 'fastify';
import { AuthService } from './auth.service';
import { OtpService } from '../../services/otp.service';
import { Helpers } from '../../utils/helpers';
import { RegisterBody, LoginBody, RefreshBody, VerifyOtpBody } from './auth.types';
import { BadRequestError, UnauthorizedError, ForbiddenError } from '../../utils/errors';
import { logger } from '../../utils/logger';

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
}
