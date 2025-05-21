#!/bin/sh
set -e # Thoát ngay nếu có lỗi

# ========================================================
# SCRIPT BUILD CHO IOS - IMAGE PROCESSOR
# ========================================================
#
# Biên dịch thư viện Go thành static library (.a) và header (.h) cho iOS.
# Phiên bản này cố gắng quay lại logic gần với một phiên bản được báo cáo là hoạt động.
#
# Tham số:
#   $1: GOARCH (Kiến trúc đích: arm64, amd64)
#   $2: SDK (Loại SDK: iphoneos, iphonesimulator)
#   $3: Tên thư viện (ví dụ: image_processor)
#   $4: Đường dẫn đến thư mục chứa mã nguồn Go (ví dụ: .)
#
# Biến môi trường tùy chọn từ Makefile:
#   MIN_IOS_VERSION_ENV: Phiên bản iOS tối thiểu (ví dụ: 12.0).
#                        Nếu không đặt, target triple sẽ không có phiên bản.
#

# --- Kiểm tra tham số ---
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
  echo "Lỗi: Thiếu tham số."
  echo "Cách dùng: $0 <GOARCH> <SDK> <LIB_NAME> <GO_SOURCE_DIR>"
  exit 1
fi

TARGET_GOARCH=$1
TARGET_SDK=$2
LIB_NAME=$3
GO_SOURCE_DIR=$4

# --- Thiết lập các biến ---
export GOOS=ios
export CGO_ENABLED=1

# Phiên bản iOS tối thiểu (từ biến môi trường, nếu có)
MIN_IOS_VERSION_FROM_ENV="${MIN_IOS_VERSION_ENV}"

# Xác định kiến trúc C target (C_ARCH)
C_ARCH=""
if [ "$TARGET_GOARCH" = "amd64" ]; then
    C_ARCH="x86_64"
elif [ "$TARGET_GOARCH" = "arm64" ]; then
    C_ARCH="arm64"
else
    echo "Lỗi: GOARCH '$TARGET_GOARCH' không được hỗ trợ cho iOS."
    exit 1
fi

# Lấy đường dẫn SDK và Clang từ Xcode
SDK_PATH=$(xcrun --sdk "$TARGET_SDK" --show-sdk-path)
CLANG_COMPILER=$(xcrun --sdk "$TARGET_SDK" --find clang)

if [ -z "$SDK_PATH" ] || [ ! -d "$SDK_PATH" ]; then
    echo "Lỗi: Không tìm thấy SDK path cho $TARGET_SDK. SDK_PATH='$SDK_PATH'"
    exit 1
fi
if [ -z "$CLANG_COMPILER" ] || [ ! -f "$CLANG_COMPILER" ]; then
    echo "Lỗi: Không tìm thấy Clang compiler cho $TARGET_SDK. CLANG_COMPILER='$CLANG_COMPILER'"
    exit 1
fi

# Xây dựng target triple cho Clang
# Nếu MIN_IOS_VERSION_FROM_ENV không được đặt, target sẽ là ví dụ: x86_64-apple-ios-simulator
IOS_TARGET_TRIPLE_BASE="${C_ARCH}-apple-ios"
IOS_TARGET_TRIPLE="${IOS_TARGET_TRIPLE_BASE}" # Khởi tạo

if [ -n "$MIN_IOS_VERSION_FROM_ENV" ]; then
    IOS_TARGET_TRIPLE="${IOS_TARGET_TRIPLE_BASE}${MIN_IOS_VERSION_FROM_ENV}"
fi

if [ "$TARGET_SDK" = "iphonesimulator" ]; then
  IOS_TARGET_TRIPLE="${IOS_TARGET_TRIPLE}-simulator"
fi

# Thiết lập CC cho Go. Giữ đơn giản.
export CC="${CLANG_COMPILER} -target ${IOS_TARGET_TRIPLE} -isysroot ${SDK_PATH}"

# Để trống CGO_CFLAGS và CGO_LDFLAGS để Go và Clang tự xử lý nhiều nhất có thể.
# Nếu bạn chắc chắn cần bitcode và nó không gây lỗi, bạn có thể thêm:
# export CGO_CFLAGS="-fembed-bitcode"
# export CGO_LDFLAGS="-fembed-bitcode" # Một số tài liệu đề cập LDFLAGS cũng cần
unset CGO_CFLAGS
unset CGO_LDFLAGS

# --- Tạo thư mục output ---
OUTPUT_DIR="build/ios"
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE_BASE="${OUTPUT_DIR}/${LIB_NAME}_${TARGET_GOARCH}_${TARGET_SDK}"

# --- Thực hiện build ---
echo "INFO: Building Go source từ '$GO_SOURCE_DIR' cho iOS $TARGET_SDK ($TARGET_GOARCH)..."
echo "INFO: GOOS=$GOOS, GOARCH=$TARGET_GOARCH, SDK=$TARGET_SDK"
if [ -n "$MIN_IOS_VERSION_FROM_ENV" ]; then
    echo "INFO: MIN_IOS_VERSION_ENV=$MIN_IOS_VERSION_FROM_ENV"
fi
echo "INFO: C_ARCH=$C_ARCH"
echo "INFO: CC=$CC"
echo "INFO: SDK_PATH=$SDK_PATH"
echo "INFO: IOS_TARGET_TRIPLE=$IOS_TARGET_TRIPLE"
echo "INFO: CGO_CFLAGS (sau khi unset) = $CGO_CFLAGS"
echo "INFO: CGO_LDFLAGS (sau khi unset)= $CGO_LDFLAGS"

go build -v -trimpath -buildmode=c-archive -o "${OUTPUT_FILE_BASE}.a" "$GO_SOURCE_DIR"

# File header .h sẽ được tạo cùng tên với file .a
echo "INFO: Build thành công cho iOS $TARGET_SDK ($TARGET_GOARCH):"
echo "  Archive: ${OUTPUT_FILE_BASE}.a"
echo "  Header:  ${OUTPUT_FILE_BASE}.h"

# # --- Tạo XCFramework ---
# echo "INFO: Creating XCFramework..."
# XCFRAMEWORK_DIR="../ios/Frameworks/xcframeworks"
# mkdir -p "$XCFRAMEWORK_DIR"

# xcodebuild -create-xcframework \
#   -library "${OUTPUT_DIR}/${LIB_NAME}_arm64_iphoneos.a" \
#   -library "${OUTPUT_DIR}/${LIB_NAME}_arm64_iphonesimulator.a" \
#   -output "${XCFRAMEWORK_DIR}/${LIB_NAME}.xcframework"

# --- Tạo Package.swift ---
echo "INFO: Creating Package.swift..."
SPM_DIR="../ios/Frameworks"
mkdir -p "$SPM_DIR"

cat > "$SPM_DIR/Package.swift" << EOF
// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "ImageProcessor",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(
            name: "ImageProcessor",
            targets: ["ImageProcessor"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "ImageProcessor",
            path: "xcframeworks/${LIB_NAME}.xcframework"
        ),
    ]
)
EOF

echo "INFO: Swift Package Manager setup completed at $SPM_DIR"



echo "INFO: Creating podspec..."

cat > "$SPM_DIR/ImageProcessor.podspec" << EOF

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
  s.vendored_frameworks = 'xcframeworks/${LIB_NAME}.xcframework'

  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '-force_load $(PROJECT_DIR)/Frameworks/${LIB_NAME}.xcframework/ios-arm64-simulator/${LIB_NAME}.a'
  }
end


