import fp from 'fastify-plugin';
import { FastifyInstance } from 'fastify';
import { ChatsService } from '../modules/chats/chats.service';
import { logger } from '../utils/logger';

export default fp(async (fastify: FastifyInstance) => {
  // Run cleanup every 6 hours
  const CLEANUP_INTERVAL_MS = 6 * 60 * 60 * 1000;
  let timer: ReturnType<typeof setInterval> | null = null;
  let startupTimer: ReturnType<typeof setTimeout> | null = null;

  const runCleanup = async () => {
    try {
      logger.info('Running background cleanup for stale invite links...');
      const deletedCount = await ChatsService.cleanupStaleInviteLinks(fastify.db);
      if (deletedCount > 0) {
        logger.info(`Cleanup complete: deleted ${deletedCount} stale invite link(s).`);
      } else {
        logger.info('Cleanup complete: no stale invite links found.');
      }
    } catch (error) {
      logger.error('Failed to cleanup stale invite links', error);
    }
  };

  // Register onClose hook during plugin init (before server starts listening)
  fastify.addHook('onClose', async () => {
    if (timer) clearInterval(timer);
    if (startupTimer) clearTimeout(startupTimer);
  });

  // Schedule the timers after the server is ready
  fastify.ready(() => {
    timer = setInterval(runCleanup, CLEANUP_INTERVAL_MS);
    // Initial run 5 minutes after startup
    startupTimer = setTimeout(runCleanup, 5 * 60 * 1000);
  });
});
