import { FastifyReply, FastifyRequest } from 'fastify';
import { UsersService } from './users.service';
import { UpdateProfileBody, UserQueryParams, ChangePasswordBody, RecoverAccountBody } from './users.types';
import { UnauthorizedError, BadRequestError } from '../../utils/errors';

export class UsersController {
  public static async getMe(request: FastifyRequest, reply: FastifyReply) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const profile = await UsersService.getProfile(request.server.db, user.userId, user.userId);
    return reply.status(200).send(profile);
  }

  public static async getUserProfile(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply
  ) {
    const requester = request.user as { userId: string } | undefined;
    if (!requester) throw new UnauthorizedError();

    const profile = await UsersService.getProfile(request.server.db, request.params.id, requester.userId);
    return reply.status(200).send(profile);
  }

  public static async updateProfile(
    request: FastifyRequest<{ Params?: { id?: string }; Body: UpdateProfileBody }>,
    reply: FastifyReply
  ) {
    const requester = request.user as { userId: string } | undefined;
    if (!requester) throw new UnauthorizedError();

    const targetUserId = request.params?.id || requester.userId;

    const profile = await UsersService.updateProfile(
      request.server.db,
      targetUserId,
      requester.userId,
      request.body
    );
    return reply.status(200).send({
      message: 'Profile updated successfully',
      user: profile
    });
  }

  public static async search(
    request: FastifyRequest<{ Querystring: UserQueryParams }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const searchQuery = request.query.search || '';
    const users = await UsersService.searchUsers(request.server.db, searchQuery, user.userId);
    return reply.status(200).send(users);
  }

  public static async changePassword(
    request: FastifyRequest<{ Body: ChangePasswordBody }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string; sessionId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const { current_password, new_password } = request.body;
    if (!current_password || !new_password) {
      throw new BadRequestError('Current password and new password are required');
    }

    await UsersService.changePassword(
      request.server.db,
      user.userId,
      current_password,
      new_password,
      user.sessionId
    );

    return reply.status(200).send({
      message: 'Password changed successfully. All other device sessions have been invalidated.'
    });
  }

  public static async getSessions(request: FastifyRequest, reply: FastifyReply) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const sessions = await UsersService.getActiveSessions(request.server.db, user.userId);
    return reply.status(200).send(sessions);
  }

  public static async revokeSession(
    request: FastifyRequest<{ Params: { sessionId: string } }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string; sessionId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    await UsersService.revokeSession(
      request.server.db,
      user.userId,
      request.params.sessionId,
      user.sessionId
    );

    return reply.status(200).send({
      message: 'Session revoked successfully'
    });
  }

  public static async generateRecoveryKey(request: FastifyRequest, reply: FastifyReply) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const rawKey = await UsersService.generateMasterRecoveryKey(request.server.db, user.userId);
    return reply.status(200).send({
      message: 'Master Recovery Key generated. Keep it safe. It is stored hashed.',
      recovery_key: rawKey
    });
  }

  public static async recoverAccount(
    request: FastifyRequest<{ Body: RecoverAccountBody }>,
    reply: FastifyReply
  ) {
    const { username, recovery_key, new_password } = request.body;
    if (!username || !recovery_key || !new_password) {
      throw new BadRequestError('Username, recovery_key, and new_password are required');
    }

    await UsersService.recoverViaMasterKey(
      request.server.db,
      username,
      recovery_key,
      new_password
    );

    return reply.status(200).send({
      message: 'Account recovered and password updated successfully. All active sessions have been invalidated. Please log in with your new password.'
    });
  }
}
