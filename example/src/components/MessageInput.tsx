import React, { useState } from 'react';
import { StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import { theme } from '../theme';

export function MessageInput({
  placeholder,
  onSend,
}: {
  placeholder: string;
  onSend: (text: string) => void;
}) {
  const [text, setText] = useState('');
  const submit = () => {
    if (!text.trim()) return;
    onSend(text);
    setText('');
  };
  return (
    <View style={styles.wrap}>
      <Text style={styles.prompt}>{'>'}</Text>
      <TextInput
        style={styles.input}
        value={text}
        onChangeText={setText}
        placeholder={placeholder}
        placeholderTextColor={theme.textMuted}
        onSubmitEditing={submit}
        returnKeyType="send"
        autoCapitalize="none"
        autoCorrect={false}
      />
      <TouchableOpacity style={styles.button} onPress={submit}>
        <Text style={styles.buttonText}>send</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    flexDirection: 'row',
    alignItems: 'center',
    borderTopWidth: 1,
    borderTopColor: theme.border,
    paddingHorizontal: 10,
    paddingTop: 8,
    // Lift the input field higher off the bottom edge.
    paddingBottom: 28,
    backgroundColor: theme.surface,
  },
  prompt: { color: theme.accent, fontFamily: theme.mono, marginRight: 6, fontSize: 16 },
  input: { flex: 1, color: theme.text, fontFamily: theme.mono, fontSize: 14, paddingVertical: 4 },
  button: { paddingHorizontal: 12, paddingVertical: 6, borderWidth: 1, borderColor: theme.accent, borderRadius: 6 },
  buttonText: { color: theme.accent, fontFamily: theme.mono, fontSize: 13 },
});
