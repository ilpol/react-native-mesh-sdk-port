package com.meshsdk

import android.util.Base64
import com.bitchat.android.mesh.BluetoothMeshService
import com.bitchat.android.mesh.MeshDelegate
import com.bitchat.android.mesh.MeshService
import com.bitchat.android.mesh.UnifiedMeshService
import com.bitchat.android.model.BitchatFilePacket
import com.bitchat.android.model.BitchatMessage
import com.bitchat.android.noise.NoiseSession
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.WritableArray
import com.facebook.react.modules.core.DeviceEventManagerModule

/**
 * Native SDK (Android) — the bridge between React Native and Core BitChat.
 *
 * Responsibilities, and ONLY these (no Core BitChat logic lives here):
 *   1. Own a single [UnifiedMeshService] instance built from the unchanged
 *      Core BitChat classes vendored under src/main/java/com/bitchat/android.
 *   2. Implement [MeshDelegate] and forward every callback to JS as a typed
 *      DeviceEvent.
 *   3. Expose each public [MeshService] method as a `@ReactMethod`.
 *
 * Because we only touch the *public* `MeshService` / `MeshDelegate` surfaces,
 * dropping in an updated Core BitChat is a pure file copy — see sync-core.sh.
 */
class MeshSdkModule(private val reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext), MeshDelegate {

    companion object {
        const val NAME = "MeshSdk"
        // Single source of truth for the mesh identity. Distinct from official
        // bitchat's UUIDs so this SDK forms its OWN private mesh. Injected into
        // the Core (AppConstants) at init; overridable at runtime via setMeshId().
        const val DEFAULT_SERVICE_UUID = "7A9C1E3D-2B4F-4A6C-8D5E-1F2A3B4C5D6E"
        const val DEFAULT_CHARACTERISTIC_UUID = "8B0D2F4E-3C5A-4B7D-9E6F-2A3B4C5D6E7F"
    }

    override fun getName(): String = NAME

    @Volatile private var serviceUUID = DEFAULT_SERVICE_UUID
    @Volatile private var characteristicUUID = DEFAULT_CHARACTERISTIC_UUID

    // ---- Core BitChat instance ----------------------------------------------

    private val mesh: MeshService by lazy {
        initCore()
        // Obtain the mesh via the process-wide MeshServiceHolder so the same
        // instance is shared with MeshForegroundService (which keeps the mesh
        // alive in the background). Creating it directly would give the FGS a
        // different instance.
        com.bitchat.android.service.MeshServiceHolder
            .getUnifiedOrCreate(reactContext.applicationContext)
            .also { it.delegate = this }
    }

    /**
     * Replicates the essential global initialization that bitchat-android performs
     * in `BitchatApplication.onCreate()`. The example/host app uses the standard
     * React Native Application, so without this the Core's preference stores,
     * favorites (used for message routing) and registries are never set up.
     * Every call is guarded — missing optional subsystems must not break the mesh.
     */
    private var coreInitialized = false
    @Synchronized
    private fun initCore() {
        if (coreInitialized) return
        coreInitialized = true
        // Inject the mesh UUIDs into the Core BEFORE the BLE stack starts. The
        // Core's AppConstants fields are `var` (via sync-core.sh) precisely so
        // this can be set from the SDK layer rather than baked into the vendored
        // source. Must run before BluetoothMeshService is constructed (it is —
        // this is called from the `mesh` lazy initializer, before getUnifiedOrCreate).
        runCatching {
            com.bitchat.android.util.AppConstants.Mesh.Gatt.SERVICE_UUID =
                java.util.UUID.fromString(serviceUUID)
            com.bitchat.android.util.AppConstants.Mesh.Gatt.CHARACTERISTIC_UUID =
                java.util.UUID.fromString(characteristicUUID)
        }
        // Application is a Context, so it satisfies both Context- and
        // Application-typed initializer parameters in the Core.
        val app = reactContext.applicationContext as? android.app.Application ?: return
        runCatching { com.bitchat.android.service.MeshServicePreferences.init(app) }
        runCatching { com.bitchat.android.ui.debug.DebugPreferenceManager.init(app) }
        runCatching { com.bitchat.android.ui.theme.ThemePreferenceManager.init(app) }
        runCatching { com.bitchat.android.favorites.FavoritesPersistenceService.initialize(app) }
        runCatching { com.bitchat.android.nostr.RelayDirectory.initialize(app) }
        runCatching { com.bitchat.android.nostr.GeohashAliasRegistry.initialize(app) }
        runCatching { com.bitchat.android.nostr.GeohashConversationRegistry.initialize(app) }
        runCatching { com.bitchat.android.wifiaware.WifiAwareController.initialize(app, false) }
    }

