import { Pool } from 'pg';
import { Client } from 'minio';
import { v4 as uuidv4 } from 'uuid';
import { Media } from '../../types';
import { config } from '../../config';
import { NotFoundError } from '../../utils/errors';

export class MediaService {
  /**
   * Generates a pre-signed URL to upload files directly to MinIO.
   */
  public static async generateUploadUrl(
    minio: Client,
    db: Pool,
    uploaderId: string,
    payload: { filename: string; mime_type: string; file_size: number }
  ): Promise<{ uploadUrl: string; mediaId: string }> {
    const fileId = uuidv4();
    const extension = payload.filename.split('.').pop();
    const storageKey = `${uploaderId}/${fileId}${extension ? `.${extension}` : ''}`;

    // Generate pre-signed PUT url (expires in 15 minutes)
    const uploadUrl = await minio.presignedPutObject(
      config.minio.bucketName,
      storageKey,
      15 * 60
    );

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
   * Generates a pre-signed URL to download/stream files from MinIO.
   */
  public static async generateDownloadUrl(
    minio: Client,
    db: Pool,
    mediaId: string,
    userId: string
  ): Promise<{ downloadUrl: string; media: Media }> {
    // 1. Fetch media details
    const res = await db.query<Media>('SELECT * FROM media WHERE id = $1', [mediaId]);
    const media = res.rows[0];

    if (!media) {
      throw new NotFoundError('Media file not found');
    }

    // 2. Generate pre-signed GET URL (expires in 1 hour)
    const downloadUrl = await minio.presignedGetObject(
      config.minio.bucketName,
      media.storage_key,
      60 * 60
    );

    return {
      downloadUrl,
      media
    };
  }
}
