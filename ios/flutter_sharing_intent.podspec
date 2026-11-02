#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_sharing_intent.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_sharing_intent'
  s.version          = '1.0.1'
  s.summary          = 'Sharing intent plugin for Flutter.'
  s.description      = <<-DESC
 A Flutter plugin to receive sharing data in iOS and Android.
                       DESC
  s.homepage         = 'https://www.techind.co/'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'techind' => 'techind@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_sharing_intent/Sources/flutter_sharing_intent/**/*.swift'
  s.dependency 'Flutter'
  s.ios.deployment_target = '12.0'

  # Xcode 16 explicit module scanner pre-scans all dependencies before build
  # phases run. The auto-generated flutter_sharing_intent-Swift.h contains
  # `@import Flutter` under #if __has_feature(objc_modules), which triggers
  # the scanner to look for Flutter.framework. Flutter's FRAMEWORK_SEARCH_PATHS
  # are SDK-conditional (set by flutter_additional_ios_build_settings), but the
  # scanner ignores sdk-conditionals, so Flutter is never found.
  # Disabling CLANG_ENABLE_EXPLICIT_MODULES on both the pod target and consumer
  # target falls back to the traditional implicit-module path that does not have
  # this pre-scan timing issue.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_ENABLE_EXPLICIT_MODULES' => 'NO',
    'SWIFT_EXPLICIT_MODULES_ENABLED' => 'NO',
  }

  s.user_target_xcconfig = {
    'CLANG_ENABLE_EXPLICIT_MODULES' => 'NO',
    'SWIFT_EXPLICIT_MODULES_ENABLED' => 'NO',
  }

  # Add resource bundle for Apple manifest policy
  s.resource_bundle = {
    'MySDKPrivacy' => ['flutter_sharing_intent/Sources/flutter_sharing_intent/PrivacyInfo.xcprivacy']
  }
  s.swift_version = '5.0'
end
