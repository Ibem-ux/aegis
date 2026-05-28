export const registerSchema = {
  body: {
    type: 'object',
    required: ['username', 'password', 'invite_code', 'device_name', 'device_fingerprint', 'platform'],
    properties: {
      username: { type: 'string', minLength: 3, maxLength: 50 },
      password: { type: 'string', minLength: 8, maxLength: 100 },
      display_name: { type: 'string', maxLength: 100 },
      invite_code: { type: 'string' },
      device_name: { type: 'string', minLength: 1 },
      device_fingerprint: { type: 'string', minLength: 1 },
      platform: { type: 'string', enum: ['ANDROID', 'IOS', 'DESKTOP'] },
      public_key: { type: 'string' }
    }
  }
};

export const loginSchema = {
  body: {
    type: 'object',
    required: ['username', 'password', 'device_name', 'device_fingerprint', 'platform'],
    properties: {
      username: { type: 'string' },
      password: { type: 'string' },
      device_name: { type: 'string', minLength: 1 },
      device_fingerprint: { type: 'string', minLength: 1 },
      platform: { type: 'string', enum: ['ANDROID', 'IOS', 'DESKTOP'] },
      public_key: { type: 'string' }
    }
  }
};

export const refreshSchema = {
  body: {
    type: 'object',
    required: ['refresh_token'],
    properties: {
      refresh_token: { type: 'string' }
    }
  }
};

export const verifyOtpSchema = {
  body: {
    type: 'object',
    required: ['code'],
    properties: {
      code: { type: 'string', minLength: 6, maxLength: 6 }
    }
  }
};

export const deviceApproveSchema = {
  body: {
    type: 'object',
    required: ['device_id'],
    properties: {
      device_id: { type: 'string', format: 'uuid' }
    }
  }
};
