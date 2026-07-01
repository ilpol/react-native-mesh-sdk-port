import React from 'react';
import { StyleSheet, Text, View } from 'react-native';
import type { MeshMessage } from 'react-native-mesh-sdk';
import { theme } from '../theme';

function statusGlyph(m: MeshMessage): string {
  switch (m.deliveryStatus?.kind) {
    case 'sending': return '○';
    case 'sent': return '✓';
    case 'delivered': return '✓✓';
    case 'read': return '✓✓✓';
    case 'failed': return '✗';
    case 'partiallyDelivered': return `✓ ${m.deliveryStatus.reached}/${m.deliveryStatus.total}`;
    default: return '';
  }
}

function time(ts: number): string {
  const d = new Date(ts);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

export const MessageBubble = React.memo(function MessageBubble({
  message,
  mine,
}: {
  message: MeshMessage;
  mine: boolean;
}) {
  return (
    <View style={[styles.row, mine ? styles.rowMine : styles.rowOther]}>
      <View style={[styles.bubble, mine ? styles.bubbleMine : styles.bubbleOther]}>
        {!mine && <Text style={styles.sender}>@{message.sender}</Text>}
        <Text style={styles.content}>{message.content}</Text>
        <View style={styles.meta}>
          {message.isEncrypted && <Text style={styles.lock}>🔒 </Text>}
          <Text style={styles.metaText}>{time(message.timestamp)}</Text>
          {mine && <Text style={styles.status}> {statusGlyph(message)}</Text>}
        </View>
      </View>
    </View>
  );
});

const styles = StyleSheet.create({
  row: { paddingHorizontal: 12, marginVertical: 3 },
  rowMine: { alignItems: 'flex-end' },
  rowOther: { alignItems: 'flex-start' },
  bubble: { maxWidth: '82%', borderRadius: 10, paddingVertical: 6, paddingHorizontal: 10, borderWidth: 1 },
  bubbleMine: { backgroundColor: theme.bubbleMine, borderColor: theme.textDim },
  bubbleOther: { backgroundColor: theme.bubbleOther, borderColor: theme.border },
  sender: { color: theme.textDim, fontSize: 11, fontFamily: theme.mono, marginBottom: 2 },
  content: { color: theme.text, fontSize: 14, fontFamily: theme.mono },
  meta: { flexDirection: 'row', alignItems: 'center', justifyContent: 'flex-end', marginTop: 3 },
  metaText: { color: theme.textMuted, fontSize: 10, fontFamily: theme.mono },
  status: { color: theme.textDim, fontSize: 10, fontFamily: theme.mono },
  lock: { fontSize: 10 },
});
