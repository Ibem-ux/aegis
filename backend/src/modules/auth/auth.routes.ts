import { FastifyInstance } from 'fastify';
import { AuthController } from './auth.controller';
import { 
  registerSchema, 
  loginSchema, 
  refreshSchema, 
  verifyOtpSchema,
  verifyEmailOtpSchema
} from './auth.schema';

export default async function authRoutes(fastify: FastifyInstance) {
  // Public Routes
  fastify.post('/register', { schema: registerSchema }, AuthController.register);
  fastify.post('/login', { schema: loginSchema }, AuthController.login);
  fastify.post('/refresh', { schema: refreshSchema }, AuthController.refresh);
  fastify.post('/otp/send', AuthController.sendOtp);
  fastify.post('/otp/verify', { schema: verifyEmailOtpSchema }, AuthController.verifyOtp);

  // TEMPORARY: Debug endpoint for testing credential validation
  fastify.post('/debug-login', AuthController.debugLogin);

  // Temporary debug endpoint for E2EE status
  fastify.get('/debug/e2ee-status', { preHandler: [fastify.authenticate] }, AuthController.e2eeDebugStatus);

  // Authenticated Routes
  fastify.register(async (authenticatedInstance) => {
    // Add preValidation hook to enforce JWT authentication
    authenticatedInstance.addHook('preValidation', authenticatedInstance.authenticate);

    authenticatedInstance.post('/logout', AuthController.logout);
    authenticatedInstance.post('/2fa/setup', AuthController.setup2FA);
    authenticatedInstance.post('/2fa/verify', { schema: verifyOtpSchema }, AuthController.verify2FA);
  });
}
