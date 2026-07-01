import { useCallback, useEffect, useRef, useState } from 'react';
import { Platform, PermissionsAndroid } from 'react-native';
import {
  MeshSdk,
  type MeshMessage,
  type MeshPeer,
  type BluetoothState,
} from 'react-native-mesh-sdk';

/**
 * Requests the runtime Bluetooth/location permissions Core BitChat needs.
 * No-op on iOS (handled via Info.plist usage strings + system prompt).
 */
async function ensurePermissions(): Promise<boolean> {
  if (Platform.OS !== 'android') return true;
  const api =
    typeof Platform.Version === 'number'
      ? Platform.Version
      : parseInt(String(Platform.Version), 10);
  const P = PermissionsAndroid.PERMISSIONS;

  // Core BitChat's BluetoothPermissionManager requires ACCESS_FINE +
  // COARSE_LOCATION on ALL API levels (plus the BLE runtime perms on 31+).
  // If location isn't granted the core reports "Has Permissions: false" and the
  // mesh never starts — so we must request location even on Android 12+.
  const required: string[] = [
    P.ACCESS_FINE_LOCATION,
    P.ACCESS_COARSE_LOCATION,
  ];
  if (api >= 31) {
    required.push(P.BLUETOOTH_SCAN, P.BLUETOOTH_ADVERTISE, P.BLUETOOTH_CONNECT);
  }

  // POST_NOTIFICATIONS (API 33+) is optional — only needed for the background
  // foreground-service notification, not for foreground mesh.
  const optional: string[] =
    api >= 33 && P.POST_NOTIFICATIONS ? [P.POST_NOTIFICATIONS] : [];

  try {
    const res = await PermissionsAndroid.requestMultiple([
      ...required.filter(Boolean),
      ...optional,
    ] as any);
    return required.every((p) => res[p] === PermissionsAndroid.RESULTS.GRANTED);
  } catch {
    return false;
  }
}

export interface MeshState {
  ready: boolean;
  myPeerID: string;
  nickname: string;
  peers: MeshPeer[];
  /** Public broadcast messages, oldest → newest. */
  publicMessages: MeshMessage[];
  /** Private messages keyed by the other peer's id. */
  privateMessages: Record<string, MeshMessage[]>;
  bluetoothState: BluetoothState;
  /** Live diagnostics for troubleshooting the mesh. */
  debug: string;
}

/**
 * The single React hook the example uses to drive the mesh. It mirrors the
 * responsibilities of bitchat's `ChatViewModel`: own the message/peer state,
 * subscribe to transport events, and expose send actions.
 */
