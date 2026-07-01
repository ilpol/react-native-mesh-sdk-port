/**
 * react-native-mesh-sdk
 *
 * Bluetooth-mesh messaging for React Native, ported from the native BitChat
 * cores (bitchat-android / bitchat-ios).
 *
 * Layering:  React Native App → this NPM module (TS) → Native SDK → Core BitChat
 *
 * Only this top layer and the Native SDK wrappers are maintained here; the
 * Core BitChat classes are vendored verbatim under `android/src/main/java` and
 * `ios/` (bitchat + localPackages; see `scripts/sync-core.sh`) so upstream
 * updates are a drop-in.
 */
export { MeshSdk, default } from './MeshSdk';
export * from './types';
