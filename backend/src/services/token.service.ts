import { FastifyInstance } from 'fastify';
import { EncryptionService } from './encryption.service';

export interface TokenPayload {
  userId: string;
  deviceId: string;
  sessionId: string;
}

export class TokenService {
  /**
   * Generates a short-lived access JWT token.
   */
  public static generateAccessToken(fastify: FastifyInstance, payload: TokenPayload): string {
    return fastify.jwt.sign(payload, {
      expiresIn: '15m'
    });
  }

  /**
   * Generates a long-lived cryptographically secure random refresh token.
   */
  public static generateRefreshToken(): string {
    // 64 random bytes hex = 128 characters
    return EncryptionService.generateSecureToken(64);
  }
}
