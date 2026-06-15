export type MessageType = "TEXT" | "IMAGE" | "VIDEO" | "AUDIO" | "RECORDING";

export interface WrappedKey {
  key: string;
  iv: string;
}

export interface EncryptedEnvelope {
  messageId: string;
  chatId: string;
  senderDeviceId: string;
  type: MessageType;
  ciphertext: string;
  iv: string;
  keys: Record<string, WrappedKey>;
  sentAt: string;
}
