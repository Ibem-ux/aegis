import { FastifyInstance } from 'fastify';
import { InvitesController } from './invites.controller';

export default async function invitesRoutes(fastify: FastifyInstance) {
  // All routes are authenticated
  fastify.addHook('preValidation', fastify.authenticate);

  fastify.post('/', InvitesController.create);
  fastify.get('/', InvitesController.list);
  fastify.delete('/:id', InvitesController.revoke);
}
