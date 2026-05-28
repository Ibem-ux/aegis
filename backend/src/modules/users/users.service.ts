import { Pool } from 'pg';
import { User } from '../../types';
import { NotFoundError } from '../../utils/errors';

export class UsersService {
  /**
   * Fetches user profile by ID.
   */
  public static async getProfile(db: Pool, userId: string): Promise<Partial<User>> {
    const res = await db.query<User>(
      'SELECT id, username, display_name, avatar_url, status, last_seen, created_at FROM users WHERE id = $1',
      [userId]
    );
    const user = res.rows[0];
    if (!user) {
      throw new NotFoundError('User not found');
    }
    return user;
  }

  /**
   * Updates profile data.
   */
  public static async updateProfile(
    db: Pool,
    userId: string,
    payload: { display_name?: string; avatar_url?: string }
  ): Promise<Partial<User>> {
    const updates: string[] = [];
    const values: any[] = [];
    let idx = 1;

    if (payload.display_name !== undefined) {
      updates.push(`display_name = $${idx++}`);
      values.push(payload.display_name);
    }
    if (payload.avatar_url !== undefined) {
      updates.push(`avatar_url = $${idx++}`);
      values.push(payload.avatar_url);
    }

    if (updates.length === 0) {
      return this.getProfile(db, userId);
    }

    values.push(userId);
    const query = `
      UPDATE users 
      SET ${updates.join(', ')}, updated_at = CURRENT_TIMESTAMP 
      WHERE id = $${idx}
      RETURNING id, username, display_name, avatar_url, status, last_seen, created_at
    `;

    const res = await db.query<User>(query, values);
    const user = res.rows[0];
    if (!user) {
      throw new NotFoundError('User not found');
    }
    return user;
  }

  /**
   * Search users by username or display name.
   */
  public static async searchUsers(db: Pool, query: string, currentUserId: string): Promise<Partial<User>[]> {
    const res = await db.query<User>(
      `SELECT id, username, display_name, avatar_url, status, last_seen 
       FROM users 
       WHERE id != $1 AND (username ILIKE $2 OR display_name ILIKE $2)
       LIMIT 20`,
      [currentUserId, `%${query}%`]
    );
    return res.rows;
  }
}
