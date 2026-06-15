import { FastifyReply, FastifyRequest } from 'fastify';
import { ForbiddenError, UnauthorizedError } from './errors';
import { Role } from '../types';

export const Capability = {
  VIEW_EXTENDED_PROFILE: 'VIEW_EXTENDED_PROFILE',
  EDIT_ANY_PROFILE: 'EDIT_ANY_PROFILE',
  MANAGE_ROLES: 'MANAGE_ROLES',
  MANAGE_USER_STATUS: 'MANAGE_USER_STATUS',
  AUTO_TRUST_DEVICE: 'AUTO_TRUST_DEVICE',
  GRANT_SUPER_USER: 'GRANT_SUPER_USER',
} as const;

export type Capability = typeof Capability[keyof typeof Capability];

export { Role } from '../types';

export const RoleCapabilities: Record<Role, Set<Capability>> = {
  user: new Set<Capability>(),
  admin: new Set<Capability>([
    Capability.VIEW_EXTENDED_PROFILE,
    Capability.EDIT_ANY_PROFILE,
    Capability.MANAGE_USER_STATUS,
    Capability.AUTO_TRUST_DEVICE,
  ]),
  super_user: new Set<Capability>([
    Capability.VIEW_EXTENDED_PROFILE,
    Capability.EDIT_ANY_PROFILE,
    Capability.MANAGE_ROLES,
    Capability.MANAGE_USER_STATUS,
    Capability.AUTO_TRUST_DEVICE,
  ]),
  owner: new Set<Capability>([
    Capability.VIEW_EXTENDED_PROFILE,
    Capability.EDIT_ANY_PROFILE,
    Capability.MANAGE_ROLES,
    Capability.MANAGE_USER_STATUS,
    Capability.AUTO_TRUST_DEVICE,
    Capability.GRANT_SUPER_USER,
  ]),
};

export const hasCapability = (role: Role, capability: Capability): boolean => {
  return RoleCapabilities[role]?.has(capability) ?? false;
};

export const requireCapability = (capability: Capability) => {
  return async (request: FastifyRequest, reply: FastifyReply) => {
    const jwtUser = request.user as { userId: string } | undefined;
    if (!jwtUser || !jwtUser.userId) {
      throw new UnauthorizedError('Unauthorized');
    }

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

    const currentRole = (user.role || 'user') as Role;

    if (!hasCapability(currentRole, capability)) {
      throw new ForbiddenError('Forbidden: Insufficient privileges');
    }
  };
};
