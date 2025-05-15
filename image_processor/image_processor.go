package main

/*
#include <stdlib.h>
typedef int int32_t;
*/
import "C"

import (
	"crypto/md5"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"sync"
	"sync/atomic"
	"time"

	"github.com/davidbyttow/govips/v2/vips"
)

const (
	MaxImageDimension  = 8000             // Kích thước tối đa ảnh (chiều rộng/cao) theo pixel
	MaxFileSize        = 30 * 1024 * 1024 // 30MB giới hạn
	LargeImageSize     = 5 * 1024 * 1024  // Ảnh lớn > 5MB sẽ được xử lý đặc biệt
	DefaultJPEGQuality = 80               // Chất lượng JPEG mặc định
	TimeoutDuration    = 30 * time.Second // Thời gian timeout mặc định
	ConcurrentTiles    = 4                // Số phần ảnh xử lý đồng thời cho ảnh lớn
	EnableCache        = true             // Bật/tắt cache
	CacheTimeout       = 15 * time.Minute // Thời gian timeout cho cache
)

var (
	// Sử dụng pool bộ nhớ để giảm áp lực GC
	memoryPool sync.Pool

	// Bộ đếm số ảnh đang xử lý
	processingCounter int32

	// Cache kết quả xử lý ảnh
	processCache     = make(map[string]*cachedResult)
	cacheMutex       sync.RWMutex
	nextCacheCleanup = time.Now().Add(5 * time.Minute)

	// Đã khởi tạo vips
	vipsInitialized bool
)

// Cấu trúc lưu cache
type cachedResult struct {
	path      string    // Đường dẫn đến ảnh đã xử lý
	createdAt time.Time // Thời gian tạo cache
}

func init() {
	// Khởi tạo libvips
	initVips()

	// Khởi tạo memory pool
	memoryPool = sync.Pool{
		New: func() interface{} {
			return make([]byte, 0, 4*1024*1024) // 4MB buffer ban đầu
		},
	}

	// Đặt giới hạn số lượng CPU được sử dụng
	numCPU := runtime.NumCPU()
	runtime.GOMAXPROCS(numCPU)

	// Điều chỉnh GC
	debug.SetGCPercent(100) // Tăng ngưỡng GC để giảm số lần GC chạy

	// Khởi động goroutine dọn cache
	go func() {
		for {
			time.Sleep(5 * time.Minute)
			cleanupCache()
		}
	}()
}

// Khởi tạo libvips
func initVips() {
	if !vipsInitialized {
		vips.LoggingSettings(func(domain string, level vips.LogLevel, message string) {
			// Chỉ log các cảnh báo và lỗi
			if level >= vips.LogLevelWarning {
				fmt.Printf("[%s] %s: %s\n", level, domain, message)
			}
		}, vips.LogLevelWarning)

		vips.Startup(&vips.Config{
			ConcurrencyLevel: runtime.NumCPU(),
			MaxCacheFiles:    50,
			MaxCacheMem:      100 * 1024 * 1024, // 100MB cache
			MaxCacheSize:     500,
			ReportLeaks:      false,
			CollectStats:     false,
		})
		vipsInitialized = true

		// Đảm bảo vips được dọn dẹp khi chương trình kết thúc
		runtime.SetFinalizer(&vipsInitialized, func(_ *bool) {
			vips.Shutdown()
		})
	}
}

