#!/bin/sh
set -e # Thoát ngay nếu có lỗi

# ========================================================
# SCRIPT BUILD CHO ANDROID - IMAGE PROCESSOR
# ========================================================
#
# Biên dịch thư viện Go thành shared library (.so) cho Android.
#
# Tham số:
#   $1: ABI (Kiến trúc Android: arm64-v8a, armeabi-v7a, x86_64, x86)
#   $2: Tên thư viện (ví dụ: image_processor)
#   $3: Đường dẫn đến thư mục chứa mã nguồn Go (ví dụ: .)
#   $4: Đường dẫn thư mục output cho JNI (ví dụ: ../android/app/src/main/jniLibs)
#
# Yêu cầu:
#   - Biến môi trường ANDROID_NDK_HOME phải được thiết lập,
#     HOẶC script sẽ thử một đường dẫn mặc định cho macOS:
#     $HOME/Library/Android/sdk/ndk/DEFAULT_NDK_VERSION
#

# --- Kiểm tra tham số ---
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
  echo "Lỗi: Thiếu tham số."
  echo "Cách dùng: $0 <ABI> <LIB_NAME> <GO_SOURCE_DIR> <ANDROID_JNI_OUT_DIR>"
  exit 1
fi

TARGET_ABI=$1
LIB_NAME=$2
GO_SOURCE_DIR=$3
ANDROID_JNI_OUT_DIR=$4

# --- Xác định ANDROID_NDK_HOME ---
# Ưu tiên biến môi trường nếu được đặt
# Nếu không, thử suy ra từ đường dẫn mặc định cho macOS (như Makefile cũ)
DEFAULT_NDK_VERSION="23.1.7779620" # Phiên bản NDK trong Makefile cũ của bạn
ANDROID_NDK_HOME_INTERNAL="$ANDROID_NDK_HOME" # Sử dụng biến môi trường nếu có

if [ -z "$ANDROID_NDK_HOME_INTERNAL" ]; then
  echo "INFO: Biến môi trường ANDROID_NDK_HOME chưa được đặt."
  # Chỉ thử đường dẫn mặc định này trên macOS
  if [ "$(uname -s)" = "Darwin" ]; then
    DEFAULT_ANDROID_SDK_PATH="$HOME/Library/Android/sdk"
    DERIVED_NDK_HOME="$DEFAULT_ANDROID_SDK_PATH/ndk/$DEFAULT_NDK_VERSION"
    echo "INFO: Thử đường dẫn NDK mặc định cho macOS: $DERIVED_NDK_HOME"
    if [ -d "$DERIVED_NDK_HOME" ]; then
      ANDROID_NDK_HOME_INTERNAL="$DERIVED_NDK_HOME"
      echo "INFO: Tìm thấy NDK tại đường dẫn mặc định: $ANDROID_NDK_HOME_INTERNAL"
    else
      echo "LỖI: Không tìm thấy NDK tại đường dẫn mặc định '$DERIVED_NDK_HOME'."
      echo "Vui lòng đặt biến môi trường ANDROID_NDK_HOME trỏ đến thư mục NDK hợp lệ của bạn."
      exit 1
    fi
  else
    echo "LỖI: Biến môi trường ANDROID_NDK_HOME chưa được đặt."
    echo "Trên các hệ điều hành không phải macOS, bạn cần đặt biến này thủ công."
    exit 1
  fi
elif [ ! -d "$ANDROID_NDK_HOME_INTERNAL" ]; then
  echo "LỖI: ANDROID_NDK_HOME được đặt thành '$ANDROID_NDK_HOME_INTERNAL' nhưng đó không phải là một thư mục hợp lệ."
  exit 1
fi


# --- Xác định cấu hình dựa trên ABI ---
API_LEVEL=21 # Có thể điều chỉnh nếu cần API level cao hơn
GOOS_TARGET="android"
CGO_ENABLED_FLAG=1
CC_COMPILER=""
GOARCH_TARGET=""
OUTPUT_SUBDIR=""

