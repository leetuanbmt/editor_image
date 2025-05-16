# editor_image

Plugin Flutter để xử lý ảnh với các chức năng cơ bản như crop, resize và overlay. Plugin sử dụng native implementation bằng Go cho hiệu năng tối ưu.

## Cài đặt

Thêm dependency vào file `pubspec.yaml`:

```yaml
dependencies:
  editor_image:
    git:
      url: https://github.com/leetuanbmt/editor_image.git
      ref: main
```

## Cấu hình

### Android

1. Mở file `android/app/build.gradle` và thêm cấu hình sau:

```gradle
android {
    defaultConfig {
        // Thêm cấu hình cho CMake
        externalNativeBuild {
            cmake {
                cppFlags ''
                arguments "-DANDROID_STL=c++_shared"
            }
        }

        // Thêm cấu hình cho ndk
        ndk {
            abiFilters 'armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'
        }
    }

    // Thêm cấu hình cho CMake
    externalNativeBuild {
        cmake {
            path "CMakeLists.txt"
            version "3.22.1"
        }
    }
}
```

2. Thêm quyền vào `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Quyền đọc/ghi bộ nhớ ngoài -->
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
    <!-- Quyền camera nếu cần -->
    <uses-permission android:name="android.permission.CAMERA"/>
</manifest>
```

### iOS

1. Cập nhật `ios/Podfile`:

```ruby
platform :ios, '11.0'

target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))

  # Thêm cấu hình cho thư viện
  pod 'editor_image', :path => '.symlinks/plugins/editor_image/ios'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)

    # Thêm cấu hình build settings
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_BITCODE'] = 'NO'
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '11.0'

      # Thêm cấu hình Swift version
      config.build_settings['SWIFT_VERSION'] = '5.0'
    end
  end
end
```

2. Cập nhật `ios/Runner/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Thêm quyền truy cập photo library -->
    <key>NSPhotoLibraryUsageDescription</key>
    <string>Ứng dụng cần quyền truy cập thư viện ảnh để chọn ảnh cần xử lý</string>

    <!-- Thêm quyền camera nếu cần -->
    <key>NSCameraUsageDescription</key>
    <string>Ứng dụng cần quyền truy cập camera để chụp ảnh</string>

    <!-- Các cấu hình khác -->
</dict>
</plist>
```

## Yêu cầu

### Android

- minSdkVersion 21
- Kotlin version 1.8.0 trở lên
- CMake 3.22.1 trở lên

### iOS

- iOS 11.0 trở lên
- Xcode 14.0 trở lên
- Swift 5.0 trở lên

## Cách sử dụng

### Import thư viện

```dart
import 'package:editor_image/editor_image.dart';
```

### Khởi tạo

```dart
// Kiểm tra xem thư viện đã được load thành công chưa
final hasLibSymbols = ImageProcessor.instance.symbolCache.values.any((exists) => exists);
```

### Các chức năng chính

1. Resize ảnh:

```dart
final result = await ImageProcessor.instance.resizeImage(
  inputPath: inputImagePath,
  outputPath: outputImagePath,
  width: 300,
  height: 400,
);

if (result.success) {
  print('Resize thành công: ${result.processingTime}ms');
} else {
  print('Lỗi: ${result.errorMessage}');
}
```

2. Crop ảnh:

```dart
final result = await ImageProcessor.instance.cropImage(
  inputPath: inputImagePath,
  outputPath: outputImagePath,
  x: 50,
  y: 50,
  width: 300,
  height: 400,
);
```

3. Overlay ảnh:

```dart
final result = await ImageProcessor.instance.overlayImage(
  basePath: baseImagePath,
  overlayPath: overlayImagePath,
  outputPath: outputImagePath,
  x: 0,
  y: 0,
);
```

## Xử lý lỗi

Plugin sử dụng kiểu `ProcessResult` để trả về kết quả xử lý:

```dart
class ProcessResult {
  final bool success;
  final String? errorMessage;
  final int processingTime;
  final String processingText;
}
```

## Hiệu năng

- Thời gian xử lý được đo bằng milliseconds
- Kết quả bao gồm thông tin về kích thước ảnh trước và sau khi xử lý
- Tỷ lệ nén được tính toán tự động

## Giới hạn

- Kích thước ảnh đầu vào tối đa: 4000x4000 pixels
- Định dạng hỗ trợ: JPG, PNG
- Dung lượng file tối đa: 10MB

## Gỡ lỗi

Để bật chế độ debug log:

```dart
ImageProcessor.instance.enableDebugLog = true;
```

## License

MIT License - xem file [LICENSE](LICENSE) để biết thêm chi tiết.
