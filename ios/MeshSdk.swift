//
//  MeshSdk.swift
//  react-native-mesh-sdk :: Native SDK (iOS)
//
//  Bridge between React Native and Core BitChat. This is the ONLY iOS file we
//  maintain (plus the .m bridge). It:
//    1. Builds one `BLEService` (the `Transport`) from the unchanged Core
//       BitChat classes vendored under ios/core (see scripts/sync-core.sh),
//       wired exactly like bitchat-ios `AppRuntime`/`ChatViewModel` do it.
//    2. Conforms to `BitchatDelegate` + `TransportEventDelegate` and forwards
//       every callback to JS as an `RCTEventEmitter` event.
//    3. Exposes the public `Transport` methods to JS (see MeshSdk.m).
//
//  We only touch the *public* `Transport` / `BitchatDelegate` surfaces, so an
//  updated Core BitChat is a pure file copy.
//

import Foundation
import React
import Combine
import CoreBluetooth
import UIKit
import BitFoundation

@objc(MeshSdk)
final class MeshSdk: RCTEventEmitter {

    // MARK: - Core BitChat wiring (mirrors AppRuntime)

    // Single source of truth for the mesh identity (see Android MeshSdkModule).
    // Distinct from official bitchat so this SDK forms its OWN private mesh.
    private static let defaultServiceUUID = "7A9C1E3D-2B4F-4A6C-8D5E-1F2A3B4C5D6E"
    private static let defaultCharacteristicUUID = "8B0D2F4E-3C5A-4B7D-9E6F-2A3B4C5D6E7F"

    private let keychain: KeychainManagerProtocol = KeychainManager()
    private lazy var idBridge = NostrIdentityBridge()
    private lazy var identityManager: SecureIdentityStateManagerProtocol =
        SecureIdentityStateManager(keychain)

    private lazy var transport: Transport = {
        let svc = BLEService(keychain: keychain, idBridge: idBridge, identityManager: identityManager)
        return svc
    }()

    private var hasListeners = false

    /// Latest Bluetooth adapter state, kept in sync via didUpdateBluetoothState
    /// so getBluetoothState() can answer synchronously.
    private var lastBluetoothState = "unknown"

    /// Local DM notifications — in-code toggle + the chat currently on screen
    /// (so we don't notify for a conversation the user is already viewing).
    private var notificationsEnabled = true
    private var activeChatPeer: String?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - RCTEventEmitter plumbing

    override init() {
        super.init()
        // Inject the private-mesh UUIDs into the Core (BLEService's `static var`,
        // made mutable via sync-core.sh) before the transport starts. This keeps
        // the mesh identity defined at the SDK layer, not in vendored source.
        BLEService.serviceUUID = CBUUID(string: Self.defaultServiceUUID)
        BLEService.characteristicUUID = CBUUID(string: Self.defaultCharacteristicUUID)
        // Attach as the delegate sinks. Both are weak on the transport side.
        transport.delegate = self
        transport.eventDelegate = self
    }

    override static func requiresMainQueueSetup() -> Bool { true }

    override func supportedEvents() -> [String]! {
        [
            "onMessage",
            "onPeerListUpdate",
            "onPeerSnapshotsUpdate",
            "onPeerConnected",
            "onPeerDisconnected",
            "onDeliveryAck",
            "onReadReceipt",
            "onDeliveryStatusUpdate",
            "onChannelLeave",
            "onBluetoothStateChange",
        ]
    }

    override func startObserving() { hasListeners = true }
    override func stopObserving() { hasListeners = false }

    private func emit(_ name: String, _ body: Any) {
        guard hasListeners else { return }
        sendEvent(withName: name, body: body)
    }

    private func peerID(_ string: String) -> PeerID { PeerID(str: string) }

    // MARK: - Lifecycle

    /// Overrides the mesh identity (BLE service + characteristic UUIDs). Must be
    /// called BEFORE startServices(). All devices that should see each other must
    /// use the same pair.
    @objc(setMeshId:characteristic:resolver:rejecter:)
    func setMeshId(_ service: String, characteristic: String,
                   resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        BLEService.serviceUUID = CBUUID(string: service)
        BLEService.characteristicUUID = CBUUID(string: characteristic)
        resolve(nil)
    }

    @objc(startServices:rejecter:)
    func startServices(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        transport.startServices()
        if notificationsEnabled { NotificationService.shared.requestAuthorization() }
        resolve(nil)
    }

