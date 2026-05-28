import { FastifyReply, FastifyRequest } from 'fastify';
import { MediaService } from './media.service';
import { UploadRequestQuery } from './media.types';
import { UnauthorizedError, BadRequestError } from '../../utils/errors';

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

    const uploadDetails = await MediaService.generateUploadUrl(
      request.server.minio,
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
    const downloadDetails = await MediaService.generateDownloadUrl(
      request.server.minio,
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
}
