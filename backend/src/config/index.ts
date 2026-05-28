import dotenv from 'dotenv';
import path from 'path';

// Load environment variables from .env file
dotenv.config({ path: path.resolve(__dirname, '../../.env') });

export const config = {
  env: process.env.NODE_ENV || 'development',
  port: parseInt(process.env.PORT || '3000', 10),
  host: process.env.HOST || '0.0.0.0',

  database: {
    path: process.env.DATABASE_PATH || 'data/database.sqlite',
  },

  uploads: {
    dir: process.env.UPLOAD_DIR || 'uploads',
  },

  security: {
    jwtPrivateKeyPath: process.env.JWT_PRIVATE_KEY_PATH || 'keys/private.pem',
    jwtPublicKeyPath: process.env.JWT_PUBLIC_KEY_PATH || 'keys/public.pem',
    masterEncryptionKey: process.env.MASTER_ENCRYPTION_KEY || '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
    backupEncryptionKey: process.env.BACKUP_ENCRYPTION_KEY || '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
  }
};

// Simple sanity validation checks
if (config.security.masterEncryptionKey.length !== 64) {
  throw new Error('MASTER_ENCRYPTION_KEY must be a 64-character hex string (32 bytes)');
}

if (config.security.backupEncryptionKey.length !== 64) {
  throw new Error('BACKUP_ENCRYPTION_KEY must be a 64-character hex string (32 bytes)');
}