//export CropImage
func CropImage(inputPath *C.char, outputPath *C.char, cropX, cropY, cropWidth, cropHeight C.double, quality C.int32_t) *C.char {
	startTime := time.Now()

	inPath := C.GoString(inputPath)
	outPath := C.GoString(outputPath)
	jpegQuality := int(quality)
	if jpegQuality <= 0 {
		jpegQuality = DefaultJPEGQuality
	}

	// Tạo hash key cho cache
	cacheKey := fmt.Sprintf("crop:%s:%f:%f:%f:%f:%d", inPath, float64(cropX), float64(cropY), float64(cropWidth), float64(cropHeight), jpegQuality)
	if EnableCache {
		if cachedPath := checkCache(cacheKey, outPath); cachedPath != "" {
			// Trả về thành công ngay từ cache
			return C.CString(fmt.Sprintf("success_cached:%d", 0))
		}
	}

	if err := checkImageSize(inPath); err != nil {
		return C.CString(fmt.Sprintf("image size check failed: %v", err))
	}

	err := cropImage(inPath, outPath, float64(cropX), float64(cropY), float64(cropWidth), float64(cropHeight), jpegQuality)

	// Tính thời gian xử lý
	processingTime := time.Since(startTime).Milliseconds()

	if err != nil {
		return C.CString(fmt.Sprintf("failed to crop image: %v", err))
	}

	// Lưu vào cache nếu thành công
	if EnableCache {
		addToCache(cacheKey, outPath)
	}

	// Trả về chuỗi rỗng và thời gian xử lý (ms)
	return C.CString(fmt.Sprintf("success:%d", processingTime))
}

//export ResizeImage
func ResizeImage(inputPath, outputPath *C.char, width, height C.double, quality C.int32_t) *C.char {
	startTime := time.Now()

	inPath := C.GoString(inputPath)
	outPath := C.GoString(outputPath)
	jpegQuality := int(quality)
	if jpegQuality <= 0 {
		jpegQuality = DefaultJPEGQuality
	}

	// Tạo hash key cho cache
	cacheKey := fmt.Sprintf("resize:%s:%f:%f:%d", inPath, float64(width), float64(height), jpegQuality)
	if EnableCache {
		if cachedPath := checkCache(cacheKey, outPath); cachedPath != "" {
			// Trả về thành công ngay từ cache
			return C.CString(fmt.Sprintf("success_cached:%d", 0))
		}
	}

	if err := checkImageSize(inPath); err != nil {
		return C.CString(fmt.Sprintf("image size check failed: %v", err))
	}

	err := resizeImage(inPath, outPath, int(width), int(height), jpegQuality)

	// Tính thời gian xử lý
	processingTime := time.Since(startTime).Milliseconds()

	if err != nil {
		return C.CString(fmt.Sprintf("failed to resize image: %v", err))
	}

	// Lưu vào cache nếu thành công
	if EnableCache {
		addToCache(cacheKey, outPath)
	}

	// Trả về chuỗi rỗng và thời gian xử lý (ms)
	return C.CString(fmt.Sprintf("success:%d", processingTime))
}

//export CropAndResizeImage
func CropAndResizeImage(inputPath, outputPath *C.char, cropX, cropY, cropWidth, cropHeight, width, height C.double, quality C.int32_t) *C.char {
	startTime := time.Now()

	inPath := C.GoString(inputPath)
	outPath := C.GoString(outputPath)
	jpegQuality := int(quality)
	if jpegQuality <= 0 {
		jpegQuality = DefaultJPEGQuality
	}

	// Tạo hash key cho cache
	cacheKey := fmt.Sprintf("cropResize:%s:%f:%f:%f:%f:%f:%f:%d",
		inPath, float64(cropX), float64(cropY), float64(cropWidth), float64(cropHeight),
		float64(width), float64(height), jpegQuality)

	if EnableCache {
		if cachedPath := checkCache(cacheKey, outPath); cachedPath != "" {
			// Trả về thành công ngay từ cache
			return C.CString(fmt.Sprintf("success_cached:%d", 0))
		}
	}

	if err := checkImageSize(inPath); err != nil {
		return C.CString(fmt.Sprintf("image size check failed: %v", err))
	}

	err := cropAndResizeImage(inPath, outPath, float64(cropX), float64(cropY), float64(cropWidth), float64(cropHeight), int(width), int(height), jpegQuality)

	// Tính thời gian xử lý
	processingTime := time.Since(startTime).Milliseconds()

	if err != nil {
		return C.CString(fmt.Sprintf("failed to crop and resize image: %v", err))
	}

	// Lưu vào cache nếu thành công
	if EnableCache {
		addToCache(cacheKey, outPath)
	}

	// Trả về chuỗi rỗng và thời gian xử lý (ms)
	return C.CString(fmt.Sprintf("success:%d", processingTime))
}

