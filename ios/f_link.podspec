#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'f_link'
  s.version          = '0.2.5'
  s.summary          = 'Ableton Link wrapper for Flutter - iOS via LinkKit'
  s.description      = <<-DESC
A Flutter plugin that wraps Ableton Link for synchronization across devices.
On iOS, uses the official LinkKit source code via Method Channels.
On other platforms, uses FFI with the C++ Link library.
                       DESC
  s.homepage         = 'https://github.com/anzbert/f_link'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'anzbert' => 'https://github.com/anzbert' }
  s.source           = { :path => '.' }

  # Flutter plugin classes + LinkKit source
  s.source_files = 'Classes/**/*', 'Frameworks/LinkKit/LinkKit/**/*.{h,mm}'
  s.public_header_files = 'Classes/**/*.h'

  # LinkKit resources
  s.resources = 'Frameworks/LinkKit/LinkKit/LinkKitResources.bundle'

  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter configuration
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/Frameworks/LinkKit/LinkKit" "$(PODS_TARGET_SRCROOT)/Frameworks/LinkKit/LinkKit/detail" "$(PODS_TARGET_SRCROOT)/../macos/link/include" "$(PODS_TARGET_SRCROOT)/../macos/link/modules/asio-standalone/asio/include"',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) LINK_PLATFORM_MACOSX=1'
  }

  s.swift_version = '5.0'
end