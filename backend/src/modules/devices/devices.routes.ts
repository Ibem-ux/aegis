import { FastifyInstance } from 'fastify';
import { DevicesController } from './devices.controller';
import { deviceApproveSchema } from '../auth/auth.schema';

export default async function devicesRoutes(fastify: FastifyInstance) {
  // All routes are authenticated
  fastify.addHook('preValidation', fastify.authenticate);

  fastify.get('/', DevicesController.list);
  fastify.post('/approve', { schema: deviceApproveSchema }, DevicesController.approve);
  fastify.delete('/:id', DevicesController.remove);
}