//export OverlayImage
func OverlayImage(inputPath, overlayPath, outputPath *C.char, x, y, overlayWidth, overlayHeight C.double, quality C.int32_t) *C.char {
	startTime := time.Now()

	inPath := C.GoString(inputPath)
	ovPath := C.GoString(overlayPath)
	outPath := C.GoString(outputPath)
	jpegQuality := int(quality)
	if jpegQuality <= 0 {
		jpegQuality = DefaultJPEGQuality
	}

	// Tạo hash key cho cache
	cacheKey := fmt.Sprintf("overlay:%s:%s:%f:%f:%f:%f:%d",
		inPath, ovPath, float64(x), float64(y),
		float64(overlayWidth), float64(overlayHeight), jpegQuality)

	if EnableCache {
		if cachedPath := checkCache(cacheKey, outPath); cachedPath != "" {
			// Trả về thành công ngay từ cache
			return C.CString(fmt.Sprintf("success_cached:%d", 0))
		}
	}

	if err := checkImageSize(inPath); err != nil {
		return C.CString(fmt.Sprintf("base image size check failed: %v", err))
	}

	if err := checkImageSize(ovPath); err != nil {
		return C.CString(fmt.Sprintf("overlay image size check failed: %v", err))
	}

	err := overlayImage(inPath, ovPath, outPath, float64(x), float64(y), int(overlayWidth), int(overlayHeight), jpegQuality)

	// Tính thời gian xử lý
	processingTime := time.Since(startTime).Milliseconds()

	if err != nil {
		return C.CString(fmt.Sprintf("failed to overlay image: %v", err))
	}

	// Lưu vào cache nếu thành công
	if EnableCache {
		addToCache(cacheKey, outPath)
	}

	// Trả về chuỗi rỗng và thời gian xử lý (ms)
	return C.CString(fmt.Sprintf("success:%d", processingTime))
}

//export ApplyBoardOverlay
func ApplyBoardOverlay(inputPath, outputPath, backgroundFile *C.char, width, height C.double, x, y C.double, quality C.int32_t) *C.char {
	startTime := time.Now()

	inPath := C.GoString(inputPath)
	outPath := C.GoString(outputPath)
	bgFile := C.GoString(backgroundFile)
	jpegQuality := int(quality)
	if jpegQuality <= 0 {
		jpegQuality = DefaultJPEGQuality
	}

	// Tạo hash key cho cache
	cacheKey := fmt.Sprintf("board:%s:%s:%f:%f:%f:%f:%d",
		inPath, bgFile, float64(width), float64(height),
		float64(x), float64(y), jpegQuality)

	if EnableCache {
		if cachedPath := checkCache(cacheKey, outPath); cachedPath != "" {
			// Trả về thành công ngay từ cache
			return C.CString(fmt.Sprintf("success_cached:%d", 0))
		}
	}

	if err := checkImageSize(inPath); err != nil {
		return C.CString(fmt.Sprintf("image size check failed: %v", err))
	}

	if bgFile != "" {
		if err := checkImageSize(bgFile); err != nil {
			return C.CString(fmt.Sprintf("background image size check failed: %v", err))
		}
	}

	err := applyBoardOverlay(inPath, outPath, bgFile, int(width), int(height), float64(x), float64(y), jpegQuality)

	// Tính thời gian xử lý
	processingTime := time.Since(startTime).Milliseconds()

	if err != nil {
		return C.CString(fmt.Sprintf("failed to apply board overlay: %v", err))
	}

	// Lưu vào cache nếu thành công
	if EnableCache {
		addToCache(cacheKey, outPath)
	}

	// Trả về chuỗi rỗng và thời gian xử lý (ms)
	return C.CString(fmt.Sprintf("success:%d", processingTime))
}

