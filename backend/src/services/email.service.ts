import nodemailer from 'nodemailer';
import { config } from '../config';
import { logger } from '../utils/logger';

export class EmailService {
  private static transporter: nodemailer.Transporter | null = null;

  private static getTransporter(): nodemailer.Transporter {
    if (!this.transporter) {
      const isSecure = config.email.smtpPort === 465;
      this.transporter = nodemailer.createTransport({
        host: config.email.smtpHost,
        port: config.email.smtpPort,
        secure: isSecure, // true for 465 (TLS), false for 587 (STARTTLS)
        ...((!isSecure) && { requireTLS: true }), // Force STARTTLS upgrade on port 587
        auth: {
          user: config.email.smtpUser,
          pass: config.email.smtpPass,
        },
        tls: {
          rejectUnauthorized: false, // Allow self-signed certs in dev environments
        },
        connectionTimeout: 10000, // 10s connect timeout
        socketTimeout: 15000,     // 15s socket timeout
      });
    }
    return this.transporter;
  }

  /**
   * Verifies the SMTP connection at startup.
   * Returns true if the connection is healthy, false otherwise.
   * Does NOT throw — safe to call during boot without crashing the server.
   */
  public static async verify(): Promise<boolean> {
    const hasConfig = config.email.smtpUser && config.email.smtpPass;
    if (!hasConfig) {
      logger.warn('⚠️ SMTP credentials not configured — email delivery is disabled (OTPs will be logged to console)');
      return false;
    }

    try {
      const transporter = this.getTransporter();
      await transporter.verify();
      return true;
    } catch (error: any) {
      // Reset the transporter so it can be recreated on next attempt
      this.transporter = null;
      const code = error.code || 'UNKNOWN';
      const msg = error.message || String(error);
      logger.error(`SMTP verification failed [${code}]: ${msg}`);
      return false;
    }
  }

  /**
   * Sends a 6-digit OTP verification code to the target email.
   * If SMTP settings are missing, it falls back to console logging.
   * Returns true on success, false on failure.
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
        text: `Your Aegis verification code is: ${otp}\n\nThis code will expire in 15 minutes.`,
        html: `
          <div style="font-family: sans-serif; padding: 20px; color: #333; max-width: 500px; margin: auto; border: 1px solid #eee; border-radius: 10px;">
            <h2 style="color: #2196F3; text-align: center;">Aegis Secure Messenger</h2>
            <p>You requested a login verification code for Aegis. Use the following OTP to authorize your device:</p>
            <div style="background-color: #f5f5f5; font-size: 28px; font-weight: bold; text-align: center; letter-spacing: 5px; padding: 15px; margin: 20px 0; border-radius: 5px; color: #333;">
              ${otp}
            </div>
            <p style="font-size: 12px; color: #777;">This code is valid for 15 minutes. If you did not request this code, please ignore this email.</p>
          </div>
        `,
      };

      await transporter.sendMail(mailOptions);
      logger.info(`✅ Successfully sent OTP email to: ${email}`);
      return true;
    } catch (error: any) {
      // Reset the transporter so a fresh connection is created on retry
      this.transporter = null;

      const code = error.code || 'UNKNOWN';
      const msg = error.message || String(error);
      const responseCode = error.responseCode || '';
      logger.error(`❌ Failed to send OTP email to ${email} [${code}${responseCode ? '/' + responseCode : ''}]: ${msg}`);
      return false;
    }
  }
}
