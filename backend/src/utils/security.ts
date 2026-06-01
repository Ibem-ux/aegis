import { FastifyReply, FastifyRequest } from 'fastify';
import { ForbiddenError, UnauthorizedError } from './errors';

export class SecurityUtils {
  /**
   * Validates password strength:
   * - At least 12 characters long
   * - Contains at least 1 uppercase letter
   * - Contains at least 1 lowercase letter
   * - Contains at least 1 number
   * - Contains at least 1 special character
   */
  public static validatePasswordStrength(password: string): boolean {
    if (password.length < 12) return false;
    const hasUpper = /[A-Z]/.test(password);
    const hasLower = /[a-z]/.test(password);
    const hasNumber = /[0-9]/.test(password);
    const hasSpecial = /[^A-Za-z0-9]/.test(password);
    return hasUpper && hasLower && hasNumber && hasSpecial;
  }

  /**
   * Factory function that returns a preHandler hook to enforce roles.
   * Superadmin always bypasses restrictions.
   */
  public static requireRole(allowedRoles: ('user' | 'admin')[]) {
    return async (request: FastifyRequest, reply: FastifyReply) => {
      const jwtUser = request.user as { userId: string } | undefined;
      if (!jwtUser || !jwtUser.userId) {
        throw new UnauthorizedError('Unauthorized');
      }

      // Query database to get latest role and status
      const res = await request.server.db.query(
        'SELECT role, status FROM users WHERE id = $1',
        [jwtUser.userId]
      );
      const user = res.rows[0];

      if (!user) {
        throw new UnauthorizedError('User not found');
      }

      if (user.status !== 'ACTIVE') {
        throw new ForbiddenError('User account is suspended or inactive');
      }

      // Map legacy or default role if they have it
      const currentRole = user.role || 'user';

      if (!allowedRoles.includes(currentRole as any)) {
        throw new ForbiddenError('Forbidden: Insufficient privileges');
      }
    };
  }
}
