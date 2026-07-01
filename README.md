# react-native-mesh-sdk

Bluetooth‑mesh messaging for React Native — chat over BLE with **no internet**,
ported from the native [BitChat](https://github.com/permissionlesstech) cores for
Android and iOS.

- 📡 **Offline mesh** over Bluetooth LE (multi‑hop relay)
- 🔒 **End‑to‑end encrypted** private messages (Noise protocol)
- 📢 **Public broadcast** channel to all nearby peers
- 👥 Live **peer list** with nicknames, RSSI and encryption state
- ✅ Delivery / read receipts
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
Bluetooth/location permissions; request them at runtime (see the example's
`useMesh.ts`). Core BitChat requires, on **all** API levels:

`BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`,
`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`.

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

await MeshSdk.setNickname('alice');
await MeshSdk.startServices();

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

## Keeping Core BitChat up to date

```bash
# bitchat-android / bitchat-ios expected as siblings by default
ANDROID_SRC=../bitchat-android IOS_SRC=../bitchat-ios npm run sync-core
```

This re‑vendors the full `com.bitchat.android` tree (+ Arti JNI, resources,
`jniLibs`) into `android/src/main/java`, precompiles the southernstorm Noise
library to `android/libs`, and copies the bitchat‑ios sources into `ios/bitchat`
+ `ios/localPackages`. Then rebuild (and re‑run `setup-ios.rb` for iOS). If the wrapper
stops compiling, the public core surface changed — fix **only** the wrapper.

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