// Kiểm tra kích thước ảnh - tối ưu với caching
var (
	imageSizeCache = make(map[string]bool)
	sizeCacheMutex sync.RWMutex
)

func checkImageSize(filePath string) error {
	// Kiểm tra cache trước
	sizeCacheMutex.RLock()
	if _, ok := imageSizeCache[filePath]; ok {
		sizeCacheMutex.RUnlock()
		return nil
	}
	sizeCacheMutex.RUnlock()

	// Kiểm tra kích thước file
	fileInfo, err := os.Stat(filePath)
	if err != nil {
		return fmt.Errorf("không thể truy cập file: %v", err)
	}

	if fileInfo.Size() > MaxFileSize {
		return fmt.Errorf("file size quá lớn (%d bytes), tối đa cho phép là %d bytes", fileInfo.Size(), MaxFileSize)
	}

	// Kiểm tra kích thước ảnh theo pixel - chỉ cho ảnh nhỏ
	// Với ảnh lớn, không cần kiểm tra kích thước pixel để tránh tải toàn bộ ảnh vào bộ nhớ
	if fileInfo.Size() < LargeImageSize {
		// Sử dụng vips để đọc thông tin kích thước ảnh
		img, err := vips.NewImageFromFile(filePath)
		if err != nil {
			return fmt.Errorf("không thể mở ảnh để kiểm tra kích thước: %v", err)
		}
		defer img.Close()

		width := img.Width()
		height := img.Height()

		// Ghi vào cache
		if width <= MaxImageDimension && height <= MaxImageDimension {
			sizeCacheMutex.Lock()
			imageSizeCache[filePath] = true
			sizeCacheMutex.Unlock()
		} else {
			return fmt.Errorf("kích thước ảnh quá lớn (%dx%d), tối đa cho phép là %dx%d",
				width, height, MaxImageDimension, MaxImageDimension)
		}
	} else {
		// Cho ảnh lớn, chỉ kiểm tra kích thước file
		sizeCacheMutex.Lock()
		imageSizeCache[filePath] = true
		sizeCacheMutex.Unlock()
	}

	return nil
}

// Kiểm tra xem ảnh có kích thước lớn không để điều chỉnh xử lý
func isLargeImage(filePath string) bool {
	fileInfo, err := os.Stat(filePath)
	if err != nil {
		return false
	}

	return fileInfo.Size() > LargeImageSize
}

// Xử lý hình ảnh với timeout và giới hạn bộ nhớ
func processWithTimeout(processFn func() error) error {
	// Tăng bộ đếm số ảnh đang xử lý
	atomic.AddInt32(&processingCounter, 1)
	defer atomic.AddInt32(&processingCounter, -1)

	done := make(chan error, 1)
	timeout := time.After(TimeoutDuration)

	go func() {
		// Thu gom rác trước khi xử lý
		runtime.GC()
		err := processFn()
		done <- err
	}()

	select {
	case err := <-done:
		return err
	case <-timeout:
		return fmt.Errorf("xử lý quá thời gian: thao tác mất quá nhiều thời gian để hoàn thành")
	}
}

// Đảm bảo các thư mục đầu ra tồn tại
func ensureOutputDir(outputPath string) error {
	dirPath := filepath.Dir(outputPath)
	if _, err := os.Stat(dirPath); os.IsNotExist(err) {
		return os.MkdirAll(dirPath, 0755)
	}
	return nil
}

