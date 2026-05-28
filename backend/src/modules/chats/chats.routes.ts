import { FastifyInstance } from 'fastify';
import { ChatsController } from './chats.controller';

export default async function chatsRoutes(fastify: FastifyInstance) {
  // All routes are authenticated
  fastify.addHook('preValidation', fastify.authenticate);

  fastify.get('/', ChatsController.list);
  fastify.post('/', ChatsController.create);
  fastify.get('/:id/keys', ChatsController.keys);
}
