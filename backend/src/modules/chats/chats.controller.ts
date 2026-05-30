import { FastifyReply, FastifyRequest } from 'fastify';
import { ChatsService } from './chats.service';
import { CreateChatBody, CreateInviteLinkBody, AcceptInviteBody } from './chats.types';
import { UnauthorizedError } from '../../utils/errors';

export class ChatsController {
  public static async list(request: FastifyRequest, reply: FastifyReply) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const chats = await ChatsService.getUserChats(request.server.db, user.userId);
    return reply.status(200).send(chats);
  }

  public static async create(
    request: FastifyRequest<{ Body: CreateChatBody }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const { recipient_id } = request.body;
    const chatResult = await ChatsService.createOrGetChat(
      request.server.db,
      user.userId,
      recipient_id
    );

    return reply.status(chatResult.isNew ? 201 : 200).send({
      message: chatResult.isNew ? 'Chat conversation created' : 'Chat conversation retrieved',
      chat_id: chatResult.chat_id
    });
  }

  public static async keys(request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const keys = await ChatsService.getChatParticipantPublicKeys(
      request.server.db,
      request.params.id,
      user.userId
    );
    return reply.status(200).send(keys);
  }

  public static async createInvite(
    request: FastifyRequest<{ Body: CreateInviteLinkBody }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const invite = await ChatsService.createInviteLink(
      request.server.db,
      user.userId,
      request.body
    );

    return reply.status(201).send(invite);
  }

  public static async listInvites(request: FastifyRequest, reply: FastifyReply) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const invites = await ChatsService.getUserInviteLinks(request.server.db, user.userId);
    return reply.status(200).send(invites);
  }

  public static async toggleInvite(
    request: FastifyRequest<{ Params: { id: string }, Body: { is_active: boolean } }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    await ChatsService.toggleInviteLinkActive(request.server.db, user.userId, request.params.id, request.body.is_active);
    return reply.status(200).send({
      message: 'Invite link status updated'
    });
  }

  public static async deleteInvite(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    await ChatsService.deleteInviteLink(request.server.db, user.userId, request.params.id);
    return reply.status(204).send();
  }

  public static async acceptInvite(
    request: FastifyRequest<{ Body: AcceptInviteBody }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const result = await ChatsService.acceptInviteLink(
      request.server.db,
      user.userId,
      request.body.token
    );

    // Fetch the claimer's profile and keys to notify the creator
    const claimerProfileRes = await request.server.db.query(
      `SELECT id, username, display_name, avatar_url, last_seen FROM users WHERE id = $1`,
      [user.userId]
    );
    const claimerProfile = claimerProfileRes.rows[0];

    const claimerKeys = await ChatsService.getChatParticipantPublicKeys(
      request.server.db,
      result.chat_id,
      user.userId
    );
    
    // Filter just claimer's keys from the participants
    const bobKeys = claimerKeys.filter((k: any) => k.user_id === user.userId);

    // Notify the creator that their invite was accepted
    request.server.io.to(`user:${result.creator_id}`).emit('chat_created', {
      chat_id: result.chat_id,
      claimer_profile: claimerProfile,
      claimer_keys: bobKeys,
    });

    return reply.status(200).send(result);
  }
}
