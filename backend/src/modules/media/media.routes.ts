import { FastifyInstance } from 'fastify';
import { MediaController } from './media.controller';

export default async function mediaRoutes(fastify: FastifyInstance) {
  // All routes are authenticated
  fastify.addHook('preValidation', fastify.authenticate);

  fastify.get('/upload', MediaController.getUploadUrl);
  fastify.get('/download/:id', MediaController.getDownloadUrl);
}