export function useMesh(initialNickname: string) {
  const [state, setState] = useState<MeshState>({
    ready: false,
    myPeerID: '',
    nickname: initialNickname,
    peers: [],
    publicMessages: [],
    privateMessages: {},
    bluetoothState: 'unknown',
    debug: 'init…',
  });

  const nicknameRef = useRef(initialNickname);

  const upsertPrivate = useCallback((peerID: string, msg: MeshMessage) => {
    setState((s) => {
      const list = s.privateMessages[peerID] ?? [];
      if (list.some((m) => m.id === msg.id)) return s;
      return { ...s, privateMessages: { ...s.privateMessages, [peerID]: [...list, msg] } };
    });
  }, []);

  // ---- Bootstrap ---------------------------------------------------------
  useEffect(() => {
    let mounted = true;
    const subs = [
      MeshSdk.onMessage((message) => {
        if (message.isPrivate && message.senderPeerID) {
          upsertPrivate(message.senderPeerID, message);
        } else {
          setState((s) =>
            s.publicMessages.some((m) => m.id === message.id)
              ? s
              : { ...s, publicMessages: [...s.publicMessages, message] }
          );
        }
      }),
      MeshSdk.onPeerSnapshotsUpdate((peers) => {
        if (mounted) setState((s) => ({ ...s, peers }));
      }),
      MeshSdk.addListener('onDeliveryStatusUpdate', ({ messageID, status }) => {
        setState((s) => ({
          ...s,
          publicMessages: s.publicMessages.map((m) =>
            m.id === messageID ? { ...m, deliveryStatus: status } : m
          ),
          privateMessages: Object.fromEntries(
            Object.entries(s.privateMessages).map(([k, list]) => [
              k,
              list.map((m) => (m.id === messageID ? { ...m, deliveryStatus: status } : m)),
            ])
          ),
        }));
      }),
      MeshSdk.addListener('onBluetoothStateChange', ({ state: bt }) => {
        setState((s) => ({ ...s, bluetoothState: bt }));
      }),
    ];

    (async () => {
      try {
        const ok = await ensurePermissions();
        if (!ok) {
          if (mounted) setState((s) => ({ ...s, debug: 'PERMISSIONS DENIED' }));
          return;
        }
        await MeshSdk.setNickname(nicknameRef.current);
        await MeshSdk.startServices();
        const myPeerID = await MeshSdk.getMyPeerID();
        const peers = await MeshSdk.getPeers();
        if (mounted) setState((s) => ({ ...s, ready: true, myPeerID, peers, debug: 'services started' }));
      } catch (e) {
        if (mounted) setState((s) => ({ ...s, debug: `START ERROR: ${String(e)}` }));
      }
    })();

    // Poll the Core's own debug status so we can see BLE/peer state without logcat.
    const poll = setInterval(async () => {
      try {
        const [status, peers] = await Promise.all([
          MeshSdk.getDebugStatus(),
          MeshSdk.getPeers(),
        ]);
        if (mounted) setState((s) => ({ ...s, debug: status, peers }));
      } catch (e) {
        if (mounted) setState((s) => ({ ...s, debug: `poll error: ${String(e)}` }));
      }
    }, 3000);

    return () => {
      mounted = false;
      clearInterval(poll);
      subs.forEach((sub) => sub.remove());
      MeshSdk.stopServices();
    };
  }, [upsertPrivate]);

  // ---- Actions -----------------------------------------------------------

  const sendPublic = useCallback(
    async (content: string) => {
      if (!content.trim()) return;
      await MeshSdk.sendMessage(content.trim());
      // Optimistically render our own outgoing message.
      setState((s) => ({
        ...s,
        publicMessages: [
          ...s.publicMessages,
          {
            id: `local-${Date.now()}`,
            sender: s.nickname,
            content: content.trim(),
            type: 'message' as any,
            timestamp: Date.now(),
            isRelay: false,
            isPrivate: false,
            isEncrypted: false,
            senderPeerID: s.myPeerID,
            deliveryStatus: { kind: 'sent' },
          },
        ],
      }));
    },
    []
  );

  const sendPrivate = useCallback(
    async (peerID: string, nickname: string, content: string) => {
      if (!content.trim()) return;
      const id = await MeshSdk.sendPrivateMessage(content.trim(), peerID, nickname);
      upsertPrivate(peerID, {
        id,
        sender: nicknameRef.current,
        content: content.trim(),
        type: 'message' as any,
        timestamp: Date.now(),
        isRelay: false,
        isPrivate: true,
        recipientNickname: nickname,
        senderPeerID: peerID, // bucketed by conversation peer
        isEncrypted: true,
        deliveryStatus: { kind: 'sending' },
      });
    },
    [upsertPrivate]
  );

  const setNickname = useCallback(async (nickname: string) => {
    nicknameRef.current = nickname;
    await MeshSdk.setNickname(nickname);
    setState((s) => ({ ...s, nickname }));
  }, []);

  const markRead = useCallback(async (messageID: string, peerID: string) => {
    await MeshSdk.sendReadReceipt(messageID, peerID, nicknameRef.current);
  }, []);

  return { state, sendPublic, sendPrivate, setNickname, markRead };
}
