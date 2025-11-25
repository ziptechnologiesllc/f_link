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

  # Flutter plugin classes
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'

  # Pre-built LinkKit xcframework
  s.vendored_frameworks = 'Frameworks/LinkKit/LinkKit.xcframework'

  # LinkKit resources
  s.resources = 'Frameworks/LinkKit/LinkKitResources.bundle'

  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter configuration
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }

  s.swift_version = '5.0'
end