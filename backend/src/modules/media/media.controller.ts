import { FastifyReply, FastifyRequest } from 'fastify';
import fs from 'fs';
import path from 'path';
import { MediaService } from './media.service';
import { UploadRequestQuery } from './media.types';
import { UnauthorizedError, BadRequestError } from '../../utils/errors';
import { config } from '../../config';
import sharp from 'sharp';
import * as FileType from 'file-type';

export class MediaController {
  public static async getUploadUrl(
    request: FastifyRequest<{ Querystring: UploadRequestQuery }>,
    reply: FastifyReply
  ) {
    const user = request.user as { userId: string } | undefined;
    if (!user) throw new UnauthorizedError();

    const { filename, mime_type, file_size, encrypted } = request.query;

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
        file_size: Number(file_size),
        encrypted: encrypted === 'true'
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
   * The body arrives as a Buffer thanks to the custom content-type parser.
   */
  public static async uploadFile(
    request: FastifyRequest<{ Params: { uploaderId: string; filename: string }; Querystring: { encrypted?: string } }>,
    reply: FastifyReply
  ) {
    const { uploaderId, filename } = request.params;
    const targetDir = path.resolve(config.uploads.dir, uploaderId);
    const storageKey = `${uploaderId}/${filename}`;

    // Ensure target folder exists
    if (!fs.existsSync(targetDir)) {
      fs.mkdirSync(targetDir, { recursive: true });
    }

    try {
      const fileBuffer = request.body as Buffer;
      const host = request.headers.host || `${config.host}:${config.port}`;
      const isEncrypted = request.query.encrypted === 'true';

      if (isEncrypted) {
        // E2EE encrypted media - save directly without validation or image processing
        const targetPath = path.join(targetDir, filename);
        fs.writeFileSync(targetPath, fileBuffer);
        request.log.info(`Encrypted file uploaded successfully to ${targetPath}`);
        const downloadUrl = `http://${host}/uploads/${storageKey}`;
        return reply.status(200).send({ success: true, path: targetPath, downloadUrl });
      }
      
      // 1. Magic-number validation
      const typeInfo = await FileType.fromBuffer(fileBuffer);
      if (!typeInfo) {
        request.log.warn(`Invalid file format for upload: ${filename}`);
        return reply.status(400).send({ error: 'BadRequest', message: 'Unknown or invalid file format' });
      }

      const isImage = typeInfo.mime.startsWith('image/');
      const baseFilename = filename.split('.').slice(0, -1).join('.') || filename;
      
      if (isImage && typeInfo.mime !== 'image/gif') {
        // 2. Sharp Image Processing
        const targetPath = path.join(targetDir, `${baseFilename}.webp`);
        const thumbPath = path.join(targetDir, `${baseFilename}_thumb.webp`);
        
        // Convert original to WebP
        const webpBuffer = await sharp(fileBuffer).webp({ quality: 85 }).toBuffer();
        fs.writeFileSync(targetPath, webpBuffer);
        
        // Generate Thumbnail
        const thumbBuffer = await sharp(fileBuffer).resize(128, 128).webp({ quality: 70 }).toBuffer();
        fs.writeFileSync(thumbPath, thumbBuffer);
        
        // Update DB with the new storage_key (if extension changed to .webp) and thumbnail_key
        const newStorageKey = `${uploaderId}/${baseFilename}.webp`;
        const thumbStorageKey = `${uploaderId}/${baseFilename}_thumb.webp`;
        
        await request.server.db.query(
          'UPDATE media SET storage_key = $1, thumbnail_key = $2, mime_type = $3 WHERE storage_key = $4',
          [newStorageKey, thumbStorageKey, 'image/webp', storageKey]
        );
        
        request.log.info(`Image processed and uploaded successfully to ${targetPath}`);
        const downloadUrl = `http://${host}/uploads/${newStorageKey}`;
        return reply.status(200).send({ success: true, path: targetPath, downloadUrl });
      } else {
        // Normal file save (Video, Audio, GIF, etc.)
        const targetPath = path.join(targetDir, filename);
        fs.writeFileSync(targetPath, fileBuffer);
        request.log.info(`File uploaded successfully to ${targetPath}`);
        const downloadUrl = `http://${host}/uploads/${storageKey}`;
        return reply.status(200).send({ success: true, path: targetPath, downloadUrl });
      }
    } catch (err: any) {
      request.log.error(`Failed to save uploaded file: ${err.message}`);
      return reply.status(500).send({ error: 'InternalServerError', message: 'Failed to upload file' });
    }
  }
}
