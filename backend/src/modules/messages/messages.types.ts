import { MessageType } from '../../shared/envelope';

export interface SendMessageBody {
  chat_id: string;
  content: string;
  message_type?: MessageType;
  reply_to_id?: string;
  media_id?: string;
}

export interface GetMessagesQuery {
  limit?: number;
  before?: string;
}
