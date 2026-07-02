import { NativeModules, Platform } from 'react-native';

/**
 * Raw native module contract — the thin JSI/bridge surface implemented by:
 *   - Android: `com.meshsdk.MeshSdkModule` (wraps `UnifiedMeshService`)
 *   - iOS:     `MeshSdk` (wraps `BLEService` / `Transport`)
 *
 * Everything here is intentionally primitive (strings, numbers, JSON-able
 * objects) so it survives the bridge unchanged on both old and new RN
 * architectures. The ergonomic, typed API lives in `MeshSdk.ts`.
 *
 * All methods that return data are async (Promise) to stay TurboModule-ready.
 */
export interface Spec {
  // Mesh identity — override the BLE service/characteristic UUIDs (call before startServices)
  setMeshId(serviceUUID: string, characteristicUUID: string): Promise<void>;

  // Lifecycle
  startServices(): Promise<void>;
  stopServices(): Promise<void>;
  emergencyDisconnectAll(): Promise<void>;

  // Bluetooth adapter
  getBluetoothState(): Promise<string>;
  enableBluetooth(): Promise<boolean>;

  // Local notifications
  setNotificationsEnabled(enabled: boolean): Promise<void>;
  setPublicNotificationsEnabled(enabled: boolean): Promise<void>;
  setActiveChatPeer(peerID: string | null): Promise<void>;

  // Identity
  getMyPeerID(): Promise<string>;
  setNickname(nickname: string): Promise<void>;
  getNickname(): Promise<string>;
  getIdentityFingerprint(): Promise<string>;
  getStaticNoisePublicKeyHex(): Promise<string | null>;

  // Messaging
  sendMessage(content: string, mentions: string[], channel: string | null): Promise<void>;
  sendPrivateMessage(
    content: string,
    recipientPeerID: string,
    recipientNickname: string,
    messageID: string | null
  ): Promise<string>;
  sendReadReceipt(messageID: string, recipientPeerID: string, readerNickname: string): Promise<void>;
  sendDeliveryAck(messageID: string, recipientPeerID: string): Promise<void>;
  sendBroadcastAnnounce(): Promise<void>;
  sendAnnouncementToPeer(peerID: string): Promise<void>;
  sendFavoriteNotification(peerID: string, isFavorite: boolean): Promise<void>;

  // Files (base64 payloads)
  sendFileBroadcast(fileName: string, mimeType: string, contentBase64: string): Promise<string>;
  sendFilePrivate(
    recipientPeerID: string,
    fileName: string,
    mimeType: string,
    contentBase64: string
  ): Promise<string>;
  cancelFileTransfer(transferId: string): Promise<boolean>;

  // Peers
  getPeerNicknames(): Promise<{ [peerID: string]: string }>;
  getPeerRSSI(): Promise<{ [peerID: string]: number }>;
  getActivePeerCount(): Promise<number>;
  getPeerSnapshots(): Promise<object[]>;
  getPeerFingerprint(peerID: string): Promise<string | null>;
  isPeerConnected(peerID: string): Promise<boolean>;

  // Noise / encryption
  hasEstablishedSession(peerID: string): Promise<boolean>;
  getSessionState(peerID: string): Promise<string>;
  initiateNoiseHandshake(peerID: string): Promise<void>;
  shouldShowEncryptionIcon(peerID: string): Promise<boolean>;
  getEncryptedPeers(): Promise<string[]>;

  // QR verification
  sendVerifyChallenge(peerID: string, noiseKeyHex: string, nonceABase64: string): Promise<void>;
  sendVerifyResponse(peerID: string, noiseKeyHex: string, nonceABase64: string): Promise<void>;

  // Diagnostics / data
  getDebugStatus(): Promise<string>;
  clearAllInternalData(): Promise<void>;
  clearAllEncryptionData(): Promise<void>;

  // Required for NativeEventEmitter on iOS (no-ops, but must exist)
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

const LINKING_ERROR =
  `The package 'react-native-mesh-sdk' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo Go (this library uses native code)\n';

const MeshSdkNative: Spec = NativeModules.MeshSdk
  ? NativeModules.MeshSdk
  : new Proxy(
      {},
      {
        get() {
          throw new Error(LINKING_ERROR);
        },
      }
    );

export default MeshSdkNative;
