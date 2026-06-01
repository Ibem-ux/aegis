import { FastifyInstance } from 'fastify';
import { UsersController } from './users.controller';

export default async function usersRoutes(fastify: FastifyInstance) {
  // Public routes (Account recovery must be public)
  fastify.post('/recovery/recover', UsersController.recoverAccount);

  // Authenticated routes
  fastify.register(async (authInstance) => {
    authInstance.addHook('preValidation', authInstance.authenticate);

    authInstance.get('/me', UsersController.getMe);
    authInstance.put('/me', UsersController.updateProfile);
    authInstance.get('/search', UsersController.search);
    
    // Retrieve profiles of other users
    authInstance.get('/:id', UsersController.getUserProfile);
    authInstance.put('/:id', UsersController.updateProfile); // Admins can edit others' profiles

    // Password Change & Master Key Configuration
    authInstance.post('/password/change', UsersController.changePassword);
    authInstance.post('/recovery/generate', UsersController.generateRecoveryKey);

    // Active Device Sessions Management
    authInstance.get('/sessions', UsersController.getSessions);
    authInstance.delete('/sessions/:sessionId', UsersController.revokeSession);
  });
}