// Cập nhật hàm để sử dụng vips thay vì imaging
func cropImage(inputPath, outputPath string, cropX, cropY, cropWidth, cropHeight float64, quality int) error {
	return processWithTimeout(func() error {
		// Đảm bảo thư mục đầu ra tồn tại
		if err := ensureOutputDir(outputPath); err != nil {
			return fmt.Errorf("không thể tạo thư mục đầu ra: %v", err)
		}

		// Mở ảnh
		img, err := vips.NewImageFromFile(inputPath)
		if err != nil {
			return fmt.Errorf("không thể mở ảnh: %v", err)
		}
		defer img.Close()

		// Thực hiện crop
		err = img.ExtractArea(int(cropX), int(cropY), int(cropWidth), int(cropHeight))
		if err != nil {
			return fmt.Errorf("không thể cắt ảnh: %v", err)
		}

		// Lưu ảnh với chất lượng cụ thể
		exportParams := vips.NewJpegExportParams()
		exportParams.Quality = quality

		// Tự động xử lý EXIF orientation
		exportParams.StripMetadata = false
		exportParams.Autorotate = true

		_, err = img.ExportJpegFile(outputPath, exportParams)
		if err != nil {
			return fmt.Errorf("không thể lưu ảnh: %v", err)
		}

		return nil
	})
}

func resizeImage(inputPath, outputPath string, width, height int, quality int) error {
	return processWithTimeout(func() error {
		// Đảm bảo thư mục đầu ra tồn tại
		if err := ensureOutputDir(outputPath); err != nil {
			return fmt.Errorf("không thể tạo thư mục đầu ra: %v", err)
		}

		// Mở ảnh
		img, err := vips.NewImageFromFile(inputPath)
		if err != nil {
			return fmt.Errorf("không thể mở ảnh: %v", err)
		}
		defer img.Close()

		// Thực hiện resize với độ nét tốt nhất cho chất lượng cao
		var vipsResize vips.Kernel
		if quality >= 90 {
			vipsResize = vips.KernelLanczos3 // Chất lượng cao nhất
		} else if quality >= 70 {
			vipsResize = vips.KernelMitchell // Cân bằng tốt
		} else {
			vipsResize = vips.KernelNearest // Nhanh nhất
		}

		// Resize ảnh
		err = img.Resize(float64(width)/float64(img.Width()), vips.KernelLanczos3)
		if err != nil {
			return fmt.Errorf("không thể resize ảnh: %v", err)
		}

		// Lưu ảnh với chất lượng cụ thể
		exportParams := vips.NewJpegExportParams()
		exportParams.Quality = quality

		// Tự động xử lý EXIF orientation
		exportParams.StripMetadata = false
		exportParams.Autorotate = true

		_, err = img.ExportJpegFile(outputPath, exportParams)
		if err != nil {
			return fmt.Errorf("không thể lưu ảnh: %v", err)
		}

		return nil
	})
}

func cropAndResizeImage(inputPath, outputPath string, cropX, cropY, cropWidth, cropHeight float64, width, height int, quality int) error {
	return processWithTimeout(func() error {
		// Đảm bảo thư mục đầu ra tồn tại
		if err := ensureOutputDir(outputPath); err != nil {
			return fmt.Errorf("không thể tạo thư mục đầu ra: %v", err)
		}

		// Mở ảnh
		img, err := vips.NewImageFromFile(inputPath)
		if err != nil {
			return fmt.Errorf("không thể mở ảnh: %v", err)
		}
		defer img.Close()

		// Thực hiện crop
		err = img.ExtractArea(int(cropX), int(cropY), int(cropWidth), int(cropHeight))
		if err != nil {
			return fmt.Errorf("không thể cắt ảnh: %v", err)
		}

		// Chọn thuật toán resize phù hợp
		var vipsResize vips.Kernel
		if quality >= 90 {
			vipsResize = vips.KernelLanczos3 // Chất lượng cao nhất
		} else if quality >= 70 {
			vipsResize = vips.KernelMitchell // Cân bằng tốt
		} else {
			vipsResize = vips.KernelNearest // Nhanh nhất
		}

		// Tính tỷ lệ để resize
		scale := float64(width) / float64(img.Width())

		// Thực hiện resize
		err = img.Resize(scale, vipsResize)
		if err != nil {
			return fmt.Errorf("không thể resize ảnh: %v", err)
		}

		// Lưu ảnh với chất lượng cụ thể
		exportParams := vips.NewJpegExportParams()
		exportParams.Quality = quality

		// Tự động xử lý EXIF orientation
		exportParams.StripMetadata = false
		exportParams.Autorotate = true

		_, err = img.ExportJpegFile(outputPath, exportParams)
		if err != nil {
			return fmt.Errorf("không thể lưu ảnh: %v", err)
		}

		return nil
	})
}