    @objc(stopServices:rejecter:)
    func stopServices(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        transport.stopServices()
        resolve(nil)
    }

    @objc(emergencyDisconnectAll:rejecter:)
    func emergencyDisconnectAll(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        transport.emergencyDisconnectAll()
        resolve(nil)
    }

    // MARK: - Bluetooth state

    @objc(getBluetoothState:rejecter:)
    func getBluetoothState(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(lastBluetoothState)
    }

    /// iOS apps cannot toggle Bluetooth programmatically — the user must enable
    /// it in Settings/Control Center. We open the app's Settings page as the
    /// closest actionable step; JS should also show guidance text.
    @objc(enableBluetooth:rejecter:)
    func enableBluetooth(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        DispatchQueue.main.async {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        resolve(false)
    }

    // MARK: - Notifications

    /// Enable/disable local DM notifications (the in-code toggle).
    @objc(setNotificationsEnabled:resolver:rejecter:)
    func setNotificationsEnabled(_ enabled: Bool, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        notificationsEnabled = enabled
        if enabled { NotificationService.shared.requestAuthorization() }
        resolve(nil)
    }

    /// Tell the SDK which private chat is on screen (null = none/public).
    @objc(setActiveChatPeer:resolver:rejecter:)
    func setActiveChatPeer(_ peerID: NSString?, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        activeChatPeer = peerID as String?
        resolve(nil)
    }

    /// Show a DM notification unless disabled or the user is already viewing this
    /// chat in the foreground. iOS presents it automatically when backgrounded.
    fileprivate func notifyPrivateMessage(from sender: String, content: String, peerID: PeerID) {
        guard notificationsEnabled else { return }
        let inForeground = UIApplication.shared.applicationState == .active
        if inForeground && activeChatPeer == peerID.id { return }
        NotificationService.shared.sendPrivateMessageNotification(from: sender, message: content, peerID: peerID)
    }

    // MARK: - Identity

    @objc(getMyPeerID:rejecter:)
    func getMyPeerID(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(transport.myPeerID.id)
    }

    @objc(setNickname:resolver:rejecter:)
    func setNickname(_ nickname: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        transport.setNickname(nickname)
        resolve(nil)
    }

    @objc(getNickname:rejecter:)
    func getNickname(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(transport.myNickname)
    }

    @objc(getIdentityFingerprint:rejecter:)
    func getIdentityFingerprint(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(transport.noiseIdentityFingerprint())
    }

    @objc(getStaticNoisePublicKeyHex:rejecter:)
    func getStaticNoisePublicKeyHex(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(transport.noiseStaticPublicKeyData().hexEncodedString())
    }

    // MARK: - Messaging

    @objc(sendMessage:mentions:channel:resolver:rejecter:)
    func sendMessage(_ content: String, mentions: [String], channel: String?,
                     resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        // iOS `Transport` carries channels in-band via geohash; the public
        // sendMessage signature takes content + mentions only.
        transport.sendMessage(content, mentions: mentions)
        resolve(nil)
    }

    @objc(sendPrivateMessage:recipientPeerID:recipientNickname:messageID:resolver:rejecter:)
    func sendPrivateMessage(_ content: String, recipientPeerID: String, recipientNickname: String,
                            messageID: String?, resolver resolve: @escaping RCTPromiseResolveBlock,
                            rejecter reject: @escaping RCTPromiseRejectBlock) {
        let id = messageID ?? UUID().uuidString
        let peer = peerID(recipientPeerID)
        // Off the bridge: establish the Noise session first, then send, so the
        // first private message isn't dropped by the Core's fire-and-forget.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.ensureSessionBlocking(peer, timeout: 6.0)
            self.transport.sendPrivateMessage(content, to: peer,
                                              recipientNickname: recipientNickname, messageID: id)
            resolve(id)
        }
    }

