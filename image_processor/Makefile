# ========================================================
# MAKEFILE TỐI ƯU CHO DỰ ÁN IMAGE PROCESSOR - GO/FLUTTER FFI
# ========================================================
#
# Điều phối việc build thư viện Go cho Android và iOS.
#
# Sử dụng:
#   make all           : Build cho cả Android và iOS
#   make android       : Build tất cả các thư viện cho Android
#   make ios           : Build XCFramework cho iOS
#   make clean         : Xóa tất cả các sản phẩm build
#
# Yêu cầu:
#   - Đặt ANDROID_NDK_HOME trỏ đến thư mục NDK của bạn.
#   - Đặt MIN_IOS_VERSION (ví dụ: 12.0) nếu muốn ghi đè phiên bản iOS tối thiểu.
#

# --- Biến Cấu Hình ---
# Tên thư viện (không có lib prefix hay extension)
LIB_NAME       ?= image_processor
# Thư mục chứa mã nguồn Go (nếu mã Go nằm trong thư mục này)
GO_SOURCE_DIR  ?= .
# Thư mục output XCFramework cho iOS (trong thư mục ios của Flutter)
IOS_XCFRAMEWORK_OUT_DIR ?= ../ios/Frameworks
# Thư mục output JNI Libs cho Android (trong thư mục android của Flutter)
ANDROID_JNI_OUT_DIR     ?= ../android/app/src/main/jniLibs

# Phiên bản iOS tối thiểu (có thể ghi đè bằng biến môi trường)
MIN_IOS_VERSION ?= 12.0

# Các kiến trúc Android cần build
ANDROID_ABIS   ?= arm64-v8a armeabi-v7a x86_64 x86

# Thư mục output XCFramework cho Swift Package
SPM_XCFRAMEWORK_DIR ?= ../ios/Frameworks/xcframeworks

# --- Targets Chính ---
.PHONY: all android ios clean

all: android ios

android:
	@echo "INFO: Building Android libraries..."
	@mkdir -p $(ANDROID_JNI_OUT_DIR)
	@for abi in $(ANDROID_ABIS); do \
		echo "INFO: Building for Android $$abi..."; \
		./build_android.sh $$abi $(LIB_NAME) $(GO_SOURCE_DIR) $(ANDROID_JNI_OUT_DIR) || exit 1; \
	done
	@echo "INFO: Android build complete. Libraries in $(ANDROID_JNI_OUT_DIR)"

ios:
	@echo "INFO: Building iOS XCFramework..."
	@echo "INFO: Building for iOS Device (arm64)..."
	MIN_IOS_VERSION=$(MIN_IOS_VERSION) ./build_ios.sh arm64 iphoneos $(LIB_NAME) $(GO_SOURCE_DIR) || exit 1
	@echo "INFO: Building for iOS Simulator (arm64 - Apple Silicon)..."
	MIN_IOS_VERSION=$(MIN_IOS_VERSION) ./build_ios.sh arm64 iphonesimulator $(LIB_NAME) $(GO_SOURCE_DIR) || exit 1

	@echo "INFO: Creating universal simulator library (chỉ arm64)..."
	cp build/ios/$(LIB_NAME)_arm64_iphonesimulator.a build/ios/$(LIB_NAME)_universal_iphonesimulator.a
	@echo "INFO: Universal simulator library created."

	@echo "INFO: Creating XCFramework..."
	@rm -rf build/ios/$(LIB_NAME).xcframework
	@mkdir -p build/ios_xcf_staging/ios-arm64/Headers
	@mkdir -p build/ios_xcf_staging/ios-arm64-simulator/Headers

	@cp build/ios/$(LIB_NAME)_arm64_iphoneos.a build/ios_xcf_staging/ios-arm64/$(LIB_NAME).a
	@cp build/ios/$(LIB_NAME)_arm64_iphoneos.h build/ios_xcf_staging/ios-arm64/Headers/$(LIB_NAME).h

	@cp build/ios/$(LIB_NAME)_universal_iphonesimulator.a build/ios_xcf_staging/ios-arm64-simulator/$(LIB_NAME).a
	@cp build/ios/$(LIB_NAME)_arm64_iphonesimulator.h build/ios_xcf_staging/ios-arm64-simulator/Headers/$(LIB_NAME).h

	xcodebuild -create-xcframework \
		-library build/ios_xcf_staging/ios-arm64/$(LIB_NAME).a \
		-headers build/ios_xcf_staging/ios-arm64/Headers \
		-library build/ios_xcf_staging/ios-arm64-simulator/$(LIB_NAME).a \
		-headers build/ios_xcf_staging/ios-arm64-simulator/Headers \
		-output build/ios/$(LIB_NAME).xcframework

	@echo "INFO: XCFramework created at build/ios/$(LIB_NAME).xcframework"

	@echo "INFO: Copying XCFramework to Swift Package xcframeworks directory..."
	@mkdir -p $(SPM_XCFRAMEWORK_DIR)
	@rm -rf $(SPM_XCFRAMEWORK_DIR)/$(LIB_NAME).xcframework
	@cp -R build/ios/$(LIB_NAME).xcframework $(SPM_XCFRAMEWORK_DIR)/
	@echo "INFO: XCFramework copied to $(SPM_XCFRAMEWORK_DIR)/$(LIB_NAME).xcframework"

clean:
	@echo "INFO: Cleaning build artifacts..."
	@rm -rf build/
	@rm -rf src/build
	@rm -rf $(ANDROID_JNI_OUT_DIR)/* # Xóa nội dung, không xóa thư mục jniLibs
	@rm -rf $(IOS_XCFRAMEWORK_OUT_DIR)/$(LIB_NAME).xcframework
	@echo "INFO: Clean complete."


