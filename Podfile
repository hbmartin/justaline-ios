project 'JustALine.xcodeproj'

# Updated platform for modern iOS support
platform :ios, '15.0'

def pods_all_targets
  # Comment the next line if you're not using Swift and don't want to use dynamic frameworks
  use_frameworks!

  # UI & Animation
  pod 'lottie-ios', '~> 4.0'
  pod 'Reachability', '~> 3.2'

  # Firebase - Moderate update for better compatibility
  pod 'Firebase', '~> 11.15.0'
  pod 'FirebaseAuth', '~> 11.15.0'
  pod 'FirebaseCrashlytics', '~> 11.15.0'  # Replaces deprecated FirebaseCrash
  pod 'FirebaseAnalytics', '~> 11.15.0'
  pod 'FirebaseFirestore', '~> 11.15.0'
  pod 'FirebaseDatabase', '~> 11.15.0'

  # Google AR & Nearby - Latest compatible versions
  pod 'ARCore', '1.49.0'
  pod 'ARCore/CloudAnchors', '1.49.0'
  # Note: NearbyConnections will be added via Swift Package Manager

  # Supporting dependencies (compatible versions)
  pod 'GoogleToolboxForMac/Logger', '~> 2.3'
  pod 'GoogleToolboxForMac/NSData+zlib', '~> 2.3'
  pod 'Protobuf', '~> 3.20'
  pod 'gRPC-ProtoRPC', '~> 1.44'
end

target 'JustALine' do
    pods_all_targets

    target 'JustALineTests' do
        inherit! :search_paths
        # Pods for testing
    end
end

target 'JustALine Global' do
    pods_all_targets
end

# Modern post-install configuration
post_install do |installer|
  installer.pods_project.targets.each do |target|
    if target.name == 'BoringSSL-GRPC'
      target.source_build_phase.files.each do |file|
        if file.settings && file.settings['COMPILER_FLAGS']
          flags = file.settings['COMPILER_FLAGS'].split
          flags.reject! { |flag| flag == '-GCC_WARN_INHIBIT_ALL_WARNINGS' }
          file.settings['COMPILER_FLAGS'] = flags.join(' ')
        end
      end
    end
    target.build_configurations.each do |config|
      # Update deployment target to match project minimum
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'

      # Ensure modern Swift version
      if config.build_settings['SWIFT_VERSION']
        config.build_settings['SWIFT_VERSION'] = '5.9'
      end

      # Modern build settings
      config.build_settings['CLANG_ANALYZER_LOCALIZABILITY_NONLOCALIZED'] = 'YES'
      config.build_settings['CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER'] = 'NO'
    end
  end

  # Legacy app icon fix for resource compilation
  copy_pods_resources_path = "Pods/Target Support Files/Pods-JustALine/Pods-JustALine-resources.sh"
  copy_pods_global_resources_path = "Pods/Target Support Files/Pods-JustALine Global/Pods-JustALine Global-resources.sh"

  if File.exist?(copy_pods_resources_path)
    string_to_replace = '--compile "${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"'
    assets_compile_with_app_icon_arguments = '--compile "${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}" --app-icon "${ASSETCATALOG_COMPILER_APPICON_NAME}" --output-partial-info-plist "${BUILD_DIR}/assetcatalog_generated_info.plist"'
    text = File.read(copy_pods_resources_path)
    new_contents = text.gsub(string_to_replace, assets_compile_with_app_icon_arguments)
    File.open(copy_pods_resources_path, "w") {|file| file.puts new_contents }
  end

  if File.exist?(copy_pods_global_resources_path)
    text = File.read(copy_pods_global_resources_path)
    new_contents = text.gsub(string_to_replace, assets_compile_with_app_icon_arguments)
    File.open(copy_pods_global_resources_path, "w") {|file| file.puts new_contents }
  end
end
