export interface UploadRequestQuery {
  filename: string;
  mime_type: string;
  file_size: number;
  encrypted?: string;
}
