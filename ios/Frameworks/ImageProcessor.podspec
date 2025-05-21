
Pod::Spec.new do |s|
  s.name             = 'ImageProcessor'
  s.version          = '1.0.0'
  s.summary          = 'A Flutter plugin for image processing'
  s.description      = <<-DESC
A Flutter plugin that provides image processing capabilities including cropping, resizing, and overlaying images.
                       DESC
  s.homepage         = 'https://github.com/leetuanbmt/editor_image'
  s.license          = { :type => 'MIT', :text => 'MIT' }
  s.author           = { 'Leetuan' => 'leetuanbmt@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
  s.vendored_frameworks = 'xcframeworks/libimage_processor.xcframework'

  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '-force_load /Frameworks/libimage_processor.xcframework/ios-arm64-simulator/libimage_processor.a'
  }
end


