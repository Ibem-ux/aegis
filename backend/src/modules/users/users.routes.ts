import { FastifyInstance } from 'fastify';
import { UsersController } from './users.controller';

export default async function usersRoutes(fastify: FastifyInstance) {
  // Enforce auth globally for all user routes
  fastify.addHook('preValidation', fastify.authenticate);

  fastify.get('/me', UsersController.getMe);
  fastify.put('/me', UsersController.updateProfile);
  fastify.get('/search', UsersController.search);
}
