package com.meshsdk

import com.bitchat.android.model.BitchatMessage
import com.bitchat.android.model.BitchatMessageType
import com.bitchat.android.model.DeliveryStatus
import com.bitchat.android.mesh.PeerInfo
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableArray
import com.facebook.react.bridge.WritableMap

/**
 * Pure, one-way conversions from Core BitChat models → React Native bridge
 * structures (WritableMap/WritableArray).
 *
 * This is the *only* place that knows the shape of both sides, keeping the
 * module body free of mapping noise. Field names match the TS `types.ts`
 * exactly so the contract is verifiable across layers.
 *
 * NOTE: Nothing here mutates Core BitChat — it only reads its public fields.
 */
object MeshSdkMapper {

    fun messageTypeToString(type: BitchatMessageType): String = when (type) {
        BitchatMessageType.Message -> "message"
        BitchatMessageType.Audio -> "audio"
        BitchatMessageType.Image -> "image"
        BitchatMessageType.File -> "file"
    }

    fun deliveryStatusToMap(status: DeliveryStatus?): WritableMap? {
        if (status == null) return null
        val map = Arguments.createMap()
        when (status) {
            is DeliveryStatus.Sending -> map.putString("kind", "sending")
            is DeliveryStatus.Sent -> map.putString("kind", "sent")
            is DeliveryStatus.Delivered -> {
                map.putString("kind", "delivered")
                map.putString("to", status.to)
                map.putDouble("at", status.at.time.toDouble())
            }
            is DeliveryStatus.Read -> {
                map.putString("kind", "read")
                map.putString("by", status.by)
                map.putDouble("at", status.at.time.toDouble())
            }
            is DeliveryStatus.Failed -> {
                map.putString("kind", "failed")
                map.putString("reason", status.reason)
            }
            is DeliveryStatus.PartiallyDelivered -> {
                map.putString("kind", "partiallyDelivered")
                map.putInt("reached", status.reached)
                map.putInt("total", status.total)
            }
        }
        return map
    }

    fun messageToMap(message: BitchatMessage): WritableMap {
        val map = Arguments.createMap()
        map.putString("id", message.id)
        map.putString("sender", message.sender)
        map.putString("content", message.content)
        map.putString("type", messageTypeToString(message.type))
        map.putDouble("timestamp", message.timestamp.time.toDouble())
        map.putBoolean("isRelay", message.isRelay)
        map.putString("originalSender", message.originalSender)
        map.putBoolean("isPrivate", message.isPrivate)
        map.putString("recipientNickname", message.recipientNickname)
        map.putString("senderPeerID", message.senderPeerID)
        map.putString("channel", message.channel)
        map.putBoolean("isEncrypted", message.isEncrypted)

        val mentions = message.mentions
        if (mentions != null) {
            val arr: WritableArray = Arguments.createArray()
            mentions.forEach { arr.pushString(it) }
            map.putArray("mentions", arr)
        }

        deliveryStatusToMap(message.deliveryStatus)?.let { map.putMap("deliveryStatus", it) }
        return map
    }

    fun stringMapToWritable(src: Map<String, String>): WritableMap {
        val map = Arguments.createMap()
        src.forEach { (k, v) -> map.putString(k, v) }
        return map
    }

    fun intMapToWritable(src: Map<String, Int>): WritableMap {
        val map = Arguments.createMap()
        src.forEach { (k, v) -> map.putInt(k, v) }
        return map
    }

    fun stringListToArray(src: List<String>): WritableArray {
        val arr = Arguments.createArray()
        src.forEach { arr.pushString(it) }
        return arr
    }

    fun bytesToHex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it) }

    /**
     * Builds a rich peer snapshot from the public [PeerInfo] plus transport
     * lookups (fingerprint / rssi / encryption) resolved by the caller.
     */
    fun peerToMap(
        info: PeerInfo,
        rssi: Int?,
        fingerprint: String?,
        isEncrypted: Boolean
    ): WritableMap {
        val map = Arguments.createMap()
        map.putString("peerID", info.id)
        map.putString("nickname", info.nickname)
        map.putBoolean("isConnected", info.isConnected)
        if (rssi != null) map.putInt("rssi", rssi) else map.putNull("rssi")
        map.putString("fingerprint", fingerprint)
        map.putBoolean("isEncrypted", isEncrypted)
        map.putString("noisePublicKeyHex", info.noisePublicKey?.let { bytesToHex(it) })
        map.putDouble("lastSeen", info.lastSeen.toDouble())
        return map
    }
}
