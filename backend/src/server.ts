import { buildApp } from './app';
import { setupSocketServer } from './socket';
import { config } from './config';
import { logger } from './utils/logger';
import { EmailService } from './services/email.service';

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

    // Verify SMTP connection (non-blocking — warn on failure, don't crash)
    EmailService.verify().then(ok => {
      if (ok) {
        logger.info('✅ SMTP connection verified — email delivery is active');
      } else {
        logger.warn('⚠️ SMTP verification failed — OTP emails will not be delivered (check SMTP_HOST/SMTP_USER/SMTP_PASS in .env)');
      }
    });
  } catch (err) {
    logger.error(err, 'Failed to start server');
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
