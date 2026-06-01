import { FastifyInstance } from 'fastify';
import { MediaController } from './media.controller';
import fastifyRateLimit from '@fastify/rate-limit';

export default async function mediaRoutes(fastify: FastifyInstance) {
  // Register a sub-context for the upload endpoint so the custom content-type
  // parser is scoped only to this route and does not affect others.
  fastify.register(async (uploadCtx) => {
    // 1 minute time window, max 5 uploads per IP
    await uploadCtx.register(fastifyRateLimit, {
      max: 5,
      timeWindow: '1 minute'
    });

    // Tell Fastify to accept ANY content-type on this route by passing
    // the raw Buffer through without parsing. This is required because
    // the frontend sends raw binary image bytes with Content-Type: image/*.
    uploadCtx.addContentTypeParser('*', { parseAs: 'buffer', bodyLimit: 10 * 1024 * 1024 }, (_req, body, done) => {
      done(null, body);
    });

    uploadCtx.put('/upload-file/:uploaderId/:filename', MediaController.uploadFile);
  });

  // Authenticated routes for obtaining pre-signed URLs
  fastify.register(async (authRoutes) => {
    authRoutes.addHook('preValidation', fastify.authenticate);

    authRoutes.get('/upload', MediaController.getUploadUrl);
    authRoutes.get('/download/:id', MediaController.getDownloadUrl);
  });
}
