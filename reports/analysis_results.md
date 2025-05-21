## Kết quả kiểm tra tự động
### Thời gian kiểm tra: Mon May 19 13:50:02 +07 2025

### Commits:
- 3bbf7b4: Implement create podspec and package swift
- 2aac079: Implement debug
- 686d0dd: remove not using
- 10bda59: first commit
### Files thay đổi:
README.md
image_processor/Makefile
image_processor/build_ios.sh
ios/Frameworks/ImageProcessor.podspec
ios/Frameworks/Package.swift
ios/Frameworks/xcframeworks/image_processor.xcframework/Info.plist
ios/Frameworks/xcframeworks/image_processor.xcframework/ios-arm64-simulator/Headers/image_processor.h
ios/Frameworks/xcframeworks/image_processor.xcframework/ios-arm64-simulator/image_processor.a
ios/Frameworks/xcframeworks/image_processor.xcframework/ios-arm64/Headers/image_processor.h
ios/Frameworks/xcframeworks/image_processor.xcframework/ios-arm64/image_processor.a
ios/Runner.xcodeproj/project.pbxproj
pubspec.lock
pubspec.yaml

### Kết quả kiểm tra:
✅ **Phân tích code**: Passed
✅ **Lỗi chính tả**: Không tìm thấy
✅ **Quy tắc đặt tên lớp**: OK
⚠️ **Quy tắc đặt tên biến**: Tìm thấy biến không tuân theo lowerCamelCase
⚠️ **Commented-out code**:        7 dòng tiềm năng
✅ **Print statements**: Không tìm thấy
✅ **Switch cases**: Tất cả switch statements đều có default case
✅ **Line length**: Tất cả các dòng đều trong giới hạn
✅ **Package imports**: OK
✅ **flutter_lints**: Có trong pubspec.yaml
✅ **Tests**: Passed
⚠️ **Non-const widgets**:        1 widgets
⚠️ **Network requests**:        0 yêu cầu tiềm năng,       10 khối try-catch
✅ **Environment variables**: Không tìm thấy biến môi trường hard-coded
⚠️ **Deep nesting**:        6 tiềm năng
✅ **Hardcoded sizes**: Không tìm thấy
✅ **Hardcoded colors**: Không tìm thấy
⚠️ **State management**:        1 StatefulWidget,        0 context.watch(),        0 context.select()
