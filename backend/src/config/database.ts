import { PoolConfig } from 'pg';
import { config } from './index';

export const dbConfig: PoolConfig = {
  connectionString: config.database.url,
  max: 20, // Maximum pool size
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
};
