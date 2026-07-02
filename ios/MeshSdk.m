//
//  MeshSdk.m
//  react-native-mesh-sdk
//
//  Objective-C bridge that registers the Swift `MeshSdk` (an RCTEventEmitter)
//  with React Native and declares each exported method's JS signature.
//

#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface RCT_EXTERN_MODULE(MeshSdk, RCTEventEmitter)

// Lifecycle
RCT_EXTERN_METHOD(setMeshId:(NSString *)service characteristic:(NSString *)characteristic resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(startServices:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(stopServices:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(emergencyDisconnectAll:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(getBluetoothState:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(enableBluetooth:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(setNotificationsEnabled:(BOOL)enabled resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(setPublicNotificationsEnabled:(BOOL)enabled resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(setActiveChatPeer:(NSString *)peerID resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)

// Identity
RCT_EXTERN_METHOD(getMyPeerID:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(setNickname:(NSString *)nickname resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(getNickname:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(getIdentityFingerprint:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(getStaticNoisePublicKeyHex:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)

// Messaging
RCT_EXTERN_METHOD(sendMessage:(NSString *)content mentions:(NSArray *)mentions channel:(NSString *)channel resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(sendPrivateMessage:(NSString *)content recipientPeerID:(NSString *)recipientPeerID recipientNickname:(NSString *)recipientNickname messageID:(NSString *)messageID resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(sendReadReceipt:(NSString *)messageID recipientPeerID:(NSString *)recipientPeerID readerNickname:(NSString *)readerNickname resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(sendDeliveryAck:(NSString *)messageID recipientPeerID:(NSString *)recipientPeerID resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(sendBroadcastAnnounce:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(sendAnnouncementToPeer:(NSString *)peerIDStr resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(sendFavoriteNotification:(NSString *)peerIDStr isFavorite:(BOOL)isFavorite resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)

// File transfer
RCT_EXTERN_METHOD(sendFileBroadcast:(NSString *)fileName mimeType:(NSString *)mimeType contentBase64:(NSString *)contentBase64 resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(sendFilePrivate:(NSString *)recipientPeerID fileName:(NSString *)fileName mimeType:(NSString *)mimeType contentBase64:(NSString *)contentBase64 resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(cancelFileTransfer:(NSString *)transferId resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)

// Peers
RCT_EXTERN_METHOD(getPeerNicknames:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(getPeerRSSI:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(getActivePeerCount:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(getPeerSnapshots:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(getPeerFingerprint:(NSString *)peerIDStr resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(isPeerConnected:(NSString *)peerIDStr resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)

// Noise / encryption
RCT_EXTERN_METHOD(hasEstablishedSession:(NSString *)peerIDStr resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(getSessionState:(NSString *)peerIDStr resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(initiateNoiseHandshake:(NSString *)peerIDStr resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(shouldShowEncryptionIcon:(NSString *)peerIDStr resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(getEncryptedPeers:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)

// QR verification
RCT_EXTERN_METHOD(sendVerifyChallenge:(NSString *)peerIDStr noiseKeyHex:(NSString *)noiseKeyHex nonceABase64:(NSString *)nonceABase64 resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(sendVerifyResponse:(NSString *)peerIDStr noiseKeyHex:(NSString *)noiseKeyHex nonceABase64:(NSString *)nonceABase64 resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)

// Diagnostics
RCT_EXTERN_METHOD(getDebugStatus:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(clearAllInternalData:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(clearAllEncryptionData:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)

+ (BOOL)requiresMainQueueSetup { return YES; }

@end
