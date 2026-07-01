import React from 'react';
import { FlatList, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import type { MeshPeer } from 'react-native-mesh-sdk';
import { theme } from '../theme';

export function PeerList({
  peers,
  onSelectPeer,
  onSelectPublic,
  activePeerID,
}: {
  peers: MeshPeer[];
  onSelectPeer: (peer: MeshPeer) => void;
  onSelectPublic: () => void;
  activePeerID: string | null;
}) {
  return (
    <View style={styles.wrap}>
      <Text style={styles.header}>PEERS · {peers.length}</Text>

      <TouchableOpacity
        style={[styles.item, activePeerID === null && styles.itemActive]}
        onPress={onSelectPublic}
      >
        <Text style={styles.hash}>#</Text>
        <Text style={styles.name}>public mesh</Text>
      </TouchableOpacity>

      <FlatList
        data={peers}
        keyExtractor={(p) => p.peerID}
        renderItem={({ item }) => (
          <TouchableOpacity
            style={[styles.item, activePeerID === item.peerID && styles.itemActive]}
            onPress={() => onSelectPeer(item)}
          >
            <Text style={[styles.dot, { color: item.isConnected ? theme.accent : theme.textMuted }]}>
              ●
            </Text>
            <Text style={styles.name} numberOfLines={1}>
              {item.nickname}
            </Text>
            {item.isEncrypted && <Text style={styles.lock}>🔒</Text>}
            {typeof item.rssi === 'number' && <Text style={styles.rssi}>{item.rssi}dBm</Text>}
          </TouchableOpacity>
        )}
        ListEmptyComponent={<Text style={styles.empty}>scanning for peers…</Text>}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: theme.surface, paddingTop: 8 },
  header: { color: theme.textDim, fontFamily: theme.mono, fontSize: 11, paddingHorizontal: 12, marginBottom: 6 },
  item: { flexDirection: 'row', alignItems: 'center', paddingVertical: 9, paddingHorizontal: 12, gap: 8 },
  itemActive: { backgroundColor: theme.bubbleMine },
  hash: { color: theme.accent, fontFamily: theme.mono, fontSize: 14 },
  dot: { fontSize: 10 },
  name: { color: theme.text, fontFamily: theme.mono, fontSize: 13, flexShrink: 1 },
  lock: { fontSize: 11 },
  rssi: { color: theme.textMuted, fontFamily: theme.mono, fontSize: 10, marginLeft: 'auto' },
  empty: { color: theme.textMuted, fontFamily: theme.mono, fontSize: 12, padding: 12 },
});