func overlayImage(basePath, overlayPath, outputPath string, x, y float64, width, height int, quality int) error {
	return processWithTimeout(func() error {
		// Đảm bảo thư mục đầu ra tồn tại
		if err := ensureOutputDir(outputPath); err != nil {
			return fmt.Errorf("không thể tạo thư mục đầu ra: %v", err)
		}

		// Mở ảnh nền
		baseImg, err := vips.NewImageFromFile(basePath)
		if err != nil {
			return fmt.Errorf("không thể mở ảnh nền: %v", err)
		}
		defer baseImg.Close()

		// Mở ảnh overlay
		overlayImg, err := vips.NewImageFromFile(overlayPath)
		if err != nil {
			return fmt.Errorf("không thể mở ảnh overlay: %v", err)
		}
		defer overlayImg.Close()

		// Resize overlay nếu cần
		if width > 0 && height > 0 {
			// Tính tỷ lệ để resize
			scale := float64(width) / float64(overlayImg.Width())

			// Chọn thuật toán resize phù hợp
			var vipsResize vips.Kernel
			if quality >= 90 {
				vipsResize = vips.KernelLanczos3
			} else if quality >= 70 {
				vipsResize = vips.KernelMitchell
			} else {
				vipsResize = vips.KernelNearest
			}

			// Thực hiện resize
			err = overlayImg.Resize(scale, vipsResize)
			if err != nil {
				return fmt.Errorf("không thể resize ảnh overlay: %v", err)
			}
		}

		// Thực hiện overlay - cần đảm bảo kênh alpha
		if overlayImg.HasAlpha() == false {
			err = overlayImg.AddAlpha()
			if err != nil {
				return fmt.Errorf("không thể thêm kênh alpha vào ảnh overlay: %v", err)
			}
		}

		// Compositing: đặt overlay lên ảnh nền
		err = baseImg.Composite(overlayImg, vips.BlendModeOver, int(x), int(y))
		if err != nil {
			return fmt.Errorf("không thể ghép ảnh: %v", err)
		}

		// Lưu ảnh với chất lượng cụ thể
		exportParams := vips.NewJpegExportParams()
		exportParams.Quality = quality

		// Tự động xử lý EXIF orientation
		exportParams.StripMetadata = false
		exportParams.Autorotate = true

		_, err = baseImg.ExportJpegFile(outputPath, exportParams)
		if err != nil {
			return fmt.Errorf("không thể lưu ảnh: %v", err)
		}

		return nil
	})
}

