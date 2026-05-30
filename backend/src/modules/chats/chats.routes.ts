import { FastifyInstance } from 'fastify';
import { ChatsController } from './chats.controller';

export default async function chatsRoutes(fastify: FastifyInstance) {
  // All routes are authenticated
  fastify.addHook('preValidation', fastify.authenticate);

  fastify.get('/', ChatsController.list);
  fastify.post('/', ChatsController.create);
  fastify.get('/:id/keys', ChatsController.keys);
  // Invite endpoints
  fastify.post('/invites', ChatsController.createInvite);
  fastify.get('/invites', ChatsController.listInvites);
  fastify.patch('/invites/:id', ChatsController.toggleInvite);
  fastify.delete('/invites/:id', ChatsController.deleteInvite);
  fastify.post('/invites/accept', ChatsController.acceptInvite);
}
