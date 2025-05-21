package main

/*
#include <stdlib.h>
typedef int int32_t;
*/
import "C"

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"
	"unsafe"
)

// DebugMain - Hàm test thay thế (không dùng func main)
func DebugMain() {
	// Thu gom rác trước khi bắt đầu test
	runtime.GC()

	// Đường dẫn gốc
	basePath := "/Users/tuanvm/Desktop/editor/"

	// Đường dẫn ảnh đầu vào - sử dụng trực tiếp file gốc
	inputFile := filepath.Join(basePath, "bg.jpg")

	backgroundPath := filepath.Join(basePath, "overlay.jpg")

	fmt.Println("inputFile", inputFile)

	// Kiểm tra file tồn tại
	if _, err := os.Stat(inputFile); os.IsNotExist(err) {
		fmt.Println("Lỗi: File ảnh không tồn tại tại", inputFile)
		return
	}

	// In thông tin kích thước file
	if fileInfo, err := os.Stat(inputFile); err == nil {
		fmt.Printf("Kích thước file: %.2f MB\n", float64(fileInfo.Size())/(1024*1024))
	}

	// Chạy test với nhiều kích thước và chất lượng khác nhau
	// testConfigs := []struct {
	// 	name     string
	// 	width    int
	// 	height   int
	// 	quality  int
	// 	filename string
	// }{
	// 	{"Ảnh chuẩn (80% chất lượng + sửa orientation)", 1000, 600, 80, "output_test1.jpg"},
	// }
	// Overlay X 2827.2969203929806
	// Overlay Y 1810.5424292845257
	// Overlay width 1435.175879396985
	// Overlay height 712.8119800332779
	testConfigs := []struct {
		name           string
		filename       string
		inputPath      string
		outputPath     string
		backgroundPath string
		overlayX       float64
		overlayY       float64
		overlayWidth   float64
		overlayHeight  float64
		quality        int
	}{
		{
			name:           "Ảnh chuẩn (80% chất lượng + sửa orientation)",
			filename:       "output_test1.jpg",
			inputPath:      inputFile,
			outputPath:     filepath.Join(basePath, "output_test1.jpg"),
			backgroundPath: backgroundPath,
			overlayX:       2827.2969203929806,
			overlayY:       1810.5424292845257,
			overlayWidth:   1435.175879396985,
			overlayHeight:  712.8119800332779,
			quality:        80,
		},
	}

	// Điểm benchmark
	var benchmarkResults []string

	for _, cfg := range testConfigs {
		fmt.Printf("\n--- %s ---\n", cfg.name)
		outputPath := filepath.Join(basePath, cfg.filename)

		// Đảm bảo GC chạy trước mỗi test
		runtime.GC()
		time.Sleep(100 * time.Millisecond)

		// Thời gian bắt đầu
		startTime := time.Now()

		// Phân tích hiệu suất theo từng giai đoạn
		beforeCall := time.Now()

		// // Gọi hàm resize
		// result := ResizeImage(
		// 	C.CString(inputFile),
		// 	C.CString(outputPath),
		// 	C.double(float64(cfg.width)),
		// 	C.double(float64(cfg.height)),
		// 	C.int32_t(int32(cfg.quality)),
		// )

		result := OverlayImage(
			C.CString(inputFile),
			C.CString(cfg.backgroundPath),
			C.CString(outputPath),
			C.double(cfg.overlayX),      // cropX
			C.double(cfg.overlayY),      // cropY
			C.double(cfg.overlayWidth),  // cropWidth
			C.double(cfg.overlayHeight), // cropHeight
			C.int32_t(cfg.quality),
		)

		// Thời gian gọi hàm
		callDuration := time.Since(beforeCall).Milliseconds()

		// Tính thời gian tổng thể
		elapsedMs := time.Since(startTime).Milliseconds()

		// Phân tích kết quả và giải phóng bộ nhớ
		resultStr := C.GoString(result)
		C.free(unsafe.Pointer(result))

		// Khởi động timers
		processingMs := int64(0)
		if strings.HasPrefix(resultStr, "success:") {
			parts := strings.Split(resultStr, ":")
			if len(parts) > 1 {
				fmt.Sscanf(parts[1], "%d", &processingMs)
			}
		}

		// Hiển thị phân tích hiệu suất chi tiết
		fmt.Printf("Chi tiết hiệu suất:\n")
		fmt.Printf("- Thời gian gọi API: %dms\n", callDuration)
		fmt.Printf("- Thời gian xử lý ảnh: %dms\n", processingMs)
		fmt.Printf("- Overhead: %dms\n", elapsedMs-processingMs)

		// Kiểm tra kết quả
		if strings.HasPrefix(resultStr, "success") {
			fmt.Printf("Kết quả: %s\n", resultStr)

			// Kiểm tra kích thước file đầu ra
			if outInfo, err := os.Stat(outputPath); err == nil {
				fmt.Printf("Kích thước file đầu ra: %.2f KB\n", float64(outInfo.Size())/1024)

				// So sánh tỷ lệ nén
				inInfo, _ := os.Stat(inputFile)
				ratio := float64(outInfo.Size()) / float64(inInfo.Size()) * 100
				fmt.Printf("Tỷ lệ nén: %.1f%%\n", ratio)
			}

			// Thêm kết quả vào benchmark
			benchmarkResults = append(benchmarkResults, fmt.Sprintf("%s: %dms", cfg.name, processingMs))
		} else {
			fmt.Printf("Lỗi: %s\n", resultStr)
		}
	}

	// Hiển thị kết quả benchmark
	fmt.Println("\n===== KẾT QUẢ BENCHMARK SIÊU NHANH =====")
	for _, result := range benchmarkResults {
		fmt.Println(result)
	}

}
