import nodemailer from 'nodemailer';
import { config } from '../config';
import { logger } from '../utils/logger';

export class EmailService {
  private static transporter: nodemailer.Transporter | null = null;

  private static getTransporter(): nodemailer.Transporter {
    if (!this.transporter) {
      this.transporter = nodemailer.createTransport({
        host: config.email.smtpHost,
        port: config.email.smtpPort,
        secure: config.email.smtpPort === 465, // true for 465, false for other ports
        auth: {
          user: config.email.smtpUser,
          pass: config.email.smtpPass,
        },
      });
    }
    return this.transporter;
  }

  /**
   * Sends a 6-digit OTP verification code to the target email.
   * If SMTP settings are missing, it falls back to console logging.
   */
  public static async sendOtp(email: string, otp: string): Promise<boolean> {
    const hasConfig = config.email.smtpUser && config.email.smtpPass;

    if (!hasConfig) {
      logger.warn('**************************************************');
      logger.warn(`[DEV LOG] SMTP credentials not set. OTP for ${email}: ${otp}`);
      logger.warn('**************************************************');
      return true;
    }

    try {
      const transporter = this.getTransporter();
      const mailOptions = {
        from: `"Aegis Secure Messenger" <${config.email.smtpUser}>`,
        to: email,
        subject: 'Aegis Device Authentication Code',
        text: `Your Aegis verification code is: ${otp}\n\nThis code will expire in 5 minutes.`,
        html: `
          <div style="font-family: sans-serif; padding: 20px; color: #333; max-width: 500px; margin: auto; border: 1px solid #eee; border-radius: 10px;">
            <h2 style="color: #2196F3; text-align: center;">Aegis Secure Messenger</h2>
            <p>You requested a login verification code for Aegis. Use the following OTP to authorize your device:</p>
            <div style="background-color: #f5f5f5; font-size: 28px; font-weight: bold; text-align: center; letter-spacing: 5px; padding: 15px; margin: 20px 0; border-radius: 5px; color: #333;">
              ${otp}
            </div>
            <p style="font-size: 12px; color: #777;">This code is valid for 5 minutes. If you did not request this code, please ignore this email.</p>
          </div>
        `,
      };

      await transporter.sendMail(mailOptions);
      logger.info(`Successfully sent OTP email to: ${email}`);
      return true;
    } catch (error) {
      logger.error(`Failed to send OTP email to ${email}`, error);
      return false;
    }
  }
}