    /// Guarantees an established Noise session before the first private message
    /// (the Core fire-and-forgets the first PM otherwise). Triggers the
    /// handshake and blocks off-bridge until it completes or times out.
    private func ensureSessionBlocking(_ peer: PeerID, timeout: TimeInterval) {
        if transport.noiseSessionPublicKeyData(for: peer) != nil { return }
        transport.triggerHandshake(with: peer)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.15)
            if transport.noiseSessionPublicKeyData(for: peer) != nil { return }
        }
    }

    @objc(sendReadReceipt:recipientPeerID:readerNickname:resolver:rejecter:)
    func sendReadReceipt(_ messageID: String, recipientPeerID: String, readerNickname: String,
                         resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let receipt = ReadReceipt(originalMessageID: messageID, readerID: transport.myPeerID, readerNickname: readerNickname)
        transport.sendReadReceipt(receipt, to: peerID(recipientPeerID))
        resolve(nil)
    }

    @objc(sendDeliveryAck:recipientPeerID:resolver:rejecter:)
    func sendDeliveryAck(_ messageID: String, recipientPeerID: String,
                         resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        transport.sendDeliveryAck(for: messageID, to: peerID(recipientPeerID))
        resolve(nil)
    }

    @objc(sendBroadcastAnnounce:rejecter:)
    func sendBroadcastAnnounce(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        transport.sendBroadcastAnnounce()
        resolve(nil)
    }

    @objc(sendAnnouncementToPeer:resolver:rejecter:)
    func sendAnnouncementToPeer(_ peerIDStr: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        // No per-peer announce in the public iOS Transport; broadcast is the equivalent.
        transport.sendBroadcastAnnounce()
        resolve(nil)
    }

    @objc(sendFavoriteNotification:isFavorite:resolver:rejecter:)
    func sendFavoriteNotification(_ peerIDStr: String, isFavorite: Bool,
                                  resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        transport.sendFavoriteNotification(to: peerID(peerIDStr), isFavorite: isFavorite)
        resolve(nil)
    }

    // MARK: - File transfer

    @objc(sendFileBroadcast:mimeType:contentBase64:resolver:rejecter:)
    func sendFileBroadcast(_ fileName: String, mimeType: String, contentBase64: String,
                           resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        guard let packet = makeFilePacket(fileName, mimeType, contentBase64) else {
            reject("mesh_error", "Invalid base64 file content", nil); return
        }
        let transferId = UUID().uuidString
        transport.sendFileBroadcast(packet, transferId: transferId)
        resolve(transferId)
    }

    @objc(sendFilePrivate:fileName:mimeType:contentBase64:resolver:rejecter:)
    func sendFilePrivate(_ recipientPeerID: String, fileName: String, mimeType: String, contentBase64: String,
                         resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        guard let packet = makeFilePacket(fileName, mimeType, contentBase64) else {
            reject("mesh_error", "Invalid base64 file content", nil); return
        }
        let transferId = UUID().uuidString
        transport.sendFilePrivate(packet, to: peerID(recipientPeerID), transferId: transferId)
        resolve(transferId)
    }

    @objc(cancelFileTransfer:resolver:rejecter:)
    func cancelFileTransfer(_ transferId: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        transport.cancelTransfer(transferId)
        resolve(true)
    }

    private func makeFilePacket(_ fileName: String, _ mimeType: String, _ contentBase64: String) -> BitchatFilePacket? {
        guard let data = Data(base64Encoded: contentBase64) else { return nil }
        return BitchatFilePacket(fileName: fileName, fileSize: UInt64(data.count), mimeType: mimeType, content: data)
    }

    // MARK: - Peers

    @objc(getPeerNicknames:rejecter:)
    func getPeerNicknames(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        var out: [String: String] = [:]
        for (pid, name) in transport.getPeerNicknames() { out[pid.id] = name }
        resolve(out)
    }

    @objc(getPeerRSSI:rejecter:)
    func getPeerRSSI(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        // RSSI is not exposed on the public iOS Transport; return empty map.
        resolve([String: Int]())
    }

    @objc(getActivePeerCount:rejecter:)
    func getActivePeerCount(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(transport.currentPeerSnapshots().filter { $0.isConnected }.count)
    }

    @objc(getPeerSnapshots:rejecter:)
    func getPeerSnapshots(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(transport.currentPeerSnapshots().map { snapshotToDict($0) })
    }

    @objc(getPeerFingerprint:resolver:rejecter:)
    func getPeerFingerprint(_ peerIDStr: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(transport.getFingerprint(for: peerID(peerIDStr)))
    }

    @objc(isPeerConnected:resolver:rejecter:)
    func isPeerConnected(_ peerIDStr: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(transport.isPeerConnected(peerID(peerIDStr)))
    }

    // MARK: - Noise / encryption

    @objc(hasEstablishedSession:resolver:rejecter:)
    func hasEstablishedSession(_ peerIDStr: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(transport.noiseSessionPublicKeyData(for: peerID(peerIDStr)) != nil)
    }

    @objc(getSessionState:resolver:rejecter:)
    func getSessionState(_ peerIDStr: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        switch transport.getNoiseSessionState(for: peerID(peerIDStr)) {
        case .none: resolve("none")
        case .handshaking, .handshakeQueued: resolve("handshaking")
        case .established: resolve("established")
        case .failed: resolve("failed")
        }
    }

    @objc(initiateNoiseHandshake:resolver:rejecter:)
    func initiateNoiseHandshake(_ peerIDStr: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        transport.triggerHandshake(with: peerID(peerIDStr))
        resolve(nil)
    }

    @objc(shouldShowEncryptionIcon:resolver:rejecter:)
    func shouldShowEncryptionIcon(_ peerIDStr: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(transport.noiseSessionPublicKeyData(for: peerID(peerIDStr)) != nil)
    }

    @objc(getEncryptedPeers:rejecter:)
    func getEncryptedPeers(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        let ids = transport.currentPeerSnapshots()
            .filter { transport.noiseSessionPublicKeyData(for: $0.peerID) != nil }
            .map { $0.peerID.id }
        resolve(ids)
    }

    // MARK: - QR verification

    @objc(sendVerifyChallenge:noiseKeyHex:nonceABase64:resolver:rejecter:)
    func sendVerifyChallenge(_ peerIDStr: String, noiseKeyHex: String, nonceABase64: String,
                             resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        guard let nonce = Data(base64Encoded: nonceABase64) else { reject("mesh_error", "bad nonce", nil); return }
        transport.sendVerifyChallenge(to: peerID(peerIDStr), noiseKeyHex: noiseKeyHex, nonceA: nonce)
        resolve(nil)
    }

    @objc(sendVerifyResponse:noiseKeyHex:nonceABase64:resolver:rejecter:)
    func sendVerifyResponse(_ peerIDStr: String, noiseKeyHex: String, nonceABase64: String,
                            resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        guard let nonce = Data(base64Encoded: nonceABase64) else { reject("mesh_error", "bad nonce", nil); return }
        transport.sendVerifyResponse(to: peerID(peerIDStr), noiseKeyHex: noiseKeyHex, nonceA: nonce)
        resolve(nil)
    }

    // MARK: - Diagnostics

    @objc(getDebugStatus:rejecter:)
    func getDebugStatus(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve("peers=\(transport.currentPeerSnapshots().count) myPeerID=\(transport.myPeerID.id)")
    }

    @objc(clearAllInternalData:rejecter:)
    func clearAllInternalData(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        transport.emergencyDisconnectAll()
        resolve(nil)
    }

    @objc(clearAllEncryptionData:rejecter:)
    func clearAllEncryptionData(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        transport.emergencyDisconnectAll()
        resolve(nil)
    }
}

