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

# --- Kiểm tra và cài đặt libvips cho iOS ---
VIPS_DIR="$GO_SOURCE_DIR/libvips-ios"
VIPS_INCLUDE="$VIPS_DIR/include"
VIPS_LIB="$VIPS_DIR/lib"

if [ ! -d "$VIPS_DIR" ] || [ ! -d "$VIPS_LIB" ]; then
    echo "INFO: Thư mục libvips chưa được cài đặt cho iOS. Đang cài đặt..."
    mkdir -p "$VIPS_INCLUDE"
    mkdir -p "$VIPS_LIB"
    
    # Script để tải và cài đặt libvips tại đây
    # Đây là bước giả định, trong thực tế bạn cần tải prebuilt libvips cho iOS
    # hoặc biên dịch từ nguồn cho mỗi kiến trúc
    echo "CẢNH BÁO: Cần cài đặt thư viện libvips prebuilt cho iOS"
    echo "Vui lòng tải libvips prebuilt từ nguồn chính thức hoặc tự biên dịch"
    echo "và đặt vào thư mục: $VIPS_DIR"
    
    # Trong môi trường CI/CD hoặc phát triển thực, chúng ta sẽ tự động tải và cài đặt
    # libvips từ một nguồn đáng tin cậy ở đây
fi

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

# Thiết lập CC cho Go với các flags cho libvips
export CC="${CLANG_COMPILER} -target ${IOS_TARGET_TRIPLE} -isysroot ${SDK_PATH}"

# Thêm đường dẫn đến thư viện và include libvips
export CGO_CFLAGS="-I${VIPS_INCLUDE} -I${VIPS_INCLUDE}/glib-2.0"
export CGO_LDFLAGS="-L${VIPS_LIB} -lvips -lgobject-2.0 -lglib-2.0 -lorc-0.4"

# Đảm bảo rằng bitcode được bật (nếu cần)
if [ "$TARGET_SDK" = "iphoneos" ]; then
    export CGO_CFLAGS="$CGO_CFLAGS -fembed-bitcode"
    export CGO_LDFLAGS="$CGO_LDFLAGS -fembed-bitcode"
fi

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
echo "INFO: CGO_CFLAGS=$CGO_CFLAGS"
echo "INFO: CGO_LDFLAGS=$CGO_LDFLAGS"


go build -v -trimpath -buildmode=c-archive -o "${OUTPUT_FILE_BASE}.a" "$GO_SOURCE_DIR"

# File header .h sẽ được tạo cùng tên với file .a
echo "INFO: Build thành công cho iOS $TARGET_SDK ($TARGET_GOARCH):"
echo "  Archive: ${OUTPUT_FILE_BASE}.a"
echo "  Header:  ${OUTPUT_FILE_BASE}.h"

# Sao chép các thư viện tĩnh của libvips vào thư mục đầu ra để Xcode có thể liên kết với chúng
echo "INFO: Bổ sung thư viện libvips và các phụ thuộc vào archive..."
COMBINED_LIB="${OUTPUT_FILE_BASE}_with_vips.a"

# Tạo danh sách các thư viện tĩnh cần kết hợp
if [ -d "$VIPS_LIB" ]; then
    STATIC_LIBS=$(find "$VIPS_LIB" -name "*.a")
    if [ -n "$STATIC_LIBS" ]; then
        # Tạo một bản sao của thư viện gốc
        cp "${OUTPUT_FILE_BASE}.a" "$COMBINED_LIB"
        
        # Liệt kê các thư viện tĩnh có sẵn
        echo "INFO: Kết hợp các thư viện tĩnh sau vào archive:"
        for lib in $STATIC_LIBS; do
            echo "  - $(basename $lib)"
            # Thêm nội dung của thư viện tĩnh vào archive kết hợp
            ar -x "$lib"
            ar -r "$COMBINED_LIB" *.o
            rm *.o
        done
        
        # Thay thế file gốc bằng file kết hợp
        mv "$COMBINED_LIB" "${OUTPUT_FILE_BASE}.a"
        echo "INFO: Đã kết hợp thư viện libvips vào archive chính."
    else
        echo "CẢNH BÁO: Không tìm thấy thư viện tĩnh libvips tại $VIPS_LIB"
    fi
else
    echo "CẢNH BÁO: Thư mục thư viện libvips không tồn tại: $VIPS_LIB"
fi
