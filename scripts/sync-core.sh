#!/usr/bin/env bash
#
# sync-core.sh — vendor the Core BitChat sources into the Native SDK VERBATIM.
#
# This is the heart of the "drop-in update" promise: we never edit Core BitChat.
# To pull a new upstream release you re-run this script and rebuild. All of our
# own code lives in the wrapper layer (android/src, ios/MeshSdk.*), which only
# depends on the *public* `MeshService` (Android) / `Transport` (iOS) surfaces.
#
# Usage:
#   ANDROID_SRC=../bitchat-android IOS_SRC=../bitchat-ios bash scripts/sync-core.sh
#
# Defaults assume the two upstream repos sit next to this package.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_SRC="${ANDROID_SRC:-$HERE/../bitchat-android}"
IOS_SRC="${IOS_SRC:-$HERE/../bitchat-ios}"

# Vendor the Android core straight into the conventional src/main/java root
# (alongside the com.meshsdk wrapper). This is the only layout where the Kotlin
# compiler reliably picks up the core's mixed .kt + .java sources (e.g. the
# southernstorm Noise library) as Java source roots.
ANDROID_CORE="$HERE/android/src/main/java"
# The iOS vendored core lives flat under ios/ (ios/bitchat + ios/localPackages),
# alongside the wrapper (ios/MeshSdk.*) — mirroring Android, which has no `core`
# folder either. IOS_CORE is the ios/ dir; only bitchat/ + localPackages/ are
# replaced on sync (never the wrapper files at the ios/ root).
IOS_CORE="$HERE/ios"

log() { printf '\033[36m[sync-core]\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# Android: copy the entire com.bitchat.android package tree as-is.
# The wrapper (com.meshsdk) is a sibling package and only touches public APIs,
# so the whole tree can be vendored unchanged (including its internal coupling
# between mesh/ui/crypto/etc.).
# ---------------------------------------------------------------------------
sync_android() {
  local java="$ANDROID_SRC/app/src/main/java"
  if [[ ! -d "$java/com/bitchat/android" ]]; then
    log "SKIP android: $java/com/bitchat/android not found (set ANDROID_SRC)"; return
  fi
  log "Android core <- $java"

  # bitchat-android is NOT cleanly layered: mesh/nostr/services depend on the
  # ui package + app resources + the bundled Tor (arti) JNI binding. So we
  # vendor ALL of its source packages verbatim and compile the whole thing as a
  # library (namespace com.bitchat.android so its R resolves).
  # Remove ONLY the vendored packages — never com/meshsdk (our wrapper, which
  # lives in the same src/main/java root).
  rm -rf "$ANDROID_CORE/com/bitchat" "$ANDROID_CORE/info" "$ANDROID_CORE/org"
  mkdir -p "$ANDROID_CORE/com/bitchat"
  cp -R "$java/com/bitchat/android" "$ANDROID_CORE/com/bitchat/android"
  # Tor (arti) JNI binding sources used by the nostr/relay stack.
  [[ -d "$java/info/guardianproject" ]] && { mkdir -p "$ANDROID_CORE/info"; cp -R "$java/info/guardianproject" "$ANDROID_CORE/info/guardianproject"; }
  [[ -d "$java/org/torproject" ]] && { mkdir -p "$ANDROID_CORE/org"; cp -R "$java/org/torproject" "$ANDROID_CORE/org/torproject"; }

  # Resources (R.string / R.drawable / themes referenced by the UI), assets,
  # and the prebuilt native libs (libarti_android.so) — all copied unchanged.
  if [[ -d "$ANDROID_SRC/app/src/main/res" ]]; then
    rm -rf "$HERE/android/src/main/res"; mkdir -p "$HERE/android/src/main/res"
    cp -R "$ANDROID_SRC/app/src/main/res/." "$HERE/android/src/main/res/"
    # Drop bitchat's UI string TRANSLATIONS (values-<lang>). The RN host provides
    # the UI, so these are unused; the base values/ + config qualifiers
    # (values-night, values-v##, …) are kept so nothing falls back to a missing
    # resource. Saves ~0.9 MB of source and keeps the vendored tree lean.
    ( cd "$HERE/android/src/main/res" && \
      ls -d values-* 2>/dev/null | grep -E '^values-[a-z]{2,3}(-r[A-Z]{2,3})?$' | xargs -r rm -rf )
  fi
  if [[ -d "$ANDROID_SRC/app/src/main/assets" ]]; then
    mkdir -p "$HERE/android/src/main/assets"
    cp -R "$ANDROID_SRC/app/src/main/assets/." "$HERE/android/src/main/assets/" 2>/dev/null || true
  fi
  if [[ -d "$ANDROID_SRC/app/src/main/jniLibs" ]]; then
    rm -rf "$HERE/android/src/main/jniLibs"; mkdir -p "$HERE/android/src/main/jniLibs"
    cp -R "$ANDROID_SRC/app/src/main/jniLibs/." "$HERE/android/src/main/jniLibs/"
  fi

  build_southernstorm_jar
  log "Android done."
}

# The vendored Noise impl (com.bitchat.android.noise.southernstorm) is the only
# Java in the core. Kotlin 2.0.x (the max RNGP 0.74 allows) can't resolve a
# Java-only subpackage from mixed sources, so we PRECOMPILE it to a classpath
# jar and drop the sources from the module. Same upstream source, just built
# ahead of time — still a pure re-copy on update.
build_southernstorm_jar() {
  local ss="$ANDROID_CORE/com/bitchat/android/noise/southernstorm"
  [[ -d "$ss" ]] || return
  local androidjar
  androidjar="$( (ls "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/platforms/android-3*/android.jar 2>/dev/null; ls "$HOME/Library/Android/sdk"/platforms/android-3*/android.jar 2>/dev/null) | sort -V | tail -1)"
  if [[ -z "$androidjar" || ! -f "$androidjar" ]]; then
    log "WARN: android.jar not found — leaving southernstorm as source (needs Kotlin 2.1+ to compile)."
    return
  fi
  log "Precompiling southernstorm Noise -> jar (android.jar: $androidjar)"
  local tmp; tmp="$(mktemp -d)"
  find "$ss" -name "*.java" ! -name "package-info.java" > "$tmp/srcs.txt"
  mkdir -p "$tmp/classes"
  if javac -d "$tmp/classes" -cp "$androidjar" @"$tmp/srcs.txt" 2>"$tmp/javac.log"; then
    mkdir -p "$HERE/android/libs"
    (cd "$tmp/classes" && jar cf "$HERE/android/libs/southernstorm-noise.jar" .)
    rm -rf "$ss"   # remove sources so they aren't double-compiled by the module
    log "southernstorm-noise.jar built; sources removed from module."
  else
    log "WARN: southernstorm javac failed (see below) — leaving sources in place."
    sed 's/^/    /' "$tmp/javac.log" | head -20
  fi
  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# iOS: like Android, bitchat-ios is NOT cleanly layered — Services/BLEService