// MARK: - Mapping helpers

private extension MeshSdk {
    func snapshotToDict(_ s: TransportPeerSnapshot) -> [String: Any] {
        [
            "peerID": s.peerID.id,
            "nickname": s.nickname,
            "isConnected": s.isConnected,
            "noisePublicKeyHex": s.noisePublicKey?.hexEncodedString() as Any,
            "fingerprint": transport.getFingerprint(for: s.peerID) as Any,
            "isEncrypted": transport.noiseSessionPublicKeyData(for: s.peerID) != nil,
            "lastSeen": s.lastSeen.timeIntervalSince1970 * 1000,
        ]
    }

    func deliveryStatusToDict(_ status: DeliveryStatus) -> [String: Any] {
        switch status {
        case .sending: return ["kind": "sending"]
        case .sent: return ["kind": "sent"]
        case .delivered(let to, let at):
            return ["kind": "delivered", "to": to, "at": at.timeIntervalSince1970 * 1000]
        case .read(let by, let at):
            return ["kind": "read", "by": by, "at": at.timeIntervalSince1970 * 1000]
        case .failed(let reason):
            return ["kind": "failed", "reason": reason]
        case .partiallyDelivered(let reached, let total):
            return ["kind": "partiallyDelivered", "reached": reached, "total": total]
        }
    }

    func messageToDict(_ m: BitchatMessage) -> [String: Any] {
        var dict: [String: Any] = [
            "id": m.id,
            "sender": m.sender,
            "content": m.content,
            "type": "message",
            "timestamp": m.timestamp.timeIntervalSince1970 * 1000,
            "isRelay": m.isRelay,
            "isPrivate": m.isPrivate,
            "isEncrypted": m.isPrivate,
        ]
        dict["originalSender"] = m.originalSender as Any
        dict["recipientNickname"] = m.recipientNickname as Any
        dict["senderPeerID"] = m.senderPeerID?.id as Any
        dict["mentions"] = m.mentions as Any
        if let status = m.deliveryStatus {
            dict["deliveryStatus"] = deliveryStatusToDict(status)
        }
        return dict
    }
}

