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
#   make libvips       : Cài đặt và build libvips cho cả iOS và Android
#   make libvips-ios   : Cài đặt libvips cho iOS
#   make libvips-android: Cài đặt libvips cho Android
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
SPM_XCFRAMEWORK_DIR ?= ../ios/ImageProcessorSPM/xcframeworks

# Phiên bản libvips
LIBVIPS_VERSION ?= 8.13.3

# --- Thư mục cho libvips ---
LIBVIPS_IOS_DIR   := $(GO_SOURCE_DIR)/libvips-ios
LIBVIPS_ANDROID_DIR := $(GO_SOURCE_DIR)/libvips-android

# --- Targets Chính ---
.PHONY: all android ios clean libvips libvips-ios libvips-android

all: libvips android ios

android: libvips-android
	@echo "INFO: Building Android libraries..."
	@mkdir -p $(ANDROID_JNI_OUT_DIR)
	@for abi in $(ANDROID_ABIS); do \
		echo "INFO: Building for Android $$abi..."; \
		./build_android.sh $$abi $(LIB_NAME) $(GO_SOURCE_DIR) $(ANDROID_JNI_OUT_DIR) || exit 1; \
	done
	@echo "INFO: Android build complete. Libraries in $(ANDROID_JNI_OUT_DIR)"

ios: libvips-ios
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

# Tạo thư mục và cài đặt libvips cho iOS
libvips-ios:
	@echo "INFO: Thiết lập libvips cho iOS..."
	@mkdir -p $(LIBVIPS_IOS_DIR)/include
	@mkdir -p $(LIBVIPS_IOS_DIR)/lib
	
	@if [ ! -f "$(LIBVIPS_IOS_DIR)/lib/libvips.a" ]; then \
		echo "INFO: Tải và cài đặt libvips prebuilt cho iOS..."; \
		echo "INFO: Phiên bản libvips: $(LIBVIPS_VERSION)"; \
		echo "CẢNH BÁO: Cần tải libvips prebuilt cho iOS từ nguồn đáng tin cậy"; \
		echo "Vui lòng cài đặt libvips thủ công trong thư mục: $(LIBVIPS_IOS_DIR)"; \
		echo "Cấu trúc thư mục cần có:"; \
		echo "  - $(LIBVIPS_IOS_DIR)/include/: Chứa header files"; \
		echo "  - $(LIBVIPS_IOS_DIR)/lib/: Chứa các file .a (libvips.a, libglib-2.0.a, etc.)"; \
		touch $(LIBVIPS_IOS_DIR)/lib/.placeholder; \
	else \
		echo "INFO: libvips đã được cài đặt cho iOS."; \
	fi

# Tạo thư mục và cài đặt libvips cho Android
libvips-android:
	@echo "INFO: Thiết lập libvips cho Android..."
	@mkdir -p $(LIBVIPS_ANDROID_DIR)/include
	@for abi in $(ANDROID_ABIS); do \
		mkdir -p $(LIBVIPS_ANDROID_DIR)/$$abi/lib; \
	done
	
	@if [ ! -f "$(LIBVIPS_ANDROID_DIR)/$(firstword $(ANDROID_ABIS))/lib/libvips.so" ]; then \
		echo "INFO: Tải và cài đặt libvips prebuilt cho Android..."; \
		echo "INFO: Phiên bản libvips: $(LIBVIPS_VERSION)"; \
		echo "CẢNH BÁO: Cần tải libvips prebuilt cho Android từ nguồn đáng tin cậy"; \
		echo "Vui lòng cài đặt libvips thủ công trong thư mục: $(LIBVIPS_ANDROID_DIR)"; \
		echo "Cấu trúc thư mục cần có:"; \
		echo "  - $(LIBVIPS_ANDROID_DIR)/include/: Chứa header files"; \
		echo "  - $(LIBVIPS_ANDROID_DIR)/[abi]/lib/: Chứa các file .so (libvips.so, libglib-2.0.so, etc.) cho từng ABI"; \
		for abi in $(ANDROID_ABIS); do \
			touch $(LIBVIPS_ANDROID_DIR)/$$abi/lib/.placeholder; \
		done; \
	else \
		echo "INFO: libvips đã được cài đặt cho Android."; \
	fi

# Cài đặt libvips cho cả iOS và Android
libvips: libvips-ios libvips-android

clean:
	@echo "INFO: Cleaning build artifacts..."
	@rm -rf build/
	@rm -rf src/build
	@rm -rf $(ANDROID_JNI_OUT_DIR)/* # Xóa nội dung, không xóa thư mục jniLibs
	@rm -rf $(IOS_XCFRAMEWORK_OUT_DIR)/$(LIB_NAME).xcframework
	@echo "INFO: Clean complete."

# Xóa cả thư viện libvips đã cài đặt
clean-all: clean
	@echo "INFO: Cleaning libvips installations..."
	@rm -rf $(LIBVIPS_IOS_DIR)
	@rm -rf $(LIBVIPS_ANDROID_DIR)
	@echo "INFO: Complete clean done."


