import crypto from 'crypto';
import { config } from '../config';

export class EncryptionService {
  private static key = Buffer.from(config.security.masterEncryptionKey, 'hex');
  private static algorithm = 'aes-256-gcm';

  /**
   * Encrypts plaintext using AES-256-GCM.
   * Returns ciphertext buffer, initialization vector (iv) buffer, and authentication tag buffer.
   */
  public static encrypt(plaintext: string): { ciphertext: Buffer; iv: Buffer; tag: Buffer } {
    // 12 bytes IV is standard for GCM
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv(this.algorithm, this.key, iv) as crypto.CipherGCM;
    
    const ciphertext = Buffer.concat([
      cipher.update(plaintext, 'utf8'),
      cipher.final()
    ]);
    
    const tag = cipher.getAuthTag();

    return {
      ciphertext,
      iv,
      tag
    };
  }

  /**
   * Decrypts ciphertext buffer using AES-256-GCM.
   * Returns plaintext string.
   */
  public static decrypt(ciphertext: Buffer, iv: Buffer, tag: Buffer): string {
    const decipher = crypto.createDecipheriv(this.algorithm, this.key, iv) as crypto.DecipherGCM;
    decipher.setAuthTag(tag);
    
    const plaintext = Buffer.concat([
      decipher.update(ciphertext),
      decipher.final()
    ]);

    return plaintext.toString('utf8');
  }

  /**
   * Hash a raw token (like a refresh token) using SHA-256
   * so it can be stored securely in the database.
   */
  public static hashToken(token: string): string {
    return crypto.createHash('sha256').update(token).digest('hex');
  }

  /**
   * Generate a random secure token string (e.g. for invite codes, refresh tokens)
   */
  public static generateSecureToken(bytes: number = 32): string {
    return crypto.randomBytes(bytes).toString('hex');
  }
}
