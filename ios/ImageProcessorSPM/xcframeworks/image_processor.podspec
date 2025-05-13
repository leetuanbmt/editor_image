Pod::Spec.new do |s|
  s.name             = 'image_processor'
  s.version          = '1.0.0'
  s.summary          = 'Thư viện xử lý hình ảnh cho ứng dụng Kansuke'
  s.description      = <<-DESC
                       Thư viện xử lý hình ảnh được viết bằng Go và được đóng gói thành XCFramework để sử dụng trong ứng dụng iOS.
                       DESC
  s.homepage         = 'https://github.com/KansukeAppRebuildTeam'
  s.license          = { :type => 'MIT', :text => 'MIT License' }
  s.author           = { 'Kansuke Team' => 'info@kansuke.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'
  s.ios.deployment_target = '15.0'
  s.swift_version    = '5.0'
  
  s.vendored_frameworks = 'Frameworks/image_processor.xcframework'
  
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '-force_load $(PODS_ROOT)/../Frameworks/image_processor.xcframework/ios-arm64-simulator/image_processor.a'
  }
end
