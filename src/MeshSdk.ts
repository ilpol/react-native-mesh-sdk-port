import { NativeEventEmitter, NativeModules, EmitterSubscription } from 'react-native';
import Native from './NativeMeshSdk';
import type {
  MeshEventMap,
  MeshEventName,
  MeshMessage,
  MeshPeer,
  MeshFilePacket,
  NoiseSessionState,
} from './types';

/**
 * High-level, ergonomic facade over the native mesh transport.
 *
 * This is the *only* class app code should touch. It owns:
 *   - a single `NativeEventEmitter` and typed `addListener` helpers,
 *   - thin Promise wrappers around the native methods,
 *   - light normalization of native payloads into the cross-platform types.
 *
 * It deliberately exposes the union of the Android `MeshService` and iOS
 * `Transport` public surfaces, so the same JS works on both platforms. Methods
 * with no native counterpart on a given platform degrade gracefully (the native
 * side either no-ops or maps to the closest equivalent).
 */
class MeshSdkClass {
  private emitter = new NativeEventEmitter(NativeModules.MeshSdk);

  // ---- Mesh identity -------------------------------------------------------

  /**
   * Override the BLE mesh identity (service + characteristic UUIDs), forming a
   * private network. **Call before `startServices()`.** Every device that should
   * see each other must use the same pair. If never called, the SDK's built-in
   * default (distinct from the official bitchat app) is used.
   */
  setMeshId(serviceUUID: string, characteristicUUID: string): Promise<void> {
    return Native.setMeshId(serviceUUID, characteristicUUID);
  }

  // ---- Lifecycle -----------------------------------------------------------

  /** Start BLE (and, where available, Wi-Fi Aware) mesh transports. */
  startServices(): Promise<void> {
    return Native.startServices();
  }

  /** Stop all transports and tear down advertising/scanning. */
  stopServices(): Promise<void> {
    return Native.stopServices();
  }

  /** Force-disconnect every peer (panic / privacy action). */
  emergencyDisconnectAll(): Promise<void> {
    return Native.emergencyDisconnectAll();
  }

  // ---- Identity ------------------------------------------------------------

  getMyPeerID(): Promise<string> {
    return Native.getMyPeerID();
  }

  setNickname(nickname: string): Promise<void> {
    return Native.setNickname(nickname);
  }

  getNickname(): Promise<string> {
    return Native.getNickname();
  }

  getIdentityFingerprint(): Promise<string> {
    return Native.getIdentityFingerprint();
  }

  getStaticNoisePublicKeyHex(): Promise<string | null> {
    return Native.getStaticNoisePublicKeyHex();
  }

  // ---- Messaging -----------------------------------------------------------

  /** Send a public (broadcast) message to the mesh. */
  sendMessage(content: string, mentions: string[] = [], channel: string | null = null): Promise<void> {
    return Native.sendMessage(content, mentions, channel);
  }

  /**
   * Send an end-to-end encrypted private message to a peer.
   * Resolves with the message id used (generated if not supplied).
   */
  sendPrivateMessage(
    content: string,
    recipientPeerID: string,
    recipientNickname: string,
    messageID: string | null = null
  ): Promise<string> {
    return Native.sendPrivateMessage(content, recipientPeerID, recipientNickname, messageID);
  }

  sendReadReceipt(messageID: string, recipientPeerID: string, readerNickname: string): Promise<void> {
    return Native.sendReadReceipt(messageID, recipientPeerID, readerNickname);
  }

  sendDeliveryAck(messageID: string, recipientPeerID: string): Promise<void> {
    return Native.sendDeliveryAck(messageID, recipientPeerID);
  }

  /** Re-announce our presence to the whole mesh. */
  sendBroadcastAnnounce(): Promise<void> {
    return Native.sendBroadcastAnnounce();
  }

  sendAnnouncementToPeer(peerID: string): Promise<void> {
    return Native.sendAnnouncementToPeer(peerID);
  }

  sendFavoriteNotification(peerID: string, isFavorite: boolean): Promise<void> {
    return Native.sendFavoriteNotification(peerID, isFavorite);
  }

  // ---- File transfer -------------------------------------------------------

  /** Broadcast a file to the mesh. Resolves with the transfer id. */
  sendFileBroadcast(file: MeshFilePacket): Promise<string> {
    return Native.sendFileBroadcast(file.fileName, file.mimeType, file.contentBase64);
  }

