import { Pool } from 'pg';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { exec } from 'child_process';
import { promisify } from 'util';
import { config } from '../config';
import { logger } from '../utils/logger';

const execAsync = promisify(exec);

export class BackupService {
  private static backupDir = path.resolve(__dirname, '../../../backups');
  private static backupKey = Buffer.from(config.security.backupEncryptionKey, 'hex');

  private static getPgDumpPath(): string {
    const commonPaths = [
      'C:\\Program Files\\PostgreSQL\\18\\bin\\pg_dump.exe',
      'C:\\Program Files\\PostgreSQL\\17\\bin\\pg_dump.exe',
      'C:\\Program Files\\PostgreSQL\\16\\bin\\pg_dump.exe',
      'C:\\Program Files\\PostgreSQL\\15\\bin\\pg_dump.exe',
      'C:\\Program Files\\PostgreSQL\\14\\bin\\pg_dump.exe',
    ];
    for (const p of commonPaths) {
      if (fs.existsSync(p)) {
        return `"${p}"`;
      }
    }
    return 'pg_dump'; // fallback to PATH
  }

  /**
   * Initializes the backups directory.
   */
  public static init() {
    if (!fs.existsSync(this.backupDir)) {
      fs.mkdirSync(this.backupDir, { recursive: true });
    }
  }

  /**
   * Performs an encrypted database backup.
   * Uses VACUUM INTO for SQLite or pg_dump for PostgreSQL.
   */
  public static async runDatabaseBackup(db: Pool, creatorId?: string): Promise<string> {
    this.init();
    
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const encryptedFile = path.join(this.backupDir, `db-backup-${timestamp}.enc`);

    // Insert initial record in backups table
    const backupRecord = await db.query(
      `INSERT INTO backups (backup_type, file_path, file_size, status)
       VALUES ('DATABASE', $1, 0, 'STARTED')
       RETURNING id`,
      [encryptedFile]
    );
    const backupId = backupRecord.rows[0].id;

    logger.info(`Starting database backup task ${backupId}`);

    let tempFile: string;

    try {
      if (config.database.type === 'postgres') {
        // ─── PostgreSQL Backup via pg_dump ─────────────────────────────────
        tempFile = path.join(this.backupDir, `db-temp-${timestamp}.sql`);
        logger.info('Running pg_dump for PostgreSQL backup...');

        // pg_dump uses the DATABASE_URL connection string
        const pgDumpBin = BackupService.getPgDumpPath();
        const { stderr } = await execAsync(
          `${pgDumpBin} "${config.database.url}" --format=custom --file="${tempFile}"`,
          { timeout: 120000 } // 2 minute timeout
        );

        if (stderr && !stderr.includes('WARNING')) {
          logger.warn(`pg_dump stderr: ${stderr}`);
        }

        logger.info('pg_dump completed successfully');
      } else {
        // ─── SQLite Backup via VACUUM INTO ─────────────────────────────────
        tempFile = path.join(this.backupDir, `db-temp-${timestamp}.sqlite`);

        // Execute vacuum to dump database atomically
        // Escape tempFile path for SQLite single quotes
        const escapedTempFile = tempFile.replace(/'/g, "''");
        await db.query(`VACUUM INTO '${escapedTempFile}'`);
      }

      // Read the backup file
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
      if (fs.existsSync(tempFile)) fs.unlinkSync(tempFile);

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
      return encryptedFile;
    } catch (err: any) {
      logger.error(`Database backup failed: ${err.message}`, err);
      
      await db.query('UPDATE backups SET status = \'FAILED\', completed_at = CURRENT_TIMESTAMP WHERE id = $1', [backupId]);
      
      if (tempFile! && fs.existsSync(tempFile!)) fs.unlinkSync(tempFile!);
      if (fs.existsSync(encryptedFile)) fs.unlinkSync(encryptedFile);
      
      throw err;
    }
  }

  /**
   * Decrypts an encrypted backup archive back to a plaintext file.
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
