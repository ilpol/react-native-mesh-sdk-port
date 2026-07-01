require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "react-native-mesh-sdk"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://github.com/permissionlesstech/bitchat"
  s.license      = package["license"]
  s.authors      = { "react-native-mesh-sdk" => "noreply@example.com" }
  s.platforms    = { :ios => "16.0" }
  s.source       = { :git => ".", :tag => "#{s.version}" }
  s.swift_version = "5.9"

  # The thin Native SDK wrapper (MeshSdk.swift / MeshSdk.m) PLUS the vendored
  # Core BitChat sources copied verbatim under ios/core by scripts/sync-core.sh.
  # We compile the core in-place so upstream updates are a literal file copy.
  s.source_files = "ios/**/*.{h,m,mm,swift}"

  # The Core BitChat depends on these local Swift packages from bitchat-ios.
  # When integrating, point these at the synced copies (see sync-core.sh) or add
  # them to your app's Podfile / Package.swift.
  #   - BitFoundation, BitLogger (localPackages/*)

  s.dependency "React-Core"

  # New-arch (TurboModules) support — harmless on old arch.
  install_modules_dependencies(s) if respond_to?(:install_modules_dependencies)
end
