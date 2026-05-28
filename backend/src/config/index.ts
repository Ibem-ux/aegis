import dotenv from 'dotenv';
import path from 'path';

// Load environment variables from .env file
dotenv.config({ path: path.resolve(__dirname, '../../.env') });

export const config = {
  env: process.env.NODE_ENV || 'development',
  port: parseInt(process.env.PORT || '3000', 10),
  host: process.env.HOST || '0.0.0.0',

  database: {
    url: process.env.DATABASE_URL || 'postgresql://ibemuser:ibempass@localhost:5432/ibemdb',
  },

  redis: {
    url: process.env.REDIS_URL || 'redis://localhost:6379',
  },

  minio: {
    endpoint: process.env.MINIO_ENDPOINT || 'localhost',
    port: parseInt(process.env.MINIO_PORT || '9000', 10),
    useSSL: process.env.MINIO_USE_SSL === 'true',
    accessKey: process.env.MINIO_ACCESS_KEY || 'minioadmin',
    secretKey: process.env.MINIO_SECRET_KEY || 'minioadmin',
    bucketName: process.env.MINIO_BUCKET_NAME || 'ibemcom-media',
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
