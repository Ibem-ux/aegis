# Aegis Thin-Relay — Encrypted Envelope & Socket Event Contract

## 1. Encrypted Message Envelope

This document is the **single source of truth** for the encrypted message
envelope exchanged between the Aegis mobile client (Flutter/Dart) and the
thin-relay backend (Fastify/TypeScript).  Both sides MUST serialize this
contract identically so that the relay can remain zero-knowledge.

### 1.1 Wire format

- JSON keys: **camelCase**
- `MessageType` serializes to **UPPERCASE strings**

### 1.2 Types

```typescript
// backend/src/shared/envelope.ts  (TypeScript)

export type MessageType = "TEXT" | "IMAGE" | "VIDEO" | "AUDIO" | "RECORDING";

export interface WrappedKey {
  key: string; // base64(encrypted K_msg + MAC)
  iv: string;  // base64(key IV)
}

export interface EncryptedEnvelope {
  messageId: string;        // client-generated UUID — idempotency + ACK key
  chatId: string;
  senderDeviceId: string;   // UUID
  type: MessageType;
  ciphertext: string;       // base64(ciphertext + GCM tag)
  iv: string;               // base64(body IV)
  keys: Record<string, WrappedKey>; // recipientDeviceId -> wrapped K_msg
  sentAt: string;           // ISO-8601 (client clock)
}
```

```dart
// frontend/lib/core/network/envelope.dart  (Dart)

enum MessageType { text, image, video, audio, recording }

class WrappedKey {
  final String key; // base64(encrypted K_msg + MAC)
  final String iv;  // base64(key IV)

  const WrappedKey({required this.key, required this.iv});

  factory WrappedKey.fromJson(Map<String, dynamic> json) => WrappedKey(
        key: json['key'] as String,
        iv: json['iv'] as String,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'iv': iv,
      };
}

class EncryptedEnvelope {
  final String messageId;        // client-generated UUID
  final String chatId;
  final String senderDeviceId;   // UUID
  final MessageType type;
  final String ciphertext;       // base64(ciphertext + GCM tag)
  final String iv;               // base64(body IV)
  final Map<String, WrappedKey> keys; // recipientDeviceId -> wrapped K_msg
  final String sentAt;           // ISO-8601 (client clock)

  const EncryptedEnvelope({
    required this.messageId,
    required this.chatId,
    required this.senderDeviceId,
    required this.type,
    required this.ciphertext,
    required this.iv,
    required this.keys,
    required this.sentAt,
  });

  factory EncryptedEnvelope.fromJson(Map<String, dynamic> json) =>
      EncryptedEnvelope(
        messageId: json['messageId'] as String,
        chatId: json['chatId'] as String,
        senderDeviceId: json['senderDeviceId'] as String,
        type: MessageType.values.firstWhere(
          (e) => e.name.toUpperCase() == (json['type'] as String),
          orElse: () => throw FormatException(
            'Unknown MessageType: ${json['type']}',
          ),
        ),
        ciphertext: json['ciphertext'] as String,
        iv: json['iv'] as String,
        keys: (json['keys'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, WrappedKey.fromJson(v as Map<String, dynamic>)),
        ),
        sentAt: json['sentAt'] as String,
      );

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'chatId': chatId,
        'senderDeviceId': senderDeviceId,
        'type': type.name.toUpperCase(),
        'ciphertext': ciphertext,
        'iv': iv,
        'keys': keys.map(
          (k, v) => MapEntry(k, v.toJson()),
        ),
        'sentAt': sentAt,
      };
}
```

### 1.3 Field dictionary

| Field | Type | Encoding / Format | Meaning |
|---|---|---|---|
| `messageId` | `string` | UUID v4 (client-generated) | Unique envelope identifier; used for idempotency and ACK correlation. |
| `chatId` | `string` | UUID | The chat / conversation this message belongs to. |
| `senderDeviceId` | `string` | UUID | The device that originated the message. |
| `type` | `MessageType` | UPPERCASE string (`TEXT`, `IMAGE`, `VIDEO`, `AUDIO`, `RECORDING`) | High-level payload category so the relay can apply tiered retention / routing rules without inspecting ciphertext. |
| `ciphertext` | `string` | base64( ciphertext \|\| GCM tag ) | The AES-GCM encrypted message body. The GCM authentication tag is appended to the ciphertext before base64 encoding. |
| `iv` | `string` | base64 | The 12-byte GCM initialization vector for the body. |
| `keys` | `Record<string, WrappedKey>` | JSON object keyed by `recipientDeviceId` | For each intended recipient device, a per-recipient wrapped copy of the ephemeral message key `K_msg`. The relay uses this map only to determine *where* to deliver; it cannot unwrap the key. |
| `keys[key].key` | `string` | base64( encrypted K_msg + MAC ) | The recipient-specific encryption of the 32-byte ephemeral message key, plus its authentication tag. |
| `keys[key].iv` | `string` | base64 | The IV used to encrypt the ephemeral message key for this recipient. |
| `sentAt` | `string` | ISO-8601 | Client-side timestamp (UTC) of when the envelope was assembled. Used for ordering and staleness checks. |

---

## 2. Socket.IO Event Contract

All events travel over a **single Socket.IO namespace** (default `/`).
No HTTP REST endpoints are used for real-time messaging.

| Event | Direction | Payload | Purpose |
|---|---|---|---|
| `message:send` | client → server | `EncryptedEnvelope` | Sender submits an envelope for recipient device(s). |
| `message:deliver` | server → client | `EncryptedEnvelope` | Relay pushes an envelope to an online recipient device. |
| `message:ack` | client → server | `{ messageId, recipientDeviceId }` | Recipient confirms local storage → server drops relay copy. |

### 2.1 Event: `message:send`

**Who sends:** The sending mobile client.  
**When:** User has tapped "Send"; the envelope has already been assembled and
encrypted client-side.  
**Payload:** A fully-formed `EncryptedEnvelope`.  
**Server behavior:** Validate auth context, verify `senderDeviceId` matches the
authenticated socket, persist the envelope keyed by `messageId`, and fan-out
to all online recipient sockets listed in `keys`.

### 2.2 Event: `message:deliver`

**Who sends:** The backend relay.  
**When:** An envelope exists whose `keys` map contains the recipient's
`deviceId` and that device is currently connected.  
**Payload:** The same `EncryptedEnvelope` object originally received via
`message:send`.  
**Client behavior:** Decrypt `K_msg` (using the entry in `keys[thisDeviceId]`),
then decrypt the `ciphertext`, and persist to local database. Emit
`message:ack` once storage is confirmed.

### 2.3 Event: `message:ack`

**Who sends:** The receiving mobile client.  
**When:** After the envelope has been durably stored on the device.  
**Payload:** A minimal acknowledgement object:

```json
{
  "messageId": "<UUID>",
  "recipientDeviceId": "<UUID>"
}
```

**Server behavior:** Mark the `(messageId, recipientDeviceId)` pair as
acknowledged. Once all intended recipients have ACK'd (or the message has
expired), the server removes its relay copy of the envelope.