case "$TARGET_ABI" in
  "armeabi-v7a")
    GOARCH_TARGET="arm"
    GOARM_VERSION=7 # Cần thiết cho GOARCH=arm
    CC_COMPILER="armv7a-linux-androideabi${API_LEVEL}-clang"
    OUTPUT_SUBDIR="armeabi-v7a"
    ;;
  "arm64-v8a")
    GOARCH_TARGET="arm64"
    CC_COMPILER="aarch64-linux-android${API_LEVEL}-clang"
    OUTPUT_SUBDIR="arm64-v8a"
    ;;
  "x86")
    GOARCH_TARGET="386"
    CC_COMPILER="i686-linux-android${API_LEVEL}-clang"
    OUTPUT_SUBDIR="x86"
    ;;
  "x86_64")
    GOARCH_TARGET="amd64"
    CC_COMPILER="x86_64-linux-android${API_LEVEL}-clang"
    OUTPUT_SUBDIR="x86_64"
    ;;
  *)
    echo "Lỗi: ABI '$TARGET_ABI' không được hỗ trợ."
    exit 1
    ;;
esac

# --- Xác định Host OS cho NDK prebuilt path ---
HOST_OS=$(uname -s | tr '[:upper:]' '[:lower:]')
NDK_PREBUILT_SUBDIR=""
case "$HOST_OS" in
  "darwin")
    NDK_PREBUILT_SUBDIR="darwin-x86_64"
    ;;
  "linux")
    NDK_PREBUILT_SUBDIR="linux-x86_64"
    ;;
  "windows" | "mingw"*) # Cần kiểm tra thêm cho Windows, có thể là windows-x86_64
    NDK_PREBUILT_SUBDIR="windows-x86_64"
    if [ ! -d "$ANDROID_NDK_HOME_INTERNAL/toolchains/llvm/prebuilt/$NDK_PREBUILT_SUBDIR" ]; then
        echo "Cảnh báo: Không tìm thấy NDK prebuilt cho $NDK_PREBUILT_SUBDIR. Thử 'windows'."
        NDK_PREBUILT_SUBDIR="windows"
    fi
    ;;
  *)
    echo "Lỗi: Host OS '$HOST_OS' không được hỗ trợ tự động cho NDK path."
    exit 1
    ;;
esac

NDK_TOOLCHAIN_PATH="$ANDROID_NDK_HOME_INTERNAL/toolchains/llvm/prebuilt/$NDK_PREBUILT_SUBDIR/bin"

if [ ! -f "$NDK_TOOLCHAIN_PATH/$CC_COMPILER" ]; then
    echo "Lỗi: Không tìm thấy compiler $CC_COMPILER tại $NDK_TOOLCHAIN_PATH"
    echo "Hãy kiểm tra lại đường dẫn NDK ($ANDROID_NDK_HOME_INTERNAL) và phiên bản NDK."
    exit 1
fi

# --- Thiết lập biến môi trường cho Go build ---
export GOOS="$GOOS_TARGET"
export GOARCH="$GOARCH_TARGET"
if [ -n "$GOARM_VERSION" ]; then
  export GOARM="$GOARM_VERSION"
fi
export CGO_ENABLED="$CGO_ENABLED_FLAG"
export CC="$NDK_TOOLCHAIN_PATH/$CC_COMPILER"
# export CXX="$NDK_TOOLCHAIN_PATH/$(echo $CC_COMPILER | sed 's/clang$/clang++/')" # Nếu cần CXX

# --- Tạo thư mục output ---
FINAL_OUTPUT_DIR="$ANDROID_JNI_OUT_DIR/$OUTPUT_SUBDIR"
mkdir -p "$FINAL_OUTPUT_DIR"

# --- Thực hiện build ---
echo "INFO: Building Go source từ '$GO_SOURCE_DIR' cho $TARGET_ABI..."
echo "INFO: Sử dụng NDK từ: $ANDROID_NDK_HOME_INTERNAL"
echo "INFO: GOOS=$GOOS, GOARCH=$GOARCH, CC=$CC"
if [ -n "$GOARM" ]; then
  echo "INFO: GOARM=$GOARM"
fi

go build -v -buildmode=c-shared -o "$FINAL_OUTPUT_DIR/lib${LIB_NAME}.so" "$GO_SOURCE_DIR"

echo "INFO: Build thành công cho $TARGET_ABI: $FINAL_OUTPUT_DIR/lib${LIB_NAME}.so"
