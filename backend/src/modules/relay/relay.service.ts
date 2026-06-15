import { EncryptedEnvelope } from '../../shared/envelope';
import { logger } from '../../utils/logger';

export class RelayService {
  public static async enqueue(
    db: { query: (sql: string, params: any[]) => Promise<{ rowCount: number }> },
    envelope: EncryptedEnvelope,
    recipientDeviceId: string,
    ttlSeconds: number
  ): Promise<void> {
    const now = new Date();
    const expiresAt = new Date(now.getTime() + ttlSeconds * 1000);

    const serialized = JSON.stringify(envelope);

    const sql = `
      INSERT INTO envelope_queue (message_id, recipient_device_id, envelope, created_at, expires_at)
      VALUES ($1, $2, $3, $4, $5)
      ON CONFLICT (message_id, recipient_device_id) DO NOTHING
    `;

    await db.query(sql, [
      envelope.messageId,
      recipientDeviceId,
      serialized,
      now.toISOString(),
      expiresAt.toISOString(),
    ]);

    logger.debug(`Enqueued envelope ${envelope.messageId} for device ${recipientDeviceId}`);
  }

  public static async listForDevice(
    db: { query: <T = any>(sql: string, params: any[]) => Promise<{ rows: T[] }> },
    recipientDeviceId: string
  ): Promise<EncryptedEnvelope[]> {
    const sql = `
      SELECT envelope
      FROM envelope_queue
      WHERE recipient_device_id = $1
        AND expires_at > NOW()
      ORDER BY created_at ASC
    `;

    const res = await db.query(sql, [recipientDeviceId]);

    return res.rows.map((row: { envelope: string }) => JSON.parse(row.envelope) as EncryptedEnvelope);
  }

  public static async remove(
    db: { query: (sql: string, params: any[]) => Promise<{ rowCount: number }> },
    messageId: string,
    recipientDeviceId: string
  ): Promise<void> {
    const sql = `
      DELETE FROM envelope_queue
      WHERE message_id = $1 AND recipient_device_id = $2
    `;

    await db.query(sql, [messageId, recipientDeviceId]);
    logger.debug(`Removed envelope ${messageId} for device ${recipientDeviceId} from queue`);
  }
}