  /** Send a file privately to one peer. Resolves with the transfer id. */
  sendFilePrivate(recipientPeerID: string, file: MeshFilePacket): Promise<string> {
    return Native.sendFilePrivate(recipientPeerID, file.fileName, file.mimeType, file.contentBase64);
  }

  cancelFileTransfer(transferId: string): Promise<boolean> {
    return Native.cancelFileTransfer(transferId);
  }

  // ---- Peers ---------------------------------------------------------------

  getPeerNicknames(): Promise<{ [peerID: string]: string }> {
    return Native.getPeerNicknames();
  }

  getPeerRSSI(): Promise<{ [peerID: string]: number }> {
    return Native.getPeerRSSI();
  }

  getActivePeerCount(): Promise<number> {
    return Native.getActivePeerCount();
  }

  /** Rich peer snapshots (nickname, connection state, encryption). */
  async getPeers(): Promise<MeshPeer[]> {
    const raw = await Native.getPeerSnapshots();
    return (raw as MeshPeer[]) ?? [];
  }

  getPeerFingerprint(peerID: string): Promise<string | null> {
    return Native.getPeerFingerprint(peerID);
  }

  isPeerConnected(peerID: string): Promise<boolean> {
    return Native.isPeerConnected(peerID);
  }

  // ---- Noise / encryption --------------------------------------------------

  hasEstablishedSession(peerID: string): Promise<boolean> {
    return Native.hasEstablishedSession(peerID);
  }

  async getSessionState(peerID: string): Promise<NoiseSessionState> {
    return (await Native.getSessionState(peerID)) as NoiseSessionState;
  }

  initiateNoiseHandshake(peerID: string): Promise<void> {
    return Native.initiateNoiseHandshake(peerID);
  }

  shouldShowEncryptionIcon(peerID: string): Promise<boolean> {
    return Native.shouldShowEncryptionIcon(peerID);
  }

  getEncryptedPeers(): Promise<string[]> {
    return Native.getEncryptedPeers();
  }

  // ---- QR verification -----------------------------------------------------

  sendVerifyChallenge(peerID: string, noiseKeyHex: string, nonceABase64: string): Promise<void> {
    return Native.sendVerifyChallenge(peerID, noiseKeyHex, nonceABase64);
  }

  sendVerifyResponse(peerID: string, noiseKeyHex: string, nonceABase64: string): Promise<void> {
    return Native.sendVerifyResponse(peerID, noiseKeyHex, nonceABase64);
  }

  // ---- Diagnostics ---------------------------------------------------------

  getDebugStatus(): Promise<string> {
    return Native.getDebugStatus();
  }

  clearAllInternalData(): Promise<void> {
    return Native.clearAllInternalData();
  }

  clearAllEncryptionData(): Promise<void> {
    return Native.clearAllEncryptionData();
  }

  // ---- Events --------------------------------------------------------------

  /**
   * Subscribe to a typed mesh event. Returns a subscription; call `.remove()`
   * to unsubscribe (or use the returned function via `addListener`).
   */
  addListener<E extends MeshEventName>(
    event: E,
    handler: (payload: MeshEventMap[E]) => void
  ): EmitterSubscription {
    return this.emitter.addListener(event, handler as (p: unknown) => void);
  }

  /** Convenience: typed message listener. */
  onMessage(handler: (message: MeshMessage) => void): EmitterSubscription {
    return this.addListener('onMessage', handler);
  }

  /** Convenience: typed peer-list listener. */
  onPeerListUpdate(handler: (peers: string[]) => void): EmitterSubscription {
    return this.addListener('onPeerListUpdate', (p) => handler(p.peers));
  }

  /** Convenience: typed rich-peer listener. */
  onPeerSnapshotsUpdate(handler: (peers: MeshPeer[]) => void): EmitterSubscription {
    return this.addListener('onPeerSnapshotsUpdate', (p) => handler(p.peers));
  }

  /** Remove every listener for an event (or all events if omitted). */
  removeAllListeners(event?: MeshEventName): void {
    const all: MeshEventName[] = [
      'onMessage',
      'onPeerListUpdate',
      'onPeerSnapshotsUpdate',
      'onPeerConnected',
      'onPeerDisconnected',
      'onDeliveryAck',
      'onReadReceipt',
      'onDeliveryStatusUpdate',
      'onChannelLeave',
      'onBluetoothStateChange',
    ];
    (event ? [event] : all).forEach((e) => this.emitter.removeAllListeners(e));
  }
}

/** Singleton instance — there is only ever one mesh transport per process. */
export const MeshSdk = new MeshSdkClass();
export default MeshSdk;
