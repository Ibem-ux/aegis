import { authenticator } from 'otplib';
import qrcode from 'qrcode';

export class OtpService {
  /**
   * Generates a new TOTP base32 secret.
   */
  public static generateSecret(): string {
    return authenticator.generateSecret();
  }

  /**
   * Generates a TOTP key URI for authenticator apps (e.g., Google Authenticator, Aegis).
   */
  public static getKeyUri(username: string, secret: string): string {
    return authenticator.keyuri(username, 'ibemCom', secret);
  }

  /**
   * Generates a base64 Data URL for a QR code from a key URI.
   */
  public static async generateQrCodeDataUrl(keyUri: string): Promise<string> {
    try {
      return await qrcode.toDataURL(keyUri);
    } catch (error) {
      throw new Error(`Failed to generate QR code data URL: ${error}`);
    }
  }

  /**
   * Verifies a TOTP token against a user's secret.
   */
  public static verifyToken(token: string, secret: string): boolean {
    try {
      return authenticator.verify({ token, secret });
    } catch (error) {
      return false;
    }
  }
}
