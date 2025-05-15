#!/bin/bash
# echo "Đang cài đặt thư viện hỗ trợ..."
# go get github.com/disintegration/imaging
# go get github.com/rwcarlsen/goexif/exif

# Xóa file debug cũ nếu có
if [ -f "./debug_app" ]; then
    rm ./debug_app
fi

# Biên dịch với tối ưu hóa và thông tin gỡ lỗi
echo "Biên dịch ứng dụng debug với tối ưu hóa..."
go build -o debug_app -tags=debug -gcflags="-N -l" debug_main.go debug.go image_processor.go

if [ $? -eq 0 ]; then
    echo "Biên dịch thành công."
    echo "Chạy ./debug_app để bắt đầu test..."
    chmod +x ./debug_app
    ./debug_app
else
    echo "Lỗi biên dịch!"
fi
