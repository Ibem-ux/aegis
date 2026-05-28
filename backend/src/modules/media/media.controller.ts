import { FastifyReply, FastifyRequest } from 'fastify';
import fs from 'fs';
import path from 'path';
import { pipeline } from 'stream/promises';
import { MediaService } from './media.service';
import { UploadRequestQuery } from './media.types';
import { UnauthorizedError, BadRequestError } from '../../utils/errors';
import { config } from '../../config';

export class MediaController {
  public static async getUploadUrl(
    request: FastifyRequest<{ Querystring: UploadRequestQuery }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const { filename, mime_type, file_size } = request.query;

    if (!filename || !mime_type || !file_size) {
      throw new BadRequestError('Missing query parameters (filename, mime_type, file_size)');
    }

    // Determine host dynamically from request headers
    const host = request.headers.host || `${config.host}:${config.port}`;

    const uploadDetails = await MediaService.generateUploadUrl(
      host,
      request.server.db,
      user.userId,
      {
        filename,
        mime_type,
        file_size: Number(file_size)
      }
    );

    return reply.status(200).send(uploadDetails);
  }

  public static async getDownloadUrl(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const mediaId = request.params.id;
    
    // Determine host dynamically from request headers
    const host = request.headers.host || `${config.host}:${config.port}`;

    const downloadDetails = await MediaService.generateDownloadUrl(
      host,
      request.server.db,
      mediaId,
      user.userId
    );

    return reply.status(200).send({
      downloadUrl: downloadDetails.downloadUrl,
      mime_type: downloadDetails.media.mime_type,
      file_size: downloadDetails.media.file_size
    });
  }

  /**
   * Endpoint to receive raw file upload body and save it to the local uploads directory.
   */
  public static async uploadFile(
    request: FastifyRequest<{ Params: { uploaderId: string; filename: string } }>,
    reply: FastifyReply
  ) {
    const { uploaderId, filename } = request.params;
    const targetDir = path.resolve(config.uploads.dir, uploaderId);

    // Ensure target folder exists
    if (!fs.existsSync(targetDir)) {
      fs.mkdirSync(targetDir, { recursive: true });
    }

    const targetPath = path.join(targetDir, filename);
    const writeStream = fs.createWriteStream(targetPath);

    try {
      await pipeline(request.raw, writeStream);
      request.log.info(`File uploaded successfully to ${targetPath}`);
      return reply.status(200).send({ success: true, path: targetPath });
    } catch (err: any) {
      request.log.error(`Failed to save uploaded file: ${err.message}`);
      return reply.status(500).send({ error: 'InternalServerError', message: 'Failed to upload file' });
    }
  }
}
