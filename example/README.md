# Mesh Chat — example app

A BitChat-style React Native client built entirely on `react-native-mesh-sdk`.
It demonstrates the same core UX as the native bitchat-android / bitchat-ios
apps:

- **Nickname onboarding** before joining the mesh
- **Public mesh chat** — broadcast messages to every nearby peer
- **Peer drawer** — live peer list with connection dot, 🔒 encryption badge, RSSI
- **Private chats** — tap a peer for an end-to-end (Noise) encrypted conversation
- **Delivery receipts** — sending / sent / delivered / read glyphs

The meaningful code is cross-platform TypeScript:

| File | Role |
|------|------|
| `App.tsx` | Onboarding + chat shell |
| `src/useMesh.ts` | The single hook driving the mesh (BitChat's `ChatViewModel` equivalent) |
| `src/components/*` | `MessageBubble`, `MessageInput`, `PeerList` |

## Run

This folder only contains the JS/TS app + config. Generate the native
iOS/Android host projects once, then autolinking wires up the SDK:

```bash
# from example/
npm install

# iOS — pod install + wire the Core & SwiftPM packages into the app target
npm run setup-ios
npm run ios        # simulator build must be arm64 (Apple Silicon)

# Android
npm run android
```

> iOS build details (SwiftPM packages, arm64-only simulator, bundle id, Xcode-26
> debug dylib) are documented in the top-level [README](../README.md#ios-integration).
> Re-run `npm run setup-ios` after any `npm run sync-core`.

> The example consumes the library straight from `..`: `react-native.config.js`
> points **autolinking** at the parent, and `metro.config.js` points **Metro**
> there (and excludes the vendored `android/core` + `ios/core` from the file
> map). So edits to the SDK hot-reload here — no publish / npm link needed.

### Android Studio can't find `node` (nvm users)

If the IDE build fails with `A problem occurred starting process 'command 'node''`
/ `Cannot run program "node"`, it's because Android Studio (launched from the
Dock) gets a minimal `PATH` from `launchd` (`/usr/bin:/bin:/usr/sbin:/sbin`)
that excludes nvm's node. RN's autolinking (`native_modules.gradle`) calls
`node` by bare name, so it must be on the **GUI** `PATH`. Note: `/etc/paths`
(incl. `/usr/local/bin`) only affects *shells*, not GUI apps — so a symlink
alone isn't enough.

**Option A — permanent, works from the Dock (recommended).** Symlink node into
`/usr/local/bin`, then add that dir to the launchd GUI PATH and reboot:

```bash
sudo ln -sf "$(which node)" /usr/local/bin/node
sudo ln -sf "$(which npm)"  /usr/local/bin/npm
sudo launchctl config user path "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# → reboot, then Sync in Android Studio
```

**Option B — no reboot.** Quit Android Studio, then launch its binary from a
terminal that has node on `PATH` (the Gradle daemon inherits that env):

```bash
cd android && JAVA_HOME="$(/usr/libexec/java_home -v 17)" ./gradlew --stop
source ~/.zshrc
"/Applications/Android Studio.app/Contents/MacOS/studio" >/dev/null 2>&1 &
```

> `open -a "Android Studio"` does NOT pass the env — launch the binary directly.
> Re-run the node symlink if you switch node versions with nvm. CLI builds via
> `npm run android` already work (the terminal has nvm on `PATH`).

### Metro / watchman note

On macOS, Metro needs **watchman** (`brew install watchman`); without it the
bundler throws `EMFILE: too many open files`. If watchman fails to start with a
`~/.local/state/watchman … Permission denied` error (that dir is root-owned on
some machines), either:

```bash
sudo chown -R "$USER" ~/.local/state           # one-time fix, or
export XDG_STATE_HOME=/tmp/wm                   # per-shell redirect
```

## Native setup checklist

**iOS** — add to `ios/MeshChatExample/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Mesh Chat uses Bluetooth to talk to nearby devices offline.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Mesh Chat uses Bluetooth to talk to nearby devices offline.</string>
<key>UIBackgroundModes</key>
<array><string>bluetooth-central</string><string>bluetooth-peripheral</string></array>
```

Also add the vendored SwiftPM packages from `../ios/core/localPackages`
(`BitFoundation`, `BitLogger`) to the app target.

**Android** — runtime permissions are requested by `useMesh.ts`; the manifest
permissions are provided by the library and merged automatically. `minSdk 26+`.

> Bluetooth mesh needs **two physical devices** — the simulator/emulator has no
> BLE radio.
