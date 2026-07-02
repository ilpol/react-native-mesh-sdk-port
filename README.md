# react-native-mesh-sdk

Bluetooth‑mesh messaging for React Native — chat over BLE with **no internet**,
ported from the native [BitChat](https://github.com/permissionlesstech) cores for
Android and iOS.

- 📡 **Offline mesh** over Bluetooth LE (multi‑hop relay)
- 🔒 **End‑to‑end encrypted** private messages (Noise protocol)
- 📢 **Public broadcast** channel to all nearby peers
- 👥 Live **peer list** with nicknames, RSSI and encryption state
- ✅ Delivery / read receipts
- 🆔 **Private network** — override the BLE service/characteristic UUIDs so your
  app forms its own mesh, isolated from other deployments (`setMeshId`)
- 🔋 **Background operation** (Android) — a foreground service keeps the mesh
  alive when the app is backgrounded
- 🔔 **Local notifications** for incoming private messages, with an on/off toggle
- 📶 **Bluetooth state** events + a helper to prompt the user to enable Bluetooth
- 🧩 The full BitChat core is **vendored verbatim** — updating to a new BitChat
  release is a single `npm run sync-core`, no forking of upstream classes.

> The library keeps a hard line between **our wrapper code** and **Core BitChat**:
> we never edit the upstream classes, we only wrap their *public* interfaces
> (`MeshService` on Android, `Transport` on iOS).

## Requirements

| | Minimum |
|---|---|
| React Native | 0.74 |
| Android | `minSdk 26`, JDK 17, AGP 8.6 / Gradle 8.8, Kotlin 2.0.21 |
| iOS | 16.0, Xcode 16+ |

Bluetooth mesh needs **two physical devices** — simulators/emulators have no BLE radio.

## Install

```bash
npm install react-native-mesh-sdk
```

### Android (autolinked)

Nothing to wire up — the module autolinks. The library ships the required
Bluetooth/location/foreground‑service permissions and the background service
declaration; request the runtime ones at startup (see the example's
`useMesh.ts`). Core BitChat requires, on **all** API levels:

`BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`,
`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`.

For background operation + notifications the manifest also declares
`FOREGROUND_SERVICE(_CONNECTED_DEVICE|_DATA_SYNC|_LOCATION)` and, on Android 13+,
`POST_NOTIFICATIONS` — request `POST_NOTIFICATIONS` at runtime to get the
background‑service and message notifications (the mesh still runs without it).

### iOS (scripted — not a CocoaPods autolink)

Because bitchat‑ios is a SwiftPM codebase whose Core symbols are `internal` and
which depends on SwiftPM packages, the Core + the RN bridge must compile **into
the app target** (Swift modules can't be merged the way Kotlin packages can). A
script wires this into your Xcode project:

```bash
# from your app folder, with react-native-mesh-sdk installed
ruby node_modules/react-native-mesh-sdk/scripts/setup-ios.rb ios/YourApp.xcodeproj
cd ios && pod install
```

`setup-ios.rb` (uses the `xcodeproj` gem bundled with CocoaPods):
- adds the vendored Core + the bridge (`MeshSdk.swift/.m`, `MeshSdkShims.swift`)
  to the app target;
- adds the SwiftPM packages — local `BitFoundation`, `BitLogger`, `Tor` (Arti,
  incl. its prebuilt `arti.xcframework`) and remote `P256K` (`swift-secp256k1`);
- sets deployment target 16.0 and `SWIFT_VERSION`.

Add to `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Used to form an offline Bluetooth mesh.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Used to form an offline Bluetooth mesh.</string>
<key>UIBackgroundModes</key>
<array><string>bluetooth-central</string><string>bluetooth-peripheral</string></array>
```

Notes: iOS **simulator builds must be arm64** (Arti ships an arm64‑sim slice, not
x86_64). Re‑run `setup-ios.rb` after every `npm run sync-core`.

## Usage

```ts
import { MeshSdk } from 'react-native-mesh-sdk';

// Optional: form your OWN private mesh (must match on every device, call BEFORE
// startServices). Omit to use the SDK default network.
await MeshSdk.setMeshId(
  '4D455348-0000-4000-8000-00000000C0DE', // service UUID
  '4D455348-0000-4000-8000-00000000DA7A', // characteristic UUID
);

await MeshSdk.setNickname('alice');
await MeshSdk.setNotificationsEnabled(true);   // local DM notifications (default on)
await MeshSdk.startServices();                 // also starts the Android background service

const sub = MeshSdk.onMessage((msg) => {
  console.log(`${msg.sender}: ${msg.content}`);
});
MeshSdk.onPeerSnapshotsUpdate((peers) => console.log('peers', peers));

await MeshSdk.sendMessage('hello mesh');                 // public broadcast
await MeshSdk.sendPrivateMessage('hi', peerID, 'bob');   // E2E encrypted (session ensured by the SDK)

// later
sub.remove();
await MeshSdk.stopServices();
```

### Bluetooth state & notifications

```ts
// Prompt the user to turn Bluetooth on when it's off.
MeshSdk.addListener('onBluetoothStateChange', ({ state }) => {
  if (state === 'poweredOff') MeshSdk.enableBluetooth();  // Android: system dialog; iOS: opens Settings
});

// Suppress notifications for the chat that's currently on screen
// (null = public feed / none). Toggle notifications at any time.
await MeshSdk.setActiveChatPeer(peerID);
await MeshSdk.setNotificationsEnabled(false);         // DMs (default on)
await MeshSdk.setPublicNotificationsEnabled(true);    // public broadcasts (default off)
```

DM notifications fire when the app is backgrounded, or foregrounded but not
viewing that chat; public-broadcast notifications are **off by default** and, when
enabled, follow the same gating (never while the public feed is on screen). On
Android, if the app is fully killed the background service keeps the mesh alive
and shows the DM notification itself. **History is not
persisted by the SDK** (Core BitChat is ephemeral by design) — persist messages
in your app if you need them across restarts; see the example's `useMesh.ts`.

Full API in [`src/MeshSdk.ts`](src/MeshSdk.ts); data model in
[`src/types.ts`](src/types.ts).

## Architecture

```
React Native App
   │  import { MeshSdk } from 'react-native-mesh-sdk'
NPM module (TS)          src/            — typed facade + NativeEventEmitter
   │  NativeModules.MeshSdk (bridge)
Native SDK (wrapper)     android/src/main/java/com/meshsdk/ · ios/MeshSdk.*   ← the only glue we own
   │  public MeshService (Android) / Transport (iOS)
Core BitChat (vendored)  android/src/main/java/{com/bitchat,info,org} · ios/{bitchat,localPackages}   ← copied verbatim
```

All of our code lives in the wrapper layer. As long as the public
`MeshService` / `Transport` surface is unchanged, an upstream BitChat update is a
pure file copy.

## Keeping Core BitChat up to date (`sync-core.sh`)

The Core BitChat sources are **vendored** into this package rather than pulled as
a dependency. `scripts/sync-core.sh` (exposed as `npm run sync-core`) re‑vendors
them from the upstream repos, so pulling a new BitChat release is a re‑run + a
rebuild — **you never hand‑edit Core**.

```bash
# bitchat-android / bitchat-ios expected as siblings of this package by default;
# override with ANDROID_SRC / IOS_SRC.
ANDROID_SRC=../bitchat-android IOS_SRC=../bitchat-ios npm run sync-core
```

**What it does**

- **Android** — copies the whole `com.bitchat.android` tree (+ the Arti/Tor JNI
  bindings under `info.guardianproject` / `org.torproject`, `res/`, `assets/`,
  `jniLibs/`) into `android/src/main/java`. It then:
  - precompiles the Java‑only southernstorm Noise library to
    `android/libs/southernstorm-noise.jar` (Kotlin 2.0.x — the max RNGP 0.74
    allows — can't resolve it from mixed sources) and drops the sources;
  - prunes the `values-<lang>` string translations (the RN host provides the UI).
- **iOS** — copies the whole `bitchat/` source tree into `ios/bitchat` and the
  local Swift packages (BitFoundation, BitLogger, Tor/Arti incl. its prebuilt
  `arti.xcframework`) into `ios/localPackages`. It prunes app‑shell bits that
  can't compile into the RN app target (`BitchatApp.swift`, `Assets.xcassets`,
  `Info.plist`, `*.entitlements`, storyboards, …).

**Patch applied on top (the only deviation from verbatim)**

Everything else is copied byte‑for‑byte; this is re‑applied by the script on
every sync so upstream stays pristine and updates keep flowing in:

- `patch_mesh_uuid_mutability` — makes the BLE service/characteristic UUID
  constants mutable (`val`→`var` on Android; collapse `#if`/`let`→`static var`
  on iOS) so the wrapper can inject the mesh identity via `setMeshId()`.

After a sync, **rebuild**; for iOS also re‑run `ruby scripts/setup-ios.rb`. If the
wrapper stops compiling, the public Core surface (`MeshService` / `Transport`)
changed upstream — fix **only** the wrapper, never Core.

## Example app

A full BitChat‑style client (nickname onboarding, public mesh chat, peer drawer,
private E2E chats, delivery receipts) that consumes this package from npm lives
in its own repo:

**https://github.com/ilpol/react-native-mesh-sdk-port-example**

```bash
git clone https://github.com/ilpol/react-native-mesh-sdk-port-example
cd react-native-mesh-sdk-port-example
npm install
npm run android          # or: npm run setup-ios && npm run ios
```

## License

MIT for the wrapper layer. Core BitChat retains its upstream license.
