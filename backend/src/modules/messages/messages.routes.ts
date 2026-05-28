import { FastifyInstance } from 'fastify';
import { MessagesController } from './messages.controller';

export default async function messagesRoutes(fastify: FastifyInstance) {
  // All routes are authenticated
  fastify.addHook('preValidation', fastify.authenticate);

  fastify.get('/:chatId', MessagesController.list);
  fastify.post('/', MessagesController.create);
}
