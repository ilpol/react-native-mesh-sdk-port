// Tells React Native autolinking where the Android ReactPackage lives. We must
// declare this explicitly because the library's AGP `namespace` is
// `com.bitchat.android` (so the vendored core's R resolves), which is NOT where
// our wrapper class lives — it's in `com.meshsdk`. Without this override,
// autolinking would derive the import from the namespace and fail.
module.exports = {
  dependency: {
    platforms: {
      android: {
        packageImportPath: 'import com.meshsdk.MeshSdkPackage;',
        packageInstance: 'new MeshSdkPackage()',
      },
      // iOS is NOT autolinked as a pod. The vendored bitchat-ios Core depends on
      // SwiftPM packages (BitFoundation, BitLogger, Tor, P256K) and its symbols
      // are `internal`, so the Core + the RN bridge must compile INTO the app
      // target (one module). `scripts/setup-ios.rb` wires that up: it adds the
      // sources and the SwiftPM packages to the app's Xcode project.
      ios: null,
    },
  },
};
