import fp from 'fastify-plugin';
import { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import fastifyJwt from '@fastify/jwt';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { config } from '../config';
import { logger } from '../utils/logger';

declare module 'fastify' {
  interface FastifyInstance {
    authenticate: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
}

export default fp(async (fastify: FastifyInstance) => {
  let privateKey: string | Buffer;
  let publicKey: string | Buffer;

  const privateKeyPath = path.resolve(__dirname, '../../', config.security.jwtPrivateKeyPath);
  const publicKeyPath = path.resolve(__dirname, '../../', config.security.jwtPublicKeyPath);

  // Auto-generate keys in development if they don't exist
  if (!fs.existsSync(privateKeyPath) || !fs.existsSync(publicKeyPath)) {
    logger.info('JWT keys not found, generating RSA key pair...');
    try {
      const keysDir = path.dirname(privateKeyPath);
      if (!fs.existsSync(keysDir)) {
        fs.mkdirSync(keysDir, { recursive: true });
      }

      const { privateKey: genPrivKey, publicKey: genPubKey } = crypto.generateKeyPairSync('rsa', {
        modulusLength: 2048,
        publicKeyEncoding: {
          type: 'pkcs1',
          format: 'pem'
        },
        privateKeyEncoding: {
          type: 'pkcs1',
          format: 'pem'
        }
      });

      fs.writeFileSync(privateKeyPath, genPrivKey);
      fs.writeFileSync(publicKeyPath, genPubKey);
      logger.info('RSA key pair generated and saved successfully');

      privateKey = genPrivKey;
      publicKey = genPubKey;
    } catch (err) {
      logger.error('Failed to generate key pair, falling back to HS256 with master key', err);
      // Fallback secret if keygen fails (e.g. environment constraints)
      privateKey = config.security.masterEncryptionKey;
      publicKey = config.security.masterEncryptionKey;
    }
  } else {
    privateKey = fs.readFileSync(privateKeyPath);
    publicKey = fs.readFileSync(publicKeyPath);
  }

  // Register Fastify JWT
  fastify.register(fastifyJwt, {
    secret: {
      private: privateKey,
      public: publicKey
    },
    sign: {
      algorithm: 'RS256',
      expiresIn: '15m' // 15 minutes access token expiry
    }
  });

  // Custom authentication decorator
  fastify.decorate('authenticate', async (request: FastifyRequest, reply: FastifyReply) => {
    try {
      await request.jwtVerify();
    } catch (err) {
      reply.status(401).send({ error: 'Unauthorized', message: 'Invalid or expired token' });
    }
  });
});
