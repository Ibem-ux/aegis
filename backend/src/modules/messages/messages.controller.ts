import { FastifyReply, FastifyRequest } from 'fastify';
import { MessagesService } from './messages.service';
import { GetMessagesQuery, SendMessageBody } from './messages.types';
import { UnauthorizedError } from '../../utils/errors';

export class MessagesController {
  public static async list(
    request: FastifyRequest<{ Params: { chatId: string }; Querystring: GetMessagesQuery }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const { chatId } = request.params;
    const { limit, before } = request.query;

    const messages = await MessagesService.getChatMessages(
      request.server.db,
      chatId,
      user.userId,
      {
        limit: limit ? Number(limit) : undefined,
        before
      }
    );

    return reply.status(200).send(messages);
  }

  public static async create(
    request: FastifyRequest<{ Body: SendMessageBody }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const message = await MessagesService.sendMessage(
      request.server.db,
      user.userId,
      request.body
    );

    // Relay via Socket.IO if recipient is online
    const io = request.server.io;
    if (io) {
      for (const recId of message.recipients) {
        io.to(`user:${recId}`).emit('message:receive', {
          id: message.id,
          chat_id: message.chat_id,
          sender: message.sender,
          content: message.content,
          message_type: message.message_type,
          reply_to_id: message.reply_to_id,
          media_id: message.media_id,
          created_at: message.created_at
        });
      }
    }

    return reply.status(201).send(message);
  }
}