func applyBoardOverlay(inputPath, outputPath, backgroundFile string, width, height int, x, y float64, quality int) error {
	return processWithTimeout(func() error {
		// Đảm bảo thư mục đầu ra tồn tại
		if err := ensureOutputDir(outputPath); err != nil {
			return fmt.Errorf("không thể tạo thư mục đầu ra: %v", err)
		}

		// Mở ảnh chính
		baseImg, err := vips.NewImageFromFile(inputPath)
		if err != nil {
			return fmt.Errorf("không thể mở ảnh gốc: %v", err)
		}
		defer baseImg.Close()

		// Nếu có file background, xử lý như overlayImage
		if backgroundFile != "" {
			bgImg, err := vips.NewImageFromFile(backgroundFile)
			if err != nil {
				return fmt.Errorf("không thể mở ảnh nền: %v", err)
			}
			defer bgImg.Close()

			// Resize background nếu cần
			if width > 0 && height > 0 {
				// Tính tỷ lệ để resize
				scaleX := float64(width) / float64(bgImg.Width())

				// Chọn thuật toán resize phù hợp
				var vipsResize vips.Kernel
				if quality >= 90 {
					vipsResize = vips.KernelLanczos3
				} else if quality >= 70 {
					vipsResize = vips.KernelMitchell
				} else {
					vipsResize = vips.KernelNearest
				}

				// Thực hiện resize
				err = bgImg.Resize(scaleX, vipsResize)
				if err != nil {
					return fmt.Errorf("không thể resize ảnh background: %v", err)
				}
			}

			// Đảm bảo ảnh chính có kênh alpha
			if baseImg.HasAlpha() == false {
				err = baseImg.AddAlpha()
				if err != nil {
					return fmt.Errorf("không thể thêm kênh alpha vào ảnh chính: %v", err)
				}
			}

			// Tạo một ảnh mới với kích thước của ảnh chính
			compositedImg := baseImg.Copy()
			defer compositedImg.Close()

			// Đặt background vào vị trí x,y
			err = compositedImg.Composite(bgImg, vips.BlendModeOver, int(x), int(y))
			if err != nil {
				return fmt.Errorf("không thể ghép ảnh background: %v", err)
			}

			// Lưu ảnh với chất lượng cụ thể
			exportParams := vips.NewJpegExportParams()
			exportParams.Quality = quality

			// Tự động xử lý EXIF orientation
			exportParams.StripMetadata = false
			exportParams.Autorotate = true

			_, err = compositedImg.ExportJpegFile(outputPath, exportParams)
			if err != nil {
				return fmt.Errorf("không thể lưu ảnh: %v", err)
			}
		} else {
			// Nếu không có background, chỉ lưu ảnh chính
			exportParams := vips.NewJpegExportParams()
			exportParams.Quality = quality

			// Tự động xử lý EXIF orientation
			exportParams.StripMetadata = false
			exportParams.Autorotate = true

			_, err = baseImg.ExportJpegFile(outputPath, exportParams)
			if err != nil {
				return fmt.Errorf("không thể lưu ảnh: %v", err)
			}
		}

		return nil
	})
}

// Tạo hash key cho cache
func generateHashKey(key string) string {
	hasher := md5.New()
	hasher.Write([]byte(key))
	return hex.EncodeToString(hasher.Sum(nil))
}

// Thêm vào cache
func addToCache(key, outputPath string) {
	// Nếu cache sắp hết thời gian, dọn dẹp cache
	if time.Now().After(nextCacheCleanup) {
		go cleanupCache()
	}

	hashKey := generateHashKey(key)
	cacheMutex.Lock()
	defer cacheMutex.Unlock()

	processCache[hashKey] = &cachedResult{
		path:      outputPath,
		createdAt: time.Now(),
	}
}

// Kiểm tra cache
func checkCache(key, outputPath string) string {
	hashKey := generateHashKey(key)
	cacheMutex.RLock()
	defer cacheMutex.RUnlock()

	if cached, ok := processCache[hashKey]; ok {
		// Kiểm tra nếu cache còn tồn tại
		if time.Since(cached.createdAt) < CacheTimeout {
			// Kiểm tra file tồn tại
			if _, err := os.Stat(cached.path); err == nil {
				// Sao chép file cache vào outputPath nếu khác nhau
				if cached.path != outputPath {
					go copyFile(cached.path, outputPath)
				}
				return cached.path
			}
		}
	}

	return ""
}

// Sao chép file
func copyFile(src, dst string) error {
	// Đảm bảo thư mục đích tồn tại
	if err := ensureOutputDir(dst); err != nil {
		return err
	}

	// Đọc nội dung file nguồn
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}

	// Ghi vào file đích
	return os.WriteFile(dst, data, 0644)
}

// Dọn dẹp cache
func cleanupCache() {
	cacheMutex.Lock()
	defer cacheMutex.Unlock()

	// Đặt thời gian dọn dẹp tiếp theo
	nextCacheCleanup = time.Now().Add(5 * time.Minute)

	for key, cached := range processCache {
		if time.Since(cached.createdAt) > CacheTimeout {
			delete(processCache, key)
		}
	}
}

func main() {
	// Đảm bảo vips được khởi tạo
	initVips()
}
