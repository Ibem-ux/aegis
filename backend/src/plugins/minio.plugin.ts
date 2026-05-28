import fp from 'fastify-plugin';
import { FastifyInstance } from 'fastify';
import { Client } from 'minio';
import { minioConfig } from '../config/minio';
import { config } from '../config';
import { logger } from '../utils/logger';

declare module 'fastify' {
  interface FastifyInstance {
    minio: Client;
  }
}

export default fp(async (fastify: FastifyInstance) => {
  const client = new Client(minioConfig);

  // Check if bucket exists, create if not
  try {
    const bucketExists = await client.bucketExists(config.minio.bucketName);
    if (!bucketExists) {
      await client.makeBucket(config.minio.bucketName, 'us-east-1');
      logger.info(`MinIO bucket "${config.minio.bucketName}" created successfully`);
    } else {
      logger.info(`MinIO bucket "${config.minio.bucketName}" already exists`);
    }
  } catch (error) {
    logger.warn('Failed to verify or create MinIO bucket. Make sure MinIO service is running.', error);
  }

  fastify.decorate('minio', client);
});
