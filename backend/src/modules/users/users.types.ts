export interface UpdateProfileBody {
  display_name?: string;
  full_name?: string;
  avatar_url?: string;
  email?: string;
  phone?: string;
  role?: 'user' | 'admin';
  status?: 'ACTIVE' | 'SUSPENDED' | 'PENDING';
}

export interface UserQueryParams {
  search?: string;
}

export interface ChangePasswordBody {
  current_password?: string;
  new_password?: string;
}

export interface RecoverAccountBody {
  username?: string;
  recovery_key?: string;
  new_password?: string;
}

