# Changelog

All notable changes to `react-native-mesh-sdk` are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## 1.3.0

### Added
- **Background operation (Android).** `startServices()` now starts a foreground
  service that keeps the BLE mesh alive when the app is backgrounded; it is
  reused across the process via `MeshServiceHolder` and stopped by
  `stopServices()`. The manifest ships the `FOREGROUND_SERVICE*` permissions and
  the service declaration.
- **Local notifications** for incoming messages, driving Core BitChat's own
  notification manager. New APIs:
  - `setNotificationsEnabled(enabled)` — DM notifications on/off (default on).
  - `setPublicNotificationsEnabled(enabled)` — public-broadcast notifications
    on/off (default **off** — a busy mesh can be noisy).
  - `setActiveChatPeer(peerID | null)` — suppress notifications for the chat
    currently on screen.
- **Bluetooth adapter control.** Android now emits `onBluetoothStateChange`
  (previously iOS-only). New APIs:
  - `getBluetoothState()` — current adapter state.
  - `enableBluetooth()` — Android shows the system enable dialog; iOS opens
    Settings (it cannot toggle Bluetooth programmatically).

### Fixed
- **Crash on Android 14+ (`targetSdk` 34+)** after starting services: the
  internal Bluetooth-state receiver is now registered with
  `ContextCompat.RECEIVER_NOT_EXPORTED`, as required by API 34+
  (`registerReceiver` without an export flag threw `SecurityException`).
- **iOS: messages received while backgrounded were lost.** The JS runtime is
  suspended in the background, Core iOS keeps no history, and iOS often terminates
  a backgrounded BLE app — so the `onMessage` event was dropped. Incoming messages
  are now persisted natively to disk as they arrive (BLE wakes the app, so native
  code runs even while JS is suspended) and replayed once JS is listening again —
  on return to foreground **or on the next cold launch** (deduped by id). Messages
  sent to a backgrounded/terminated iPhone now appear when the app is reopened,
  matching Android. The native buffer emits live first and only persists
  property-list-safe fields, so it can never crash the app (an earlier build
  could crash persisting a private message whose optional `recipientNickname`
  was nil, which destabilized sessions).

### Notes
- Message history is still **not** persisted by the SDK — Core BitChat is
  ephemeral by design. Persist in your app if needed (see the example app).

## 1.2.0
- Mesh identity is configurable from the app via `setMeshId(service, characteristic)`,
  so each deployment can run its own private, isolated BLE network.

## 1.1.1
- Fixed autolinking for consumers: `react-native.config.js` is now included in
  the published `files`.

## 1.0.0
- Initial public release: offline BLE mesh (multi-hop relay), Noise-encrypted
  private messages, public broadcast, peer list, delivery/read receipts.
  Full BitChat cores (Android + iOS) vendored verbatim behind a thin wrapper.