    /** App-supplied nickname, surfaced to Core BitChat via [getNickname]. */
    @Volatile private var nickname: String = "anon"

    /** Favorite peer ids, surfaced to Core BitChat via [isFavorite]. */
    private val favorites = mutableSetOf<String>()

    // ---- Event plumbing -----------------------------------------------------

    private var listenerCount = 0

    private fun emit(event: String, params: Any?) {
        if (listenerCount == 0) return
        reactContext
            .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
            .emit(event, params)
    }

    @ReactMethod fun addListener(eventName: String) { listenerCount++ }

    @ReactMethod fun removeListeners(count: Int) {
        listenerCount = (listenerCount - count).coerceAtLeast(0)
    }

    // =====================================================================
    // MeshDelegate — Core BitChat callbacks → JS events
    // =====================================================================

    override fun didReceiveMessage(message: BitchatMessage) {
        emit("onMessage", MeshSdkMapper.messageToMap(message))
    }

    override fun didUpdatePeerList(peers: List<String>) {
        val payload = Arguments.createMap()
        payload.putArray("peers", MeshSdkMapper.stringListToArray(peers))
        emit("onPeerListUpdate", payload)
        // Also push a rich snapshot so UIs can render nickname/encryption state.
        emitPeerSnapshots(peers)
    }

    override fun didReceiveChannelLeave(channel: String, fromPeer: String) {
        val payload = Arguments.createMap()
        payload.putString("channel", channel)
        payload.putString("fromPeer", fromPeer)
        emit("onChannelLeave", payload)
    }

    override fun didReceiveDeliveryAck(messageID: String, recipientPeerID: String) {
        val payload = Arguments.createMap()
        payload.putString("messageID", messageID)
        payload.putString("recipientPeerID", recipientPeerID)
        emit("onDeliveryAck", payload)
    }

    override fun didReceiveReadReceipt(messageID: String, recipientPeerID: String) {
        val payload = Arguments.createMap()
        payload.putString("messageID", messageID)
        payload.putString("recipientPeerID", recipientPeerID)
        emit("onReadReceipt", payload)
    }

    override fun decryptChannelMessage(encryptedContent: ByteArray, channel: String): String? {
        // Channel encryption is owned by the app layer in BitChat; not handled here.
        return null
    }

    override fun getNickname(): String = nickname

    override fun isFavorite(peerID: String): Boolean = favorites.contains(peerID)

    private fun emitPeerSnapshots(peers: List<String>) {
        val rssi = runCatching { mesh.getPeerRSSI() }.getOrDefault(emptyMap())
        val encrypted = runCatching { mesh.getEncryptedPeers().toSet() }.getOrDefault(emptySet())
        val arr: WritableArray = Arguments.createArray()
        peers.forEach { peerID ->
            val info = runCatching { mesh.getPeerInfo(peerID) }.getOrNull() ?: return@forEach
            val fp = runCatching { mesh.getPeerFingerprint(peerID) }.getOrNull()
            arr.pushMap(
                MeshSdkMapper.peerToMap(
                    info = info,
                    rssi = rssi[peerID],
                    fingerprint = fp,
                    isEncrypted = encrypted.contains(peerID)
                )
            )
        }
        val payload = Arguments.createMap()
        payload.putArray("peers", arr)
        emit("onPeerSnapshotsUpdate", payload)
    }

    // =====================================================================
    // Lifecycle
    // =====================================================================

    /**
     * Overrides the mesh identity (BLE service + characteristic UUIDs). Must be
     * called BEFORE startServices() — once the mesh is created the UUIDs are
     * locked in. All devices that should see each other must use the same pair.
     */
    @ReactMethod fun setMeshId(service: String, characteristic: String, promise: Promise) =
        guard(promise) {
            serviceUUID = service
            characteristicUUID = characteristic
            null
        }

    @ReactMethod fun startServices(promise: Promise) = guard(promise) {
        mesh.startServices()
        // Keep the mesh alive when the app is backgrounded. The FGS reuses the
        // same instance via MeshServiceHolder and no-ops if background is
        // disabled or the notification/BT permissions are missing.
        com.bitchat.android.service.MeshForegroundService.start(reactContext.applicationContext)
        null
    }

    @ReactMethod fun stopServices(promise: Promise) = guard(promise) {
        com.bitchat.android.service.MeshForegroundService.stop(reactContext.applicationContext)
        mesh.stopServices(); null
    }

    @ReactMethod fun emergencyDisconnectAll(promise: Promise) = guard(promise) {
        // Closest public equivalent on Android: stop + clear transient state.
        mesh.stopServices(); null
    }

    // =====================================================================
    // Identity
    // =====================================================================

    @ReactMethod fun getMyPeerID(promise: Promise) = guard(promise) { mesh.myPeerID }

