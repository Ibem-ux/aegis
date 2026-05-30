export interface CreateChatBody {
  recipient_id: string;
}

export interface CreateInviteLinkBody {
  max_uses?: number | null;
  expires_at?: string; // ISO timestamp
  label?: string;
}

export interface AcceptInviteBody {
  token: string;
}
