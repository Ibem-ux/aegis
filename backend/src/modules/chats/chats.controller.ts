import { FastifyReply, FastifyRequest } from 'fastify';
import { ChatsService } from './chats.service';
import { CreateChatBody } from './chats.types';
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
}
