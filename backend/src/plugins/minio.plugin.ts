import fp from 'fastify-plugin';
import { FastifyInstance } from 'fastify';
import fs from 'fs';
import path from 'path';
import { config } from '../config';
import { logger } from '../utils/logger';

declare module 'fastify' {
  interface FastifyInstance {
    minio: any;
  }
}

export default fp(async (fastify: FastifyInstance) => {
  const uploadPath = path.resolve(config.uploads.dir);

  // Ensure uploads directory exists
  if (!fs.existsSync(uploadPath)) {
    logger.info(`Creating media upload directory at: ${uploadPath}`);
    fs.mkdirSync(uploadPath, { recursive: true });
  } else {
    logger.info(`Media upload directory exists at: ${uploadPath}`);
  }

  // Decorate fastify with dummy object to avoid runtime errors on undefined references
  fastify.decorate('minio', {
    presignedPutObject: async () => '',
    presignedGetObject: async () => ''
  });
});
