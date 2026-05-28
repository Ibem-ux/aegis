import { FastifyReply, FastifyRequest } from 'fastify';
import { UsersService } from './users.service';
import { UpdateProfileBody, UserQueryParams } from './users.types';
import { UnauthorizedError } from '../../utils/errors';

export class UsersController {
  public static async getMe(request: FastifyRequest, reply: FastifyReply) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const profile = await UsersService.getProfile(request.server.db, user.userId);
    return reply.status(200).send(profile);
  }

  public static async updateProfile(
    request: FastifyRequest<{ Body: UpdateProfileBody }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const profile = await UsersService.updateProfile(request.server.db, user.userId, request.body);
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
}
