export type UserStatus = 'ACTIVE' | 'SUSPENDED' | 'PENDING';
export type DevicePlatform = 'ANDROID' | 'IOS' | 'DESKTOP' | 'WEB';
export type MessageDeliveryStatus = 'SENT' | 'DELIVERED';
export type KeyPurpose = 'DB_MESSAGE' | 'MEDIA_DECRYPTION' | 'BACKUP';
export type BackupStatus = 'STARTED' | 'COMPLETED' | 'FAILED';
export type Role = 'user' | 'admin' | 'super_user' | 'owner';

export interface User {
  id: string;
  username: string;
  display_name: string | null;
  full_name: string | null;
  avatar_url: string | null;
  email: string | null;
  phone: string | null;
  password_hash: string;
  totp_secret: string | null;
  totp_enabled: boolean;
  status: UserStatus;
  role: Role;
  recovery_key_hash: string | null;
  password_updated_at: Date;
  last_seen: Date;
  created_at: Date;
  updated_at: Date;
}

export interface Device {
  id: string;
  user_id: string;
  device_name: string;
  device_fingerprint: string;
  public_key: string | null;
  platform: DevicePlatform;
  push_token: string | null;
  is_trusted: boolean;
  trusted_at: Date | null;
  trusted_by_device_id: string | null;
  last_active: Date;
  created_at: Date;
}

export interface Session {
  id: string;
  user_id: string;
  device_id: string;
  refresh_token_hash: string;
  ip_address: string | null;
  user_agent: string | null;
  expires_at: Date;
  revoked_at: Date | null;
  created_at: Date;
}

export interface Invite {
  id: string;
  code: string;
  created_by: string | null;
  claimed_by: string | null;
  max_uses: number;
  use_count: number;
  expires_at: Date | null;
  created_at: Date;
}

export interface Chat {
  id: string;
  created_at: Date;
  updated_at: Date;
  last_message_at: Date;
}

export interface ChatParticipant {
  chat_id: string;
  user_id: string;
  joined_at: Date;
  muted_until: Date | null;
  archived: boolean;
}

export interface Media {
  id: string;
  uploader_id: string | null;
  storage_key: string;
  encrypted_key: Buffer | null;
  key_iv: Buffer | null;
  mime_type: string;
  file_size: number;
  thumbnail_key: string | null;
  checksum: string | null;
  created_at: Date;
}

export interface EncryptionKey {
  id: string;
  key_purpose: KeyPurpose;
  encrypted_key: Buffer;
  key_version: number;
  is_active: boolean;
  created_at: Date;
  rotated_at: Date | null;
}

export interface LoginAttempt {
  id: string;
  user_identifier: string;
  ip_address: string;
  success: boolean;
  failure_reason: string | null;
  device_fingerprint: string | null;
  attempted_at: Date;
}

export interface Backup {
  id: string;
  backup_type: string;
  file_path: string;
  file_size: number;
  checksum: string | null;
  encrypted: boolean;
  status: BackupStatus;
  started_at: Date;
  completed_at: Date | null;
  created_by: string | null;
}
