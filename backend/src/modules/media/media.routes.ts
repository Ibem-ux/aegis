import { FastifyInstance } from 'fastify';
import { MediaController } from './media.controller';

export default async function mediaRoutes(fastify: FastifyInstance) {
  // Public PUT endpoint for actual file uploads (mimics direct upload to object storage)
  fastify.put('/upload-file/:uploaderId/:filename', MediaController.uploadFile);

  // Authenticated routes for obtaining pre-signed URLs
  fastify.register(async (authRoutes) => {
    authRoutes.addHook('preValidation', fastify.authenticate);

    authRoutes.get('/upload', MediaController.getUploadUrl);
    authRoutes.get('/download/:id', MediaController.getDownloadUrl);
  });
}
