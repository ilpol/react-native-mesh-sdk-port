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
- **Local notifications** for incoming private messages, driving Core BitChat's
  own notification manager. New APIs:
  - `setNotificationsEnabled(enabled)` — on/off toggle (default on).
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
