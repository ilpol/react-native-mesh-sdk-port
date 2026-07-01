# react-native-mesh-sdk

Bluetooth-mesh messaging for React Native — chat over BLE with **no internet**,
ported from the native [BitChat](https://github.com/permissionlesstech) cores
for Android and iOS.

The library deliberately keeps a hard line between **our code** and **Core
BitChat**: we never modify the upstream classes, we only wrap their *public*
interfaces. Pulling a new BitChat release is a single `npm run sync-core`.

## Architecture

```
┌─────────────────────┐
│  React Native App    │   example/ (chat UI like the native apps)
└──────────┬──────────┘
           │  import { MeshSdk } from 'react-native-mesh-sdk'
┌──────────▼──────────┐
│  NPM Module (TS)     │   src/  — typed facade + NativeEventEmitter
└──────────┬──────────┘
           │  NativeModules.MeshSdk  (bridge / TurboModule-ready)
┌──────────▼──────────┐
│  Native SDK          │   android/src + ios/MeshSdk.*  ← THE ONLY GLUE WE OWN
│  (thin wrapper)      │
└──────────┬──────────┘
           │  public MeshService (Android) / Transport (iOS)
┌──────────▼──────────┐
│  Core BitChat        │   android/core + ios/core  ← VENDORED VERBATIM
│  (unchanged)         │
└─────────────────────┘
```

**All of our changes live in the top wrapper layer.** As long as the public
interface of Core BitChat
([`MeshService`](android/core/com/bitchat/android/mesh/MeshService.kt) /
[`Transport`](ios/core/bitchat/Services/Transport.swift)) doesn't change, an
upstream update is a pure file copy.

## Layout

| Path | What it is | Who maintains it |
|------|-----------|------------------|
| `src/` | TS interface — `MeshSdk` facade, types, native spec | us |
| `android/src/main/java/com/meshsdk/` | Android Native SDK wrapper (`MeshSdkModule` ⟶ `UnifiedMeshService`, implements `MeshDelegate`) | us |
| `ios/MeshSdk.swift`, `ios/MeshSdk.m` | iOS Native SDK wrapper (wraps `BLEService`/`Transport`, implements `BitchatDelegate`) | us |
| `android/core/` | `com.bitchat.android.*` copied as-is | **upstream — do not edit** |
| `ios/core/` | BitChat services/protocols/models + `localPackages` copied as-is | **upstream — do not edit** |
| `scripts/sync-core.sh` | Re-vendors both cores | us |
| `example/` | Reference RN app with BitChat-like UX | us |

## Keeping Core BitChat up to date

```bash
# repos are expected next to this package by default
ANDROID_SRC=../bitchat-android IOS_SRC=../bitchat-ios npm run sync-core
```

This copies the entire `com.bitchat.android` tree into `android/core`, and the
BitChat service/protocol/model layers + `localPackages` into `ios/core`. Then
rebuild. If the wrapper fails to compile after a sync, the public
`MeshService`/`Transport` surface changed — adjust **only** the wrapper.

## Install (in a host app)

```bash
npm install react-native-mesh-sdk
cd ios && pod install   # iOS
```

Android & iOS autolinking register the module automatically (RN ≥ 0.60).

### Permissions

**Android** (`AndroidManifest.xml` perms ship with the library; request at
runtime — see `example/src/useMesh.ts`):
`BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT` (and
`ACCESS_FINE_LOCATION` on API < 31).

**iOS** (`Info.plist`):

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Used to form an offline Bluetooth mesh.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Used to form an offline Bluetooth mesh.</string>
```

### iOS integration

bitchat-ios is a SwiftPM codebase whose Core symbols are `internal` and which
depends on SwiftPM packages. Swift modules can't be merged the way Kotlin
packages can, so — unlike Android (a Gradle library) — the iOS Core + the RN
bridge compile **into the app target** (one module), and the dependencies are
added as SwiftPM packages. This is scripted:

```bash
cd example
npm run setup-ios   # = pod install  +  ruby ../scripts/setup-ios.rb
```

`scripts/setup-ios.rb` (uses the `xcodeproj` gem that ships with CocoaPods):
- adds the whole vendored Core (`ios/core/bitchat/**`) + the bridge
  (`ios/MeshSdk.swift`, `ios/MeshSdk.m`, `ios/MeshSdkShims.swift`) to the app target;
- adds the SwiftPM packages: **local** `BitFoundation`, `BitLogger`, `Tor`
  (Arti, incl. its prebuilt `arti.xcframework`) from `ios/core/localPackages`,
  and **remote** `P256K` (`swift-secp256k1` @ 0.21.1);
- sets deployment target 16.0 (bitchat-ios's minimum) and `SWIFT_VERSION`.

Because of this, iOS is **not** autolinked as a pod (`react-native.config.js`
sets `ios: null`); the bridge registers via `RCT_EXTERN_MODULE` from the app target.

Notes:
- **Simulator builds must be arm64** (Apple Silicon) — Arti's xcframework ships
  an arm64 simulator slice, not x86_64. Device builds use its `ios-arm64` slice.
- `MeshSdkShims.swift` reproduces the few symbols from the un-vendored
  `BitchatApp.swift` that the Core still references (`NotificationDelegate`,
  `BitchatApp.bundleID/groupID`) — wrapper code, not a Core edit.
- Re-run `npm run setup-ios` after every `npm run sync-core`.
- CocoaPods needs a UTF-8 locale (`LANG=en_US.UTF-8`) or it crashes on
  `ASCII-8BIT`; the npm scripts set it for you.

## Usage

```ts
import { MeshSdk } from 'react-native-mesh-sdk';

await MeshSdk.setNickname('alice');
await MeshSdk.startServices();

const sub = MeshSdk.onMessage((msg) => {
  console.log(`${msg.sender}: ${msg.content}`);
});

MeshSdk.onPeerSnapshotsUpdate((peers) => console.log('peers', peers));

await MeshSdk.sendMessage('hello mesh');                       // broadcast
await MeshSdk.sendPrivateMessage('hi', peerID, 'bob');         // E2E encrypted

sub.remove();
await MeshSdk.stopServices();
```

See [`src/MeshSdk.ts`](src/MeshSdk.ts) for the full API and
[`src/types.ts`](src/types.ts) for the data model.

## Example app

A BitChat-style client (nickname onboarding, public mesh chat, peer drawer,
private E2E conversations, delivery receipts) lives in [`example/`](example/).

```bash
cd example
npm install
npm run ios      # or: npm run android
```

## License

MIT for the wrapper layer. Core BitChat retains its upstream license.
