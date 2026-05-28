import { Pool } from 'pg';
import { exec } from 'child_process';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { config } from '../config';
import { logger } from '../utils/logger';

export class BackupService {
  private static backupDir = path.resolve(__dirname, '../../../backups');
  private static backupKey = Buffer.from(config.security.backupEncryptionKey, 'hex');

  /**
   * Initializes the backups directory.
   */
  public static init() {
    if (!fs.existsSync(this.backupDir)) {
      fs.mkdirSync(this.backupDir, { recursive: true });
    }
  }

  /**
   * Performs an encrypted PostgreSQL database backup using pg_dump.
   */
  public static async runDatabaseBackup(db: Pool, creatorId?: string): Promise<string> {
    this.init();
    
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const tempFile = path.join(this.backupDir, `db-temp-${timestamp}.sql`);
    const encryptedFile = path.join(this.backupDir, `db-backup-${timestamp}.enc`);

    // Parse DB URL to get credentials for pg_dump
    // postgresql://user:pass@host:port/db
    const connectionUrl = config.database.url;

    // Insert initial record in backups table
    const backupRecord = await db.query(
      `INSERT INTO backups (backup_type, file_path, file_size, status)
       VALUES ('DATABASE', $1, 0, 'STARTED')
       RETURNING id`,
      [encryptedFile]
    );
    const backupId = backupRecord.rows[0].id;

    logger.info(`Starting database backup task ${backupId}`);

    return new Promise((resolve, reject) => {
      // Execute pg_dump
      exec(`pg_dump "${connectionUrl}" > "${tempFile}"`, async (error, stdout, stderr) => {
        if (error) {
          logger.error(`Database backup failed during pg_dump: ${stderr}`, error);
          await db.query('UPDATE backups SET status = \'FAILED\', completed_at = CURRENT_TIMESTAMP WHERE id = $1', [backupId]);
          if (fs.existsSync(tempFile)) fs.unlinkSync(tempFile);
          return reject(error);
        }

        try {
          // Read the plaintext file
          const plaintext = fs.readFileSync(tempFile);

          // Encrypt file content using AES-256-GCM
          const iv = crypto.randomBytes(12);
          const cipher = crypto.createCipheriv('aes-256-gcm', this.backupKey, iv);
          
          const ciphertext = Buffer.concat([
            cipher.update(plaintext),
            cipher.final()
          ]);
          const tag = cipher.getAuthTag();

          // Write encrypted archive: [12-byte IV][16-byte TAG][Encrypted Data]
          const finalBuffer = Buffer.concat([iv, tag, ciphertext]);
          fs.writeFileSync(encryptedFile, finalBuffer);

          // Compute SHA-256 Checksum
          const checksum = crypto.createHash('sha256').update(finalBuffer).digest('hex');
          const fileSize = finalBuffer.length;

          // Cleanup temp file
          fs.unlinkSync(tempFile);

          // Update backup record
          await db.query(
            `UPDATE backups 
             SET status = 'COMPLETED', 
                 file_size = $1, 
                 checksum = $2, 
                 completed_at = CURRENT_TIMESTAMP,
                 created_by = $3
             WHERE id = $4`,
            [fileSize, checksum, creatorId || null, backupId]
          );

          logger.info(`Database backup ${backupId} completed successfully`);
          resolve(encryptedFile);
        } catch (err: any) {
          logger.error(`Database backup encryption failed: ${err.message}`, err);
          await db.query('UPDATE backups SET status = \'FAILED\', completed_at = CURRENT_TIMESTAMP WHERE id = $1', [backupId]);
          if (fs.existsSync(tempFile)) fs.unlinkSync(tempFile);
          if (fs.existsSync(encryptedFile)) fs.unlinkSync(encryptedFile);
          reject(err);
        }
      });
    });
  }

  /**
   * Decrypts an encrypted backup archive back to plaintext SQL.
   */
  public static decryptBackup(encryptedFilePath: string, outputFilePath: string) {
    const fileBuffer = fs.readFileSync(encryptedFilePath);
    
    // Extract metadata: IV, tag, ciphertext
    const iv = fileBuffer.subarray(0, 12);
    const tag = fileBuffer.subarray(12, 28);
    const ciphertext = fileBuffer.subarray(28);

    const decipher = crypto.createDecipheriv('aes-256-gcm', this.backupKey, iv);
    decipher.setAuthTag(tag);

    const plaintext = Buffer.concat([
      decipher.update(ciphertext),
      decipher.final()
    ]);

    fs.writeFileSync(outputFilePath, plaintext);
    logger.info(`Decrypted backup saved to ${outputFilePath}`);
  }
}
