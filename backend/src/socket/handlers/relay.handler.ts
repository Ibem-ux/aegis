import { Server } from 'socket.io';
import { AuthenticatedSocket } from '../middleware/auth.middleware';
import { FastifyInstance } from 'fastify';
import { EncryptedEnvelope, WrappedKey } from '../../shared/envelope';
import { RelayService } from '../../modules/relay/relay.service';
import { MessagesService } from '../../modules/messages/messages.service';
import { config } from '../../config';
import { logger } from '../../utils/logger';

const VALID_MESSAGE_TYPES = new Set<string>(['TEXT', 'IMAGE', 'VIDEO', 'AUDIO', 'RECORDING']);

export const presenceRegistry: Map<string, Set<string>> = new Map();

export const registerRelayHandlers = async (
  io: Server,
  socket: AuthenticatedSocket,
  fastify: FastifyInstance
): Promise<void> => {
  const { deviceId } = socket.data.user;

  if (!presenceRegistry.has(deviceId)) {
    presenceRegistry.set(deviceId, new Set());
  }
  presenceRegistry.get(deviceId)!.add(socket.id);

  socket.on('disconnect', () => {
    const deviceSockets = presenceRegistry.get(deviceId);
    if (deviceSockets) {
      deviceSockets.delete(socket.id);
      if (deviceSockets.size === 0) {
        presenceRegistry.delete(deviceId);
      }
    }
  });

  const enqueueOfflineEnvelope = async (envelope: EncryptedEnvelope, recipientDeviceId: string): Promise<void> => {
    await RelayService.enqueue(fastify.db, envelope, recipientDeviceId, config.relay.offlineQueueTTL);
  };

  socket.on('message:send', async (payload: unknown) => {
    if (
      !payload ||
      typeof payload !== 'object' ||
      !('messageId' in payload) ||
      !('chatId' in payload) ||
      !('senderDeviceId' in payload) ||
      !('type' in payload) ||
      !('ciphertext' in payload) ||
      !('iv' in payload) ||
      !('keys' in payload) ||
      !('sentAt' in payload)
    ) {
      logger.warn('Malformed message:send payload', { payload });
      return;
    }

    const envelope = payload as EncryptedEnvelope;

    if (
      typeof envelope.messageId !== 'string' ||
      typeof envelope.chatId !== 'string' ||
      typeof envelope.senderDeviceId !== 'string' ||
      typeof envelope.ciphertext !== 'string' ||
      typeof envelope.iv !== 'string' ||
      typeof envelope.sentAt !== 'string'
    ) {
      logger.warn('Invalid field types in envelope', { messageId: envelope.messageId });
      return;
    }

    if (!VALID_MESSAGE_TYPES.has(envelope.type)) {
      logger.warn('Invalid MessageType in envelope', { type: envelope.type });
      return;
    }

    if (typeof envelope.keys !== 'object' || envelope.keys === null) {
      logger.warn('Invalid keys in envelope', { messageId: envelope.messageId });
      return;
    }

    const keys = envelope.keys as Record<string, WrappedKey>;

    for (const [recipientDeviceId, wrappedKey] of Object.entries(keys)) {
      if (typeof recipientDeviceId !== 'string') {
        logger.warn('Invalid recipientDeviceId type in keys', { messageId: envelope.messageId });
        continue;
      }

      const wk = wrappedKey as WrappedKey;
      if (typeof wk.key !== 'string' || typeof wk.iv !== 'string') {
        logger.warn('Invalid WrappedKey in envelope', { messageId: envelope.messageId, recipientDeviceId });
        continue;
      }

      const isOnline = presenceRegistry.has(recipientDeviceId) && presenceRegistry.get(recipientDeviceId)!.size > 0;

      if (isOnline) {
        const deviceSockets = presenceRegistry.get(recipientDeviceId)!;
        for (const socketId of deviceSockets) {
          io.to(socketId).emit('message:deliver', envelope);
        }
      } else {
        await enqueueOfflineEnvelope(envelope, recipientDeviceId);
      }
    }
  });

  socket.on('message:ack', async (payload: unknown) => {
    if (
      !payload ||
      typeof payload !== 'object' ||
      !('messageId' in payload) ||
      !('recipientDeviceId' in payload)
    ) {
      logger.warn('Malformed message:ack payload', { payload });
      return;
    }

    const { messageId, recipientDeviceId } = payload as { messageId: string; recipientDeviceId: string };

    logger.info(`Received ACK for message ${messageId} from device ${recipientDeviceId}`);
    
    try {
      await MessagesService.updateMessageStatus(fastify.db, messageId, recipientDeviceId, 'DELIVERED');
    } catch (err) {
      logger.error(`Failed to update message status to DELIVERED for message ${messageId}`, err);
    }
    
    await RelayService.remove(fastify.db, messageId, recipientDeviceId);
  });
};

export const flushQueueForDevice = async (io: Server, fastify: FastifyInstance, deviceId: string, socketId: string): Promise<void> => {
  try {
    const queued = await RelayService.listForDevice(fastify.db, deviceId);
    logger.info(`Flushing ${queued.length} queued envelopes for device ${deviceId}`);
    for (const envelope of queued) {
      io.to(socketId).emit('message:deliver', envelope);
    }
  } catch (err) {
    logger.error(`Failed to flush offline queue for device ${deviceId}`, err);
  }
};
