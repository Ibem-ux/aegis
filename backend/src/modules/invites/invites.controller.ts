import { FastifyReply, FastifyRequest } from 'fastify';
import { InvitesService } from './invites.service';
import { CreateInviteBody } from './invites.types';
import { UnauthorizedError } from '../../utils/errors';

export class InvitesController {
  public static async create(
    request: FastifyRequest<{ Body: CreateInviteBody }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const invite = await InvitesService.createInvite(request.server.db, user.userId, request.body);
    return reply.status(201).send({
      message: 'Invite generated successfully',
      invite
    });
  }

  public static async list(request: FastifyRequest, reply: FastifyReply) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const invites = await InvitesService.getMyInvites(request.server.db, user.userId);
    return reply.status(200).send(invites);
  }

  public static async revoke(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const inviteId = request.params.id;
    await InvitesService.revokeInvite(request.server.db, inviteId, user.userId);
    return reply.status(200).send({
      message: 'Invite revoked successfully'
    });
  }
}