    @ReactMethod fun setNickname(value: String, promise: Promise) = guard(promise) {
        nickname = value
        // The Core builds identity announcements from NicknameProvider →
        // DataManager, NOT from MeshDelegate.getNickname(). Persist it there or
        // peers see the auto-generated "anon####" default instead of this name.
        runCatching {
            com.bitchat.android.ui.DataManager(reactContext.applicationContext).saveNickname(value)
        }
        // Re-announce so peers pick up the new nickname.
        runCatching { mesh.sendBroadcastAnnounce() }
        null
    }

    @ReactMethod fun getNickname(promise: Promise) = guard(promise) { nickname }

    @ReactMethod fun getIdentityFingerprint(promise: Promise) = guard(promise) {
        mesh.getIdentityFingerprint()
    }

    @ReactMethod fun getStaticNoisePublicKeyHex(promise: Promise) = guard(promise) {
        mesh.getStaticNoisePublicKey()?.let { MeshSdkMapper.bytesToHex(it) }
    }

    // =====================================================================
    // Messaging
    // =====================================================================

    @ReactMethod
    fun sendMessage(content: String, mentions: ReadableArray, channel: String?, promise: Promise) =
        guard(promise) {
            mesh.sendMessage(content, mentions.toStringList(), channel); null
        }

    @ReactMethod
    fun sendPrivateMessage(
        content: String,
        recipientPeerID: String,
        recipientNickname: String,
        messageID: String?,
        promise: Promise
    ) {
        val id = messageID ?: java.util.UUID.randomUUID().toString().uppercase()
        // Off the bridge thread: establish the Noise session first, then send.
        Thread {
            try {
                ensureSessionBlocking(recipientPeerID, 6000L)
                mesh.sendPrivateMessage(content, recipientPeerID, recipientNickname, id)
                promise.resolve(id)
            } catch (e: Throwable) {
                promise.reject("mesh_error", e.message, e)
            }
        }.start()
    }

