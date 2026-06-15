import fastify, { FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import path from 'path';
import fastifyStatic from '@fastify/static';
import { config } from './config';
import { logger } from './utils/logger';
import { HttpError } from './utils/errors';

// Custom Plugins
import dbPlugin from './plugins/database.plugin';
import redisPlugin from './plugins/redis.plugin';
import minioPlugin from './plugins/minio.plugin';
import authPlugin from './plugins/auth.plugin';
import rateLimitPlugin from './plugins/rate-limit.plugin';
import socketPlugin from './plugins/socket.plugin';
import cleanupPlugin from './plugins/cleanup.plugin';

// Route Modules
import authRoutes from './modules/auth/auth.routes';
import usersRoutes from './modules/users/users.routes';
import invitesRoutes from './modules/invites/invites.routes';
import devicesRoutes from './modules/devices/devices.routes';
import chatsRoutes from './modules/chats/chats.routes';

import mediaRoutes from './modules/media/media.routes';

export function buildApp(): FastifyInstance {
  const app = fastify({
    logger: logger as any,
    disableRequestLogging: true // Custom clean logging handled manually or in hooks
  });

  // Global plugins
  app.register(cors, {
    origin: '*', // Customize to specific client origins in production
    methods: ['GET', 'POST', 'PUT', 'DELETE']
  });

  app.register(helmet, {
    contentSecurityPolicy: false // Disabled for testing/REST tools if needed
  });

  // Serve static files from local uploads directory
  app.register(fastifyStatic, {
    root: path.resolve(config.uploads.dir),
    prefix: '/uploads/'
  });

  // Register Custom Data-Store / Utility Plugins (ordered by dependency)
  app.register(dbPlugin);
  app.register(redisPlugin);
  app.register(minioPlugin);
  app.register(authPlugin);
  app.register(rateLimitPlugin);
  app.register(socketPlugin);
  app.register(cleanupPlugin);

  // Register API Routes
  app.register(async (apiInstance) => {
    apiInstance.register(authRoutes, { prefix: '/auth' });
    apiInstance.register(usersRoutes, { prefix: '/users' });
    apiInstance.register(invitesRoutes, { prefix: '/invites' });
    apiInstance.register(devicesRoutes, { prefix: '/devices' });
    apiInstance.register(chatsRoutes, { prefix: '/chats' });

    apiInstance.register(mediaRoutes, { prefix: '/media' });
  }, { prefix: '/api' });

  // Health check endpoint
  app.get('/health', async () => {
    return { status: 'healthy', timestamp: new Date().toISOString() };
  });

  // Global Error Handler
  app.setErrorHandler((error, request, reply) => {
    if (error instanceof HttpError) {
      logger.warn(`API HTTP Error: [${error.statusCode}] ${error.message} on ${request.method} ${request.url}`);
      return reply.status(error.statusCode).send({
        error: error.name,
        message: error.message
      });
    }

    if (error.validation) {
      logger.warn(`Validation Error: ${error.message} on ${request.method} ${request.url}`);
      return reply.status(400).send({
        error: 'ValidationError',
        message: error.message,
        details: error.validation
      });
    }

    console.error('Unhandled Server Error', error);
    return reply.status(500).send({
      error: 'InternalServerError',
      message: 'An unexpected error occurred. Please contact the administrator.'
    });
  });

  return app;
}
