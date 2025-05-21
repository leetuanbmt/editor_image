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
	"image"
	"image/jpeg"
	"io"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"sync"
	"sync/atomic"
	"time"

	"github.com/disintegration/imaging"
	"github.com/rwcarlsen/goexif/exif"
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
)

// Cấu trúc lưu cache
type cachedResult struct {
	path      string    // Đường dẫn đến ảnh đã xử lý
	createdAt time.Time // Thời gian tạo cache
}

func init() {
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

//export FixImageOrientation
func FixImageOrientation(inputPath, outputPath *C.char, quality C.int32_t) *C.char {
	startTime := time.Now()

	inPath := C.GoString(inputPath)
	outPath := C.GoString(outputPath)
	jpegQuality := int(quality)
	if jpegQuality <= 0 {
		jpegQuality = DefaultJPEGQuality
	}

	// Tạo hash key cho cache
	cacheKey := fmt.Sprintf("fix_orientation:%s:%d", inPath, jpegQuality)
	if EnableCache {
		if cachedPath := checkCache(cacheKey, outPath); cachedPath != "" {
			return C.CString(fmt.Sprintf("success_cached:%d", 0))
		}
	}

	if err := checkImageSize(inPath); err != nil {
		return C.CString(fmt.Sprintf("image size check failed: %v", err))
	}

	err := fixImageOrientation(inPath, outPath, jpegQuality)
	processingTime := time.Since(startTime).Milliseconds()

	if err != nil {
		return C.CString(fmt.Sprintf("failed to fix orientation: %v", err))
	}

	if EnableCache {
		addToCache(cacheKey, outPath)
	}

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
		config, err := imaging.Open(filePath)
		if err != nil {
			return fmt.Errorf("không thể mở ảnh để kiểm tra kích thước: %v", err)
		}

		bounds := config.Bounds()
		width := bounds.Dx()
		height := bounds.Dy()

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

// Đọc thông tin EXIF để xác định hướng ảnh
func getImageOrientation(file io.Reader) (int, error) {
	// Mặc định orientation = 1 (không xoay)
	orientation := 1

	// Đọc metadata EXIF
	x, err := exif.Decode(file)
	if err != nil {
		// Nếu không đọc được EXIF, giả định orientation = 1
		return orientation, nil
	}

	// Lấy giá trị orientation
	tag, err := x.Get(exif.Orientation)
	if err != nil {
		// Nếu không có tag orientation, giả định orientation = 1
		return orientation, nil
	}

	// Chuyển đổi giá trị sang int
	if val, err := tag.Int(0); err == nil {
		orientation = val
	}

	return orientation, nil
}

// Xoay ảnh dựa trên orientation EXIF
func fixOrientation(img image.Image, orientation int) image.Image {
	switch orientation {
	case 2:
		// Lật ngang
		return imaging.FlipH(img)
	case 3:
		// Xoay 180 độ
		return imaging.Rotate180(img)
	case 4:
		// Lật dọc
		return imaging.FlipV(img)
	case 5:
		// Xoay 90 độ và lật ngang
		rotated := imaging.Rotate90(img)
		return imaging.FlipH(rotated)
	case 6:
		// Xoay 90 độ theo chiều kim đồng hồ
		return imaging.Rotate270(img)
	case 7:
		// Xoay 270 độ và lật ngang
		rotated := imaging.Rotate270(img)
		return imaging.FlipH(rotated)
	case 8:
		// Xoay 270 độ theo chiều kim đồng hồ
		return imaging.Rotate90(img)
	default:
		// Giữ nguyên (orientation = 1 hoặc giá trị không hợp lệ)
		return img
	}
}

// Mở ảnh có xử lý EXIF
func openImageWithOrientation(filePath string) (image.Image, error) {
	// Mở file để đọc EXIF trước
	file, err := os.Open(filePath)
	if err != nil {
		return nil, fmt.Errorf("không thể mở file ảnh: %v", err)
	}
	defer file.Close()

	// Đọc thông tin orientation
	orientation, _ := getImageOrientation(file)

	// Đóng và mở lại file để đọc ảnh (cần reset vị trí đọc)
	file.Close()

	// Mở ảnh bằng imaging
	img, err := imaging.Open(filePath)
	if err != nil {
		return nil, err
	}

	// Sửa orientation nếu cần
	if orientation > 1 {
		img = fixOrientation(img, orientation)
	}

	return img, nil
}

// Lưu ảnh với thông tin EXIF được bảo toàn
func saveImagePreservingMetadata(img image.Image, outputPath string, quality int) error {
	// Tạo thư mục đầu ra nếu chưa tồn tại
	if err := ensureOutputDir(outputPath); err != nil {
		return err
	}

	// Nếu là định dạng JPEG, thử bảo toàn metadata
	if filepath.Ext(outputPath) == ".jpg" || filepath.Ext(outputPath) == ".jpeg" {
		return saveJPEGWithMetadata(img, outputPath, quality)
	}

	// Nếu không phải JPEG, sử dụng hàm lưu thông thường
	return imaging.Save(img, outputPath, imaging.JPEGQuality(quality))
}

// Lưu ảnh JPEG với metadata được bảo toàn
func saveJPEGWithMetadata(img image.Image, outputPath string, quality int) error {
	// Tạo file đầu ra
	out, err := os.Create(outputPath)
	if err != nil {
		return err
	}
	defer out.Close()

	// Mã hóa ảnh thành JPEG
	opts := jpeg.Options{Quality: quality}
	if err := jpeg.Encode(out, img, &opts); err != nil {
		return err
	}

	return nil
}

// Cập nhật hàm openAndProcess để sử dụng xử lý orientation mới
func openAndProcess(inputPath string, processFunc func(img image.Image) (image.Image, error), outputPath string, quality int) error {
	// Đảm bảo thư mục đầu ra tồn tại
	if err := ensureOutputDir(outputPath); err != nil {
		return fmt.Errorf("không thể tạo thư mục đầu ra: %v", err)
	}

	// Nếu là ảnh lớn và có thể chia tile
	if isLargeImage(inputPath) && supportsParallelProcessing(processFunc) {
		return processByTiles(inputPath, processFunc, outputPath, quality)
	}

	// Xử lý ảnh bình thường với xử lý orientation
	src, err := openImageWithOrientation(inputPath)
	if err != nil {
		return fmt.Errorf("không thể mở ảnh: %v", err)
	}

	// Xử lý ảnh với hàm được cung cấp
	result, err := processFunc(src)
	if err != nil {
		// Giải phóng bộ nhớ
		src = nil
		runtime.GC()
		return err
	}

	// Giải phóng bộ nhớ
	src = nil
	runtime.GC()

	// Lưu kết quả trong goroutine riêng để tránh chặn
	saveResult := make(chan error, 1)
	go func() {
		saveErr := saveImagePreservingMetadata(result, outputPath, quality)
		result = nil // Giải phóng bộ nhớ
		runtime.GC()
		saveResult <- saveErr
	}()

	// Đợi lưu xong
	if err := <-saveResult; err != nil {
		return fmt.Errorf("không thể lưu ảnh đã xử lý: %v", err)
	}

	return nil
}

// Kiểm tra xem hàm xử lý có hỗ trợ xử lý song song hay không
func supportsParallelProcessing(_ func(img image.Image) (image.Image, error)) bool {
	// Hiện tại chỉ resize hỗ trợ xử lý song song
	// Crop, overlay không dễ song song hóa
	return false // Mặc định không hỗ trợ, sẽ mở rộng sau
}

// Xử lý ảnh lớn bằng cách chia thành các tile nhỏ và xử lý song song
func processByTiles(inputPath string, processFunc func(img image.Image) (image.Image, error), outputPath string, quality int) error {
	// Mở ảnh gốc
	src, err := imaging.Open(inputPath)
	if err != nil {
		return fmt.Errorf("không thể mở ảnh: %v", err)
	}

	bounds := src.Bounds()
	width := bounds.Dx()
	height := bounds.Dy()

	// Chỉ áp dụng cho ảnh đủ lớn
	if width < 1000 || height < 1000 {
		// Ảnh nhỏ, xử lý bình thường
		result, err := processFunc(src)
		if err != nil {
			src = nil
			runtime.GC()
			return err
		}

		src = nil
		runtime.GC()

		return imaging.Save(result, outputPath, imaging.JPEGQuality(quality))
	}

	// Chia ảnh thành các tile
	tileWidth := width / ConcurrentTiles
	tileHeight := height / ConcurrentTiles

	// Chuẩn bị kết quả
	var wg sync.WaitGroup
	results := make([]*image.NRGBA, ConcurrentTiles*ConcurrentTiles)
	errors := make([]error, ConcurrentTiles*ConcurrentTiles)

	// Xử lý từng tile
	for y := 0; y < ConcurrentTiles; y++ {
		for x := 0; x < ConcurrentTiles; x++ {
			wg.Add(1)
			go func(tileX, tileY int) {
				defer wg.Done()

				// Tính toán vùng cắt
				startX := tileX * tileWidth
				startY := tileY * tileHeight
				endX := startX + tileWidth
				endY := startY + tileHeight

				if endX > width {
					endX = width
				}
				if endY > height {
					endY = height
				}

				// Cắt tile
				tile := imaging.Crop(src, image.Rect(startX, startY, endX, endY))

				// Xử lý tile
				processed, err := processFunc(tile)
				if err != nil {
					errors[tileY*ConcurrentTiles+tileX] = err
					return
				}

				// Lưu kết quả
				results[tileY*ConcurrentTiles+tileX] = processed.(*image.NRGBA)
			}(x, y)
		}
	}

	// Đợi tất cả các tile xử lý xong
	wg.Wait()

	// Kiểm tra lỗi
	for i, err := range errors {
		if err != nil {
			return fmt.Errorf("lỗi xử lý tile %d: %v", i, err)
		}
	}

	// Ghép các tile lại
	result := imaging.New(width, height, image.Transparent)
	for y := 0; y < ConcurrentTiles; y++ {
		for x := 0; x < ConcurrentTiles; x++ {
			startX := x * tileWidth
			startY := y * tileHeight
			tile := results[y*ConcurrentTiles+x]
			if tile != nil {
				result = imaging.Paste(result, tile, image.Pt(startX, startY))
			}
		}
	}

	// Giải phóng bộ nhớ
	src = nil
	results = nil
	runtime.GC()

	// Lưu kết quả
	return imaging.Save(result, outputPath, imaging.JPEGQuality(quality))
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
	processCache[hashKey] = &cachedResult{path: outputPath, createdAt: time.Now()}
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

// Go implementation functions - đã tối ưu hóa

func cropImage(inputPath, outputPath string, cropX, cropY, cropWidth, cropHeight float64, quality int) error {
	return processWithTimeout(func() error {
		return openAndProcess(inputPath, func(img image.Image) (image.Image, error) {
			return imaging.Crop(img, image.Rect(int(cropX), int(cropY), int(cropX+cropWidth), int(cropY+cropHeight))), nil
		}, outputPath, quality)
	})
}

// Calculate resize dimensions to fill (cover) the target size while preserving aspect ratio.
// The result will be at least as large as the target in both dimensions, possibly cropping.
func calculateResizeDimensions(img image.Image, targetWidth, targetHeight int) (width, height int) {
	bounds := img.Bounds()
	origWidth := bounds.Dx()
	origHeight := bounds.Dy()

	if targetWidth <= 0 || targetHeight <= 0 {
		return origWidth, origHeight
	}

	widthRatio := float64(targetWidth) / float64(origWidth)
	heightRatio := float64(targetHeight) / float64(origHeight)

	// Use the larger ratio to ensure the image covers the target size
	ratio := widthRatio
	if heightRatio > widthRatio {
		ratio = heightRatio
	}

	// Prevent upscaling beyond original size if not desired (optional)
	// if ratio > 1 {
	// 	ratio = 1
	// }

	newWidth := int(float64(origWidth) * ratio)
	newHeight := int(float64(origHeight) * ratio)
	return newWidth, newHeight
}

func resizeImage(inputPath, outputPath string, width, height int, quality int) error {
	return processWithTimeout(func() error {
		return openAndProcess(inputPath, func(img image.Image) (image.Image, error) {
			// Tính toán kích thước resize phù hợp
			newWidth, newHeight := calculateResizeDimensions(img, width, height)

			// Sử dụng thuật toán nhanh hơn cho ảnh lớn
			filter := imaging.Lanczos
			if isLargeImage(inputPath) && quality < 90 {
				// Dùng box filter cho ảnh lớn và chất lượng thấp
				filter = imaging.Box
			}
			return imaging.Resize(img, newWidth, newHeight, filter), nil
		}, outputPath, quality)
	})
}

func cropAndResizeImage(inputPath, outputPath string, cropX, cropY, cropWidth, cropHeight float64, width, height int, quality int) error {
	return processWithTimeout(func() error {
		return openAndProcess(inputPath, func(img image.Image) (image.Image, error) {
			// Crop trước
			cropped := imaging.Crop(img, image.Rect(int(cropX), int(cropY), int(cropX+cropWidth), int(cropY+cropHeight)))

			// Resize sau
			img = nil // Giải phóng ảnh gốc
			runtime.GC()

			// Tính toán kích thước resize phù hợp
			newWidth, newHeight := calculateResizeDimensions(cropped, width, height)

			// Sử dụng thuật toán nhanh hơn cho ảnh lớn
			filter := imaging.Lanczos
			if quality < 90 {
				// Dùng box filter cho chất lượng thấp
				filter = imaging.Box
			}

			return imaging.Resize(cropped, newWidth, newHeight, filter), nil
		}, outputPath, quality)
	})
}

func overlayImage(basePath, overlayPath, outputPath string, x, y float64, width, height int, quality int) error {
	return processWithTimeout(func() error {
		startTotal := time.Now()
		// Đảm bảo thư mục đầu ra tồn tại
		if err := ensureOutputDir(outputPath); err != nil {
			return fmt.Errorf("không thể tạo thư mục đầu ra: %v", err)
		}

		// Sử dụng concurrent loading cho cả hai ảnh
		var wg sync.WaitGroup
		var baseImg, overlayImg image.Image
		var baseErr, overlayErr error

		// Tải song song hai ảnh với xử lý orientation
		startLoadBase := time.Now()
		wg.Add(1)
		go func() {
			defer wg.Done()
			baseImg, baseErr = openImageWithOrientation(basePath)
		}()

		startLoadOverlay := time.Now()
		wg.Add(1)
		go func() {
			defer wg.Done()
			overlayImg, overlayErr = openImageWithOrientation(overlayPath)
		}()

		wg.Wait()
		log.Printf("Load base: %v ms", time.Since(startLoadBase).Milliseconds())
		log.Printf("Load overlay: %v ms", time.Since(startLoadOverlay).Milliseconds())

		// Kiểm tra lỗi
		if baseErr != nil {
			return fmt.Errorf("không thể mở ảnh nền: %v", baseErr)
		}

		if overlayErr != nil {
			return fmt.Errorf("không thể mở ảnh overlay: %v", overlayErr)
		}

		// Lấy kích thước ảnh nền
		bounds := baseImg.Bounds()
		dst := imaging.New(bounds.Dx(), bounds.Dy(), image.Transparent)
		dst = imaging.Paste(dst, baseImg, image.Pt(0, 0))

		// Giải phóng bộ nhớ
		baseImg = nil
		runtime.GC()

		// Resize overlay nếu cần
		var startResizeOverlay time.Time
		if width > 0 && height > 0 {
			startResizeOverlay = time.Now()
			// Tính toán kích thước resize phù hợp
			newWidth, newHeight := calculateResizeDimensions(overlayImg, width, height)

			// Chọn thuật toán resize dựa trên chất lượng
			filter := imaging.Box // Nhanh hơn cho chất lượng thấp
			if quality >= 90 {
				filter = imaging.Lanczos
			}
			overlayImg = imaging.Resize(overlayImg, newWidth, newHeight, filter)
			log.Printf("Resize overlay: %v ms", time.Since(startResizeOverlay).Milliseconds())
		}

		// Đặt overlay lên ảnh nền
		startPaste := time.Now()
		dst = imaging.Paste(dst, overlayImg, image.Pt(int(x), int(y)))
		log.Printf("Paste overlay: %v ms", time.Since(startPaste).Milliseconds())

		// Giải phóng bộ nhớ
		overlayImg = nil
		runtime.GC()

		// Lưu kết quả trong goroutine riêng
		startSave := time.Now()
		saveChan := make(chan error, 1)
		go func() {
			saveErr := saveImagePreservingMetadata(dst, outputPath, quality)
			dst = nil // Giải phóng bộ nhớ
			runtime.GC()
			saveChan <- saveErr
		}()

		if err := <-saveChan; err != nil {
			return fmt.Errorf("không thể lưu ảnh đã xử lý: %v", err)
		}
		log.Printf("Save output: %v ms", time.Since(startSave).Milliseconds())
		log.Printf("Total overlayImage: %v ms", time.Since(startTotal).Milliseconds())

		return nil
	})
}

// Xoay lại hình ảnh cho đúng chiều dựa trên EXIF
func fixImageOrientation(inputPath, outputPath string, quality int) error {
	return processWithTimeout(func() error {
		// Đọc orientation
		file, err := os.Open(inputPath)
		if err != nil {
			return fmt.Errorf("cannot open image: %v", err)
		}
		defer file.Close()

		orientation, _ := getImageOrientation(file)
		file.Close()

		// Nếu đã đúng chiều thì chỉ copy/lưu lại
		if orientation == 1 {
			// Copy file hoặc lưu lại để giữ metadata
			return copyFile(inputPath, outputPath)
		}

		// Mở lại ảnh và xoay cho đúng chiều
		img, err := imaging.Open(inputPath)
		if err != nil {
			return fmt.Errorf("cannot open image: %v", err)
		}
		img = fixOrientation(img, orientation)

		return saveImagePreservingMetadata(img, outputPath, quality)
	})
}