# reference ViewModels + Views. So we vendor the WHOLE bitchat source tree and
# compile it (together with the RN bridge) into the host APP target, which keeps
# `internal` symbols reachable and lets it use both React (CocoaPods) and the
# SwiftPM deps. We prune only what must NOT be compiled into the RN app:
#   - BitchatApp.swift  (its @main / AppDelegate conflicts with the RN entry)
#   - Assets.xcassets / _PreviewHelpers / Localizable / Info.plist / entitlements
# The local Swift packages (BitFoundation, BitLogger, Tor/Arti incl. its
# prebuilt xcframework) are vendored too and wired via SwiftPM by
# scripts/setup-ios.rb. P256K (swift-secp256k1) is fetched as a remote package.
# ---------------------------------------------------------------------------
sync_ios() {
  if [[ ! -d "$IOS_SRC/bitchat" ]]; then
    log "SKIP ios: $IOS_SRC/bitchat not found (set IOS_SRC)"; return
  fi
  log "iOS core <- $IOS_SRC (full tree)"
  # Replace ONLY the vendored dirs — never the wrapper files at the ios/ root.
  rm -rf "$IOS_CORE/bitchat" "$IOS_CORE/localPackages"
  mkdir -p "$IOS_CORE"

  cp -R "$IOS_SRC/bitchat" "$IOS_CORE/bitchat"

  # Prune app-shell / non-source bits that break an in-app-target compile.
  rm -f  "$IOS_CORE/bitchat/BitchatApp.swift"
  rm -rf "$IOS_CORE/bitchat/Assets.xcassets"
  rm -rf "$IOS_CORE/bitchat/_PreviewHelpers"
  find "$IOS_CORE/bitchat" -name "Info.plist" -delete 2>/dev/null || true
  find "$IOS_CORE/bitchat" -name "*.entitlements" -delete 2>/dev/null || true
  find "$IOS_CORE/bitchat" -name "*.xcstrings" -delete 2>/dev/null || true
  find "$IOS_CORE/bitchat" -name "*.storyboard" -delete 2>/dev/null || true

  # Local Swift packages (BitFoundation, BitLogger, Tor/Arti) vendored verbatim,
  # incl. Arti's prebuilt arti.xcframework.
  if [[ -d "$IOS_SRC/localPackages" ]]; then
    cp -R "$IOS_SRC/localPackages" "$IOS_CORE/localPackages"
  fi

  log "iOS done. Wire into the example project with: ruby scripts/setup-ios.rb"
}

# Re-apply our distinct BLE UUIDs so the SDK forms its OWN private mesh, separate
# from the official bitchat app (which uses the upstream UUIDs). Upstream:
#   service  F47B5E2D-…-4B5C (mainnet) / …-4B5A (testnet)
#   char     A1B2C3D4-…-4C5D
# Remapped to unique values (kept identical to the manual edits in
# AppConstants.kt / BLEService.swift so a re-sync restores them).
patch_mesh_uuids() {
  local n=0 f
  while IFS= read -r f; do
    perl -i -pe '
      s/F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C/7A9C1E3D-2B4F-4A6C-8D5E-1F2A3B4C5D6E/g;
      s/F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5A/7A9C1E3D-2B4F-4A6C-8D5E-1F2A3B4C5D6C/g;
      s/A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D/8B0D2F4E-3C5A-4B7D-9E6F-2A3B4C5D6E7F/g;
    ' "$f"
    n=$((n + 1))
  done < <(grep -rl "F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5\|A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D" \
             "$ANDROID_CORE" "$IOS_CORE/bitchat" 2>/dev/null)
  log "Patched BLE UUIDs for private mesh in $n file(s)."
}

sync_android
sync_ios
patch_mesh_uuids
log "Core sync complete."
