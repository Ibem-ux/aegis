import { MessageType } from '../../types';

export interface SendMessageBody {
  chat_id: string;
  content: string; // Plaintext sent from client (will be server-encrypted in Phase 1 setup)
  message_type?: MessageType;
  reply_to_id?: string;
  media_id?: string;
}

export interface GetMessagesQuery {
  limit?: number;
  before?: string; // Timestamp ISO String
}
