import { Pool } from 'pg';
import { v4 as uuidv4 } from 'uuid';
import { Media } from '../../types';
import { NotFoundError } from '../../utils/errors';

export class MediaService {
  /**
   * Generates a local URL to upload files directly to this backend.
   */
  public static async generateUploadUrl(
    host: string,
    db: Pool,
    uploaderId: string,
    payload: { filename: string; mime_type: string; file_size: number }
  ): Promise<{ uploadUrl: string; mediaId: string }> {
    const fileId = uuidv4();
    const extension = payload.filename.split('.').pop();
    const storageKey = `${uploaderId}/${fileId}${extension ? `.${extension}` : ''}`;

    // Construct local PUT endpoint URL
    const uploadUrl = `http://${host}/api/v1/media/upload-file/${storageKey}`;

    // Save media metadata in DB
    const res = await db.query<Media>(
      `INSERT INTO media (id, uploader_id, storage_key, mime_type, file_size)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [fileId, uploaderId, storageKey, payload.mime_type, payload.file_size]
    );

    return {
      uploadUrl,
      mediaId: res.rows[0].id
    };
  }

  /**
   * Generates a local URL served by @fastify/static.
   */
  public static async generateDownloadUrl(
    host: string,
    db: Pool,
    mediaId: string,
    userId: string
  ): Promise<{ downloadUrl: string; media: Media }> {
    // Fetch media details
    const res = await db.query<Media>('SELECT * FROM media WHERE id = $1', [mediaId]);
    const media = res.rows[0];

    if (!media) {
      throw new NotFoundError('Media file not found');
    }

    // Serve via @fastify/static mount point
    const downloadUrl = `http://${host}/uploads/${media.storage_key}`;

    return {
      downloadUrl,
      media
    };
  }
}
