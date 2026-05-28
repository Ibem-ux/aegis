import { DevicePlatform } from '../../types';

export interface RegisterBody {
  username: string;
  password?: string; // Optional if we do passwordless, but required by default
  display_name?: string;
  invite_code: string;
  device_name: string;
  device_fingerprint: string;
  platform: DevicePlatform;
  public_key?: string;
}

export interface LoginBody {
  username: string;
  password?: string;
  device_name: string;
  device_fingerprint: string;
  platform: DevicePlatform;
  public_key?: string;
}

export interface RefreshBody {
  refresh_token: string;
}

export interface VerifyOtpBody {
  code: string;
}

export interface DeviceApproveBody {
  device_id: string;
}
