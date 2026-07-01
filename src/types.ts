/**
 * Cross-platform type definitions for react-native-mesh-sdk.
 *
 * These types are a faithful, transport-agnostic projection of the public
 * data models shared by both native cores:
 *   - Android: `com.bitchat.android.model.BitchatMessage` / `DeliveryStatus`
 *   - iOS:     `BitFoundation.BitchatMessage` / `DeliveryStatus`
 *
 * They intentionally mirror only the *public* fields the UI layer needs.
 * Anything platform-specific (binary payloads, parcelable flags, etc.) stays
 * inside the native SDK and never crosses the bridge.
 */

/** Mirrors `BitchatMessageType` (Android) / message kind (iOS). */
export enum MeshMessageType {
  Message = 'message',
  Audio = 'audio',
  Image = 'image',
  File = 'file',
}

/** Delivery status kinds — union of Android `DeliveryStatus` sealed class. */
export type DeliveryStatusKind =
  | 'sending'
  | 'sent'
  | 'delivered'
  | 'read'
  | 'failed'
  | 'partiallyDelivered';

/**
 * Delivery status, flattened for the bridge. `kind` discriminates; the other
 * fields are populated depending on the case (matching the native enums).
 */
export interface DeliveryStatus {
  kind: DeliveryStatusKind;
  /** Delivered/Read: peer nickname or id. */
  to?: string;
  by?: string;
  /** Delivered/Read: epoch milliseconds. */
  at?: number;
  /** Failed: reason text. */
  reason?: string;
  /** PartiallyDelivered. */
  reached?: number;
  total?: number;
}

/**
 * A chat message. Field names match the native `BitchatMessage` data class
 * one-to-one so the model is recognizable across all three layers.
 */
export interface MeshMessage {
  id: string;
  sender: string;
  content: string;
  type: MeshMessageType;
  /** Epoch milliseconds. */
  timestamp: number;
  isRelay: boolean;
  originalSender?: string | null;
  isPrivate: boolean;
  recipientNickname?: string | null;
  senderPeerID?: string | null;
  mentions?: string[] | null;
  channel?: string | null;
  isEncrypted: boolean;
  deliveryStatus?: DeliveryStatus | null;
}

/** A snapshot of a known peer, unifying Android `PeerInfo` + iOS `TransportPeerSnapshot`. */
export interface MeshPeer {
  peerID: string;
  nickname: string;
  isConnected: boolean;
  /** Signal strength in dBm, when available (BLE). */
  rssi?: number | null;
  /** Hex-encoded Noise static public key, when a session exists. */
  noisePublicKeyHex?: string | null;
  /** Fingerprint of the peer's identity key, when known. */
  fingerprint?: string | null;
  /** True once an authenticated Noise session is established. */
  isEncrypted: boolean;
  /** Epoch milliseconds of last sighting. */
  lastSeen?: number | null;
}

/** Noise session state, unified across platforms. */
export type NoiseSessionState =
  | 'none'
  | 'handshaking'
  | 'established'
  | 'failed';

/** A file to broadcast/send privately. Mirrors `BitchatFilePacket`. */
export interface MeshFilePacket {
  /** File name including extension. */
  fileName: string;
  /** MIME type, e.g. "image/jpeg". */
  mimeType: string;
  /** Base64-encoded file contents. */
  contentBase64: string;
}

/** Bluetooth adapter state (primarily iOS `CBManagerState`, mapped on Android). */
export type BluetoothState =
  | 'unknown'
  | 'resetting'
  | 'unsupported'
  | 'unauthorized'
  | 'poweredOff'
  | 'poweredOn';

/** Names of the events emitted by the native SDK. */
export interface MeshEventMap {
  /** A public or private message was received. */
  onMessage: MeshMessage;
  /** The list of visible peer IDs changed. */
  onPeerListUpdate: { peers: string[] };
  /** Rich peer snapshots changed (nickname/connection/encryption). */
  onPeerSnapshotsUpdate: { peers: MeshPeer[] };
  /** A peer connected at the transport level (iOS-rich; emitted best-effort on Android). */
  onPeerConnected: { peerID: string };
  onPeerDisconnected: { peerID: string };
  /** Delivery acknowledgement for one of our outgoing messages. */
  onDeliveryAck: { messageID: string; recipientPeerID: string };
  /** Read receipt for one of our outgoing messages. */
  onReadReceipt: { messageID: string; recipientPeerID: string };
  /** Fine-grained delivery status transitions. */
  onDeliveryStatusUpdate: { messageID: string; status: DeliveryStatus };
  /** A peer left a channel. */
  onChannelLeave: { channel: string; fromPeer: string };
  /** Underlying Bluetooth adapter state changed. */
  onBluetoothStateChange: { state: BluetoothState };
}

export type MeshEventName = keyof MeshEventMap;
