import { buildApp } from './app';
import { setupSocketServer } from './socket';
import { config } from './config';
import { logger } from './utils/logger';

const server = buildApp();

async function start() {
  try {
    // Wait until plugins are decorated
    await server.ready();
    
    // Set up Socket.IO events and middleware
    setupSocketServer(server);

    // Listen
    await server.listen({
      port: config.port,
      host: config.host
    });

    logger.info(`Server is running at http://${config.host}:${config.port}`);
  } catch (err) {
    logger.error('Failed to start server', err);
    process.exit(1);
  }
}

// Handle termination signals gracefully
const signals = ['SIGINT', 'SIGTERM'];
signals.forEach((signal) => {
  process.on(signal, async () => {
    logger.info(`Received ${signal}, starting graceful shutdown...`);
    try {
      await server.close();
      logger.info('Server successfully closed.');
      process.exit(0);
    } catch (err) {
      logger.error('Error during graceful shutdown', err);
      process.exit(1);
    }
  });
});

start();