    /**
     * Guarantees an established Noise session before the first private message.
     * The Core "fires and forgets" the first PM when no session exists (it only
     * kicks off the handshake), so without this the first message is dropped.
     * Triggers the handshake and blocks (off-bridge) until it completes or times
     * out; then the caller sends over the ready session.
     */
    private fun ensureSessionBlocking(peerID: String, timeoutMs: Long) {
        if (runCatching { mesh.hasEstablishedSession(peerID) }.getOrDefault(false)) return
        runCatching { mesh.initiateNoiseHandshake(peerID) }
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            Thread.sleep(150)
            if (runCatching { mesh.hasEstablishedSession(peerID) }.getOrDefault(false)) return
        }
    }

    @ReactMethod
    fun sendReadReceipt(messageID: String, recipientPeerID: String, readerNickname: String, promise: Promise) =
        guard(promise) {
            mesh.sendReadReceipt(messageID, recipientPeerID, readerNickname); null
        }

    @ReactMethod
    fun sendDeliveryAck(messageID: String, recipientPeerID: String, promise: Promise) =
        guard(promise) { mesh.sendDeliveryAck(messageID, recipientPeerID); null }

    @ReactMethod fun sendBroadcastAnnounce(promise: Promise) = guard(promise) {
        mesh.sendBroadcastAnnounce(); null
    }

    @ReactMethod fun sendAnnouncementToPeer(peerID: String, promise: Promise) = guard(promise) {
        mesh.sendAnnouncementToPeer(peerID); null
    }

    @ReactMethod
    fun sendFavoriteNotification(peerID: String, isFavorite: Boolean, promise: Promise) =
        guard(promise) {
            if (isFavorite) favorites.add(peerID) else favorites.remove(peerID)
            mesh.sendFavoriteNotification(peerID, isFavorite)
            null
        }

    // =====================================================================
    // File transfer
    // =====================================================================

    @ReactMethod
    fun sendFileBroadcast(fileName: String, mimeType: String, contentBase64: String, promise: Promise) =
        guard(promise) {
            val packet = buildFilePacket(fileName, mimeType, contentBase64)
            mesh.sendFileBroadcast(packet)
            packet.fileName
        }

    @ReactMethod
    fun sendFilePrivate(
        recipientPeerID: String,
        fileName: String,
        mimeType: String,
        contentBase64: String,
        promise: Promise
    ) = guard(promise) {
        val packet = buildFilePacket(fileName, mimeType, contentBase64)
        mesh.sendFilePrivate(recipientPeerID, packet)
        packet.fileName
    }

    @ReactMethod fun cancelFileTransfer(transferId: String, promise: Promise) = guard(promise) {
        mesh.cancelFileTransfer(transferId)
    }

    private fun buildFilePacket(fileName: String, mimeType: String, contentBase64: String): BitchatFilePacket {
        val bytes = Base64.decode(contentBase64, Base64.DEFAULT)
        return BitchatFilePacket(
            fileName = fileName,
            fileSize = bytes.size.toLong(),
            mimeType = mimeType,
            content = bytes
        )
    }

    // =====================================================================
    // Peers
    // =====================================================================

    @ReactMethod fun getPeerNicknames(promise: Promise) = guard(promise) {
        MeshSdkMapper.stringMapToWritable(mesh.getPeerNicknames())
    }

    @ReactMethod fun getPeerRSSI(promise: Promise) = guard(promise) {
        MeshSdkMapper.intMapToWritable(mesh.getPeerRSSI())
    }

    @ReactMethod fun getActivePeerCount(promise: Promise) = guard(promise) {
        mesh.getActivePeerCount()
    }

    @ReactMethod fun getPeerSnapshots(promise: Promise) = guard(promise) {
        val peers = mesh.getPeerNicknames().keys.toList()
        val rssi = runCatching { mesh.getPeerRSSI() }.getOrDefault(emptyMap())
        val encrypted = runCatching { mesh.getEncryptedPeers().toSet() }.getOrDefault(emptySet())
        val arr: WritableArray = Arguments.createArray()
        peers.forEach { peerID ->
            val info = runCatching { mesh.getPeerInfo(peerID) }.getOrNull() ?: return@forEach
            val fp = runCatching { mesh.getPeerFingerprint(peerID) }.getOrNull()
            arr.pushMap(
                MeshSdkMapper.peerToMap(info, rssi[peerID], fp, encrypted.contains(peerID))
            )
        }
        arr
    }

    @ReactMethod fun getPeerFingerprint(peerID: String, promise: Promise) = guard(promise) {
        mesh.getPeerFingerprint(peerID)
    }

    @ReactMethod fun isPeerConnected(peerID: String, promise: Promise) = guard(promise) {
        mesh.getPeerInfo(peerID)?.isConnected ?: false
    }

    // =====================================================================
    // Noise / encryption
    // =====================================================================

    @ReactMethod fun hasEstablishedSession(peerID: String, promise: Promise) = guard(promise) {
        mesh.hasEstablishedSession(peerID)
    }

    @ReactMethod fun getSessionState(peerID: String, promise: Promise) = guard(promise) {
        when (mesh.getSessionState(peerID)) {
            is NoiseSession.NoiseSessionState.Uninitialized -> "none"
            is NoiseSession.NoiseSessionState.Handshaking -> "handshaking"
            is NoiseSession.NoiseSessionState.Established -> "established"
            is NoiseSession.NoiseSessionState.Failed -> "failed"
        }
    }

    @ReactMethod fun initiateNoiseHandshake(peerID: String, promise: Promise) = guard(promise) {
        mesh.initiateNoiseHandshake(peerID); null
    }

    @ReactMethod fun shouldShowEncryptionIcon(peerID: String, promise: Promise) = guard(promise) {
        mesh.shouldShowEncryptionIcon(peerID)
    }

    @ReactMethod fun getEncryptedPeers(promise: Promise) = guard(promise) {
        MeshSdkMapper.stringListToArray(mesh.getEncryptedPeers())
    }

    // =====================================================================
    // QR verification
    // =====================================================================

    @ReactMethod
    fun sendVerifyChallenge(peerID: String, noiseKeyHex: String, nonceABase64: String, promise: Promise) =
        guard(promise) {
            mesh.sendVerifyChallenge(peerID, noiseKeyHex, Base64.decode(nonceABase64, Base64.DEFAULT)); null
        }

    @ReactMethod
    fun sendVerifyResponse(peerID: String, noiseKeyHex: String, nonceABase64: String, promise: Promise) =
        guard(promise) {
            mesh.sendVerifyResponse(peerID, noiseKeyHex, Base64.decode(nonceABase64, Base64.DEFAULT)); null
        }

    // =====================================================================
    // Diagnostics
    // =====================================================================

    @ReactMethod fun getDebugStatus(promise: Promise) = guard(promise) { mesh.getDebugStatus() }

    @ReactMethod fun clearAllInternalData(promise: Promise) = guard(promise) {
        mesh.clearAllInternalData(); null
    }

    @ReactMethod fun clearAllEncryptionData(promise: Promise) = guard(promise) {
        mesh.clearAllEncryptionData(); null
    }

    // ---- helpers ------------------------------------------------------------

    private fun ReadableArray.toStringList(): List<String> =
        (0 until size()).mapNotNull { getString(it) }

    /** Runs [block] guarding against exceptions, resolving/rejecting the promise. */
    private inline fun guard(promise: Promise, block: () -> Any?) {
        try {
            promise.resolve(block())
        } catch (e: Throwable) {
            promise.reject("mesh_error", e.message, e)
        }
    }
}
