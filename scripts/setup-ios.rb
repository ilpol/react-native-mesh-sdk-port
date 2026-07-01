#!/usr/bin/env ruby
# frozen_string_literal: true
#
# setup-ios.rb — wire the vendored bitchat-ios Core + the RN bridge into an app's
# Xcode project.
#
# Why not a pod? The Core's Swift symbols are `internal` and it depends on SwiftPM
# packages (BitFoundation, BitLogger, Tor, P256K). To keep `internal` reachable
# and to consume both React (CocoaPods) and those SwiftPM modules, the Core + the
# RN bridge (MeshSdk.swift/.m) must compile INTO the app target itself. This
# script does exactly that, idempotently. Re-run after `npm run sync-core`.
#
# Usage:
#   ruby scripts/setup-ios.rb /abs/path/to/App.xcodeproj [AppTargetName]
#
# Defaults to the bundled example project.

require "xcodeproj"

SDK_ROOT   = File.expand_path("..", __dir__)                 # react-native-mesh-sdk
IOS_DIR    = File.join(SDK_ROOT, "ios")                      # bridge + core live here
CORE_DIR   = File.join(IOS_DIR, "core", "bitchat")          # vendored bitchat sources
LOCAL_PKGS = File.join(IOS_DIR, "core", "localPackages")   # BitFoundation/BitLogger/Arti

proj_path = ARGV[0] || File.join(SDK_ROOT, "example", "ios", "MeshChatExample.xcodeproj")
target_name = ARGV[1] # nil -> first application target

abort("Project not found: #{proj_path}") unless File.exist?(proj_path)

project = Xcodeproj::Project.open(proj_path)
target = if target_name
           project.targets.find { |t| t.name == target_name }
         else
           project.targets.find { |t| t.product_type == "com.apple.product-type.application" }
         end
abort("No application target found") unless target
puts "[setup-ios] project=#{File.basename(proj_path)} target=#{target.name}"

GROUP_NAME = "BitchatCore"

# ---------------------------------------------------------------------------
# 1. Remove any previous wiring so re-runs are clean.
# ---------------------------------------------------------------------------
if (old = project.main_group[GROUP_NAME])
  old.recursive_children.each do |c|
    c.build_files.dup.each { |bf| bf.remove_from_project } if c.respond_to?(:build_files)
  end
  old.clear
  old.remove_from_project
  puts "[setup-ios] cleared previous #{GROUP_NAME} group"
end

# ---------------------------------------------------------------------------
# 2. Add sources (bridge + shims + whole vendored Core) to the app target.
# ---------------------------------------------------------------------------
group = project.main_group.new_group(GROUP_NAME)

sources = []
sources += Dir.glob(File.join(IOS_DIR, "*.{swift,m,mm}")).reject { |f| f.include?("/core/") }
sources += Dir.glob(File.join(CORE_DIR, "**", "*.swift"))
sources.sort!

added = 0
sources.each do |abs|
  ref = group.new_file(abs) # xcodeproj stores a path relative to the project
  target.source_build_phase.add_file_reference(ref, true)
  added += 1
end
puts "[setup-ios] added #{added} source files to #{target.name}"

# ---------------------------------------------------------------------------
# 3. SwiftPM packages: local (BitFoundation, BitLogger, Tor) + remote (P256K).
# ---------------------------------------------------------------------------
# Drop existing refs we manage (idempotent).
managed_products = %w[BitFoundation BitLogger Tor P256K]
target.package_product_dependencies.dup.each do |ppd|
  ppd.remove_from_project if managed_products.include?(ppd.product_name)
end
project.root_object.package_references.dup.each do |ref|
  name = ref.respond_to?(:relative_path) ? File.basename(ref.relative_path.to_s) : ref.repositoryURL.to_s
  ref.remove_from_project if name =~ /BitFoundation|BitLogger|Arti|secp256k1/
end

def add_product(project, target, package_ref, product_name)
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = package_ref if package_ref
  dep.product_name = product_name
  target.package_product_dependencies << dep
  bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf.product_ref = dep
  target.frameworks_build_phase.files << bf
end

# Local packages — path relative to the .xcodeproj directory.
proj_dir = File.dirname(proj_path)
{
  "BitFoundation" => %w[BitFoundation],
  "BitLogger"     => %w[BitLogger],
  "Arti"          => %w[Tor],
}.each do |dir, products|
  pkg_path = File.join(LOCAL_PKGS, dir)
  rel = Xcodeproj::Project.relative_path_from(pkg_path, proj_dir) rescue nil
  rel ||= Pathname.new(pkg_path).relative_path_from(Pathname.new(proj_dir)).to_s
  local = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  local.relative_path = rel.to_s
  project.root_object.package_references << local
  products.each { |p| add_product(project, target, local, p) }
  puts "[setup-ios] local SPM: #{dir} (#{rel}) -> #{products.join(', ')}"
end

# Remote package: swift-secp256k1 (module P256K), pinned like bitchat-ios.
remote = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
remote.repositoryURL = "https://github.com/21-DOT-DEV/swift-secp256k1"
remote.requirement = { "kind" => "exactVersion", "version" => "0.21.1" }
project.root_object.package_references << remote
add_product(project, target, remote, "P256K")
puts "[setup-ios] remote SPM: swift-secp256k1 -> P256K"

# ---------------------------------------------------------------------------
# 4. Build settings the Core needs.
# ---------------------------------------------------------------------------
target.build_configurations.each do |cfg|
  cfg.build_settings["SWIFT_VERSION"] ||= "5.0"
  cfg.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "16.0"
  # The Core has SwiftUI + Combine; ensure module + ARC defaults are sane.
  cfg.build_settings["CLANG_ENABLE_MODULES"] = "YES"
end

project.save
puts "[setup-ios] done. Open the .xcworkspace, let SPM resolve, then build."