// MARK: - BitchatDelegate (Core BitChat callbacks → JS)

extension MeshSdk: BitchatDelegate {
    func didReceiveMessage(_ message: BitchatMessage) {
        emit("onMessage", messageToDict(message))
    }

    func didConnectToPeer(_ peerID: PeerID) {
        emit("onPeerConnected", ["peerID": peerID.id])
    }

    func didDisconnectFromPeer(_ peerID: PeerID) {
        emit("onPeerDisconnected", ["peerID": peerID.id])
    }

    func didUpdatePeerList(_ peers: [PeerID]) {
        emit("onPeerListUpdate", ["peers": peers.map { $0.id }])
    }

    func didUpdateMessageDeliveryStatus(_ messageID: String, status: DeliveryStatus) {
        emit("onDeliveryStatusUpdate", ["messageID": messageID, "status": deliveryStatusToDict(status)])
    }

    // Private (Noise-encrypted) messages arrive here as a raw payload that the
    // app must decode — the transport does NOT turn them into BitchatMessages.
    // Without this, incoming private messages (e.g. Android → iOS) are dropped.
    func didReceiveNoisePayload(from peerID: PeerID, type: NoisePayloadType, payload: Data, timestamp: Date) {
        switch type {
        case .privateMessage:
            guard let packet = PrivateMessagePacket.decode(from: payload) else { return }
            let sender = transport.peerNickname(peerID: peerID) ?? peerID.id
            emit("onMessage", [
                "id": packet.messageID,
                "sender": sender,
                "content": packet.content,
                "type": "message",
                "timestamp": timestamp.timeIntervalSince1970 * 1000,
                "isRelay": false,
                "isPrivate": true,
                "isEncrypted": true,
                "senderPeerID": peerID.id,
                "recipientNickname": transport.myNickname,
            ])
            notifyPrivateMessage(from: sender, content: packet.content, peerID: peerID)
            // Acknowledge delivery so the sender's message shows as delivered.
            transport.sendDeliveryAck(for: packet.messageID, to: peerID)
        case .delivered:
            if let mid = String(data: payload, encoding: .utf8) {
                emit("onDeliveryAck", ["messageID": mid, "recipientPeerID": peerID.id])
            }
        case .readReceipt:
            if let mid = String(data: payload, encoding: .utf8) {
                emit("onReadReceipt", ["messageID": mid, "recipientPeerID": peerID.id])
            }
        default:
            break
        }
    }

    func didReceivePublicMessage(from peerID: PeerID, nickname: String, content: String, timestamp: Date, messageID: String?) {
        emit("onMessage", [
            "id": messageID ?? UUID().uuidString,
            "sender": nickname,
            "content": content,
            "type": "message",
            "timestamp": timestamp.timeIntervalSince1970 * 1000,
            "isRelay": false,
            "isPrivate": false,
            "isEncrypted": false,
            "senderPeerID": peerID.id,
        ])
    }

    func didUpdateBluetoothState(_ state: CBManagerState) {
        let str: String
        switch state {
        case .poweredOn: str = "poweredOn"
        case .poweredOff: str = "poweredOff"
        case .resetting: str = "resetting"
        case .unauthorized: str = "unauthorized"
        case .unsupported: str = "unsupported"
        default: str = "unknown"
        }
        lastBluetoothState = str
        emit("onBluetoothStateChange", ["state": str])
    }
}

// MARK: - TransportEventDelegate

extension MeshSdk: TransportEventDelegate {
    func didReceiveTransportEvent(_ event: TransportEvent) {
        switch event {
        case .peerSnapshotsUpdated(let snapshots):
            emit("onPeerSnapshotsUpdate", ["peers": snapshots.map { snapshotToDict($0) }])
        default:
            // BLEService delivers incoming messages and peer events through this
            // typed sink (emitTransportEvent), NOT through BitchatDelegate. Dispatch
            // them via the BitchatDelegate mapping so our emit-to-JS handlers fire —
            // without this, messages received over the mesh never reach JS.
            self.receiveTransportEvent(event)
        }
    }
}
