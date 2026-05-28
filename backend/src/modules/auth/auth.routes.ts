import { FastifyInstance } from 'fastify';
import { AuthController } from './auth.controller';
import { 
  registerSchema, 
  loginSchema, 
  refreshSchema, 
  verifyOtpSchema 
} from './auth.schema';

export default async function authRoutes(fastify: FastifyInstance) {
  // Public Routes
  fastify.post('/register', { schema: registerSchema }, AuthController.register);
  fastify.post('/login', { schema: loginSchema }, AuthController.login);
  fastify.post('/refresh', { schema: refreshSchema }, AuthController.refresh);

  // Authenticated Routes
  fastify.register(async (authenticatedInstance) => {
    // Add preValidation hook to enforce JWT authentication
    authenticatedInstance.addHook('preValidation', authenticatedInstance.authenticate);

    authenticatedInstance.post('/logout', AuthController.logout);
    authenticatedInstance.post('/2fa/setup', AuthController.setup2FA);
    authenticatedInstance.post('/2fa/verify', { schema: verifyOtpSchema }, AuthController.verify2FA);
  });
}
