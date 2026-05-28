import { Socket } from 'socket.io';
import { FastifyInstance } from 'fastify';
import { TokenPayload } from '../../services/token.service';

export interface AuthenticatedSocket extends Socket {
  data: {
    user: TokenPayload;
  };
}

export const socketAuthMiddleware = (fastify: FastifyInstance) => {
  return (socket: Socket, next: (err?: Error) => void) => {
    // Retrieve token from handshake auth or query parameter
    const token = socket.handshake.auth?.token || socket.handshake.query?.token;

    if (!token || typeof token !== 'string') {
      return next(new Error('Authentication error: Token missing'));
    }

    try {
      // Decode and verify token using Fastify JWT instance
      const decoded = fastify.jwt.verify<TokenPayload>(token);
      
      // Store user data in socket session
      socket.data = {
        ...socket.data,
        user: decoded
      };

      next();
    } catch (err) {
      return next(new Error('Authentication error: Invalid or expired token'));
    }
  };
};
