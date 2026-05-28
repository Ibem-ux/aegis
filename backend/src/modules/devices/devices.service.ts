import { Pool } from 'pg';
import { Device } from '../../types';
import { NotFoundError, BadRequestError } from '../../utils/errors';

export class DevicesService {
  /**
   * Retrieves all devices registered to a specific user.
   */
  public static async getUserDevices(db: Pool, userId: string): Promise<Device[]> {
    const res = await db.query<Device>(
      'SELECT * FROM devices WHERE user_id = $1 ORDER BY created_at DESC',
      [userId]
    );
    return res.rows;
  }

  /**
   * Approves (trusts) a device belonging to the same user.
   * Requires approval from a device that is already trusted.
   */
  public static async approveDevice(
    db: Pool,
    userId: string,
    targetDeviceId: string,
    approvingDeviceId: string
  ): Promise<Device> {
    // 1. Verify approving device is indeed trusted
    const approverRes = await db.query<Device>(
      'SELECT is_trusted FROM devices WHERE id = $1 AND user_id = $2',
      [approvingDeviceId, userId]
    );
    const approver = approverRes.rows[0];

    if (!approver || !approver.is_trusted) {
      throw new BadRequestError('Approving device must be a trusted device');
    }

    // 2. Trust target device
    const res = await db.query<Device>(
      `UPDATE devices 
       SET is_trusted = TRUE, 
           trusted_at = CURRENT_TIMESTAMP, 
           trusted_by_device_id = $1
       WHERE id = $2 AND user_id = $3 AND is_trusted = FALSE
       RETURNING *`,
      [approvingDeviceId, targetDeviceId, userId]
    );

    const device = res.rows[0];
    if (!device) {
      throw new NotFoundError('Untrusted device not found or already trusted');
    }

    return device;
  }

  /**
   * Revoke trust or remove a device.
   */
  public static async removeDevice(db: Pool, userId: string, targetDeviceId: string): Promise<void> {
    const res = await db.query(
      'DELETE FROM devices WHERE id = $1 AND user_id = $2',
      [targetDeviceId, userId]
    );

    if (res.rowCount === 0) {
      throw new NotFoundError('Device not found');
    }
  }
}
