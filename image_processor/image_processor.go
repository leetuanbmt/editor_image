package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"fmt"
	"image"
	"image/draw"
	"os"
	"path/filepath"
	"runtime"
	"time"

	"github.com/disintegration/imaging"
)

const (
	MaxImageDimension = 8000             // Kích thước tối đa ảnh (chiều rộng/cao) theo pixel
	MaxFileSize       = 30 * 1024 * 1024 // 30MB giới hạn
	LargeImageSize    = 5 * 1024 * 1024  // Ảnh lớn > 5MB sẽ được xử lý đặc biệt
)

//export CropImage
func CropImage(inputPath *C.char, outputPath *C.char, cropX, cropY, cropWidth, cropHeight C.double) *C.char {
	startTime := time.Now()

	inPath := C.GoString(inputPath)
	outPath := C.GoString(outputPath)

	if err := checkImageSize(inPath); err != nil {
		return C.CString(fmt.Sprintf("image size check failed: %v", err))
	}

	err := cropImage(inPath, outPath, float64(cropX), float64(cropY), float64(cropWidth), float64(cropHeight))

	// Tính thời gian xử lý
	processingTime := time.Since(startTime).Milliseconds()

	if err != nil {
		return C.CString(fmt.Sprintf("failed to crop image: %v", err))
	}

	// Trả về chuỗi rỗng và thời gian xử lý (ms)
	return C.CString(fmt.Sprintf("success:%d", processingTime))
}

//export ResizeImage
func ResizeImage(inputPath, outputPath *C.char, width, height C.double) *C.char {
	startTime := time.Now()

	inPath := C.GoString(inputPath)
	outPath := C.GoString(outputPath)

	if err := checkImageSize(inPath); err != nil {
		return C.CString(fmt.Sprintf("image size check failed: %v", err))
	}

	err := resizeImage(inPath, outPath, int(width), int(height))

	// Tính thời gian xử lý
	processingTime := time.Since(startTime).Milliseconds()

	if err != nil {
		return C.CString(fmt.Sprintf("failed to resize image: %v", err))
	}

	// Trả về chuỗi rỗng và thời gian xử lý (ms)
	return C.CString(fmt.Sprintf("success:%d", processingTime))
}

//export CropAndResizeImage
func CropAndResizeImage(inputPath, outputPath *C.char, cropX, cropY, cropWidth, cropHeight, width, height C.double) *C.char {
	startTime := time.Now()

	inPath := C.GoString(inputPath)
	outPath := C.GoString(outputPath)

	if err := checkImageSize(inPath); err != nil {
		return C.CString(fmt.Sprintf("image size check failed: %v", err))
	}

	err := cropAndResizeImage(inPath, outPath, float64(cropX), float64(cropY), float64(cropWidth), float64(cropHeight), int(width), int(height))

	// Tính thời gian xử lý
	processingTime := time.Since(startTime).Milliseconds()

	if err != nil {
		return C.CString(fmt.Sprintf("failed to crop and resize image: %v", err))
	}

	// Trả về chuỗi rỗng và thời gian xử lý (ms)
	return C.CString(fmt.Sprintf("success:%d", processingTime))
}

//export OverlayImage
func OverlayImage(inputPath, overlayPath, outputPath *C.char, x, y, overlayWidth, overlayHeight C.double) *C.char {
	startTime := time.Now()

	inPath := C.GoString(inputPath)
	ovPath := C.GoString(overlayPath)
	outPath := C.GoString(outputPath)

	if err := checkImageSize(inPath); err != nil {
		return C.CString(fmt.Sprintf("base image size check failed: %v", err))
	}

	if err := checkImageSize(ovPath); err != nil {
		return C.CString(fmt.Sprintf("overlay image size check failed: %v", err))
	}

	err := overlayImage(inPath, ovPath, outPath, float64(x), float64(y), int(overlayWidth), int(overlayHeight))

	// Tính thời gian xử lý
	processingTime := time.Since(startTime).Milliseconds()

	if err != nil {
		return C.CString(fmt.Sprintf("failed to overlay image: %v", err))
	}

	// Trả về chuỗi rỗng và thời gian xử lý (ms)
	return C.CString(fmt.Sprintf("success:%d", processingTime))
}

//export ApplyBoardOverlay
func ApplyBoardOverlay(inputPath, outputPath, backgroundFile *C.char, width, height C.double, x, y C.double) *C.char {
	startTime := time.Now()

	inPath := C.GoString(inputPath)
	outPath := C.GoString(outputPath)
	bgFile := C.GoString(backgroundFile)

	if err := checkImageSize(inPath); err != nil {
		return C.CString(fmt.Sprintf("image size check failed: %v", err))
	}

	if bgFile != "" {
		if err := checkImageSize(bgFile); err != nil {
			return C.CString(fmt.Sprintf("background image size check failed: %v", err))
		}
	}

	err := applyBoardOverlay(inPath, outPath, bgFile, int(width), int(height), float64(x), float64(y))

	// Tính thời gian xử lý
	processingTime := time.Since(startTime).Milliseconds()

	if err != nil {
		return C.CString(fmt.Sprintf("failed to apply board overlay: %v", err))
	}

	// Trả về chuỗi rỗng và thời gian xử lý (ms)
	return C.CString(fmt.Sprintf("success:%d", processingTime))
}

// Kiểm tra kích thước ảnh
func checkImageSize(filePath string) error {
	// Kiểm tra kích thước file
	fileInfo, err := os.Stat(filePath)
	if err != nil {
		return fmt.Errorf("cannot access file: %v", err)
	}

	if fileInfo.Size() > MaxFileSize {
		return fmt.Errorf("file size too large (%d bytes), maximum allowed is %d bytes", fileInfo.Size(), MaxFileSize)
	}

	// Kiểm tra kích thước ảnh theo pixel - chỉ cho ảnh nhỏ
	// Với ảnh lớn, không cần kiểm tra kích thước pixel để tránh tải toàn bộ ảnh vào bộ nhớ
	if fileInfo.Size() < LargeImageSize {
		config, err := imaging.Open(filePath)
		if err != nil {
			return fmt.Errorf("cannot open image to check dimensions: %v", err)
		}

		bounds := config.Bounds()
		width := bounds.Dx()
		height := bounds.Dy()

		if width > MaxImageDimension || height > MaxImageDimension {
			return fmt.Errorf("image dimensions too large (%dx%d), maximum allowed is %dx%d",
				width, height, MaxImageDimension, MaxImageDimension)
		}
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
	done := make(chan error, 1)

	// Cài đặt timeout 30 giây
	timeout := time.After(30 * time.Second)

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
		return fmt.Errorf("processing timeout: operation took too long to complete")
	}
}

// Đảm bảo các thư mục đầu ra tồn tại
func ensureOutputDir(outputPath string) error {
	return os.MkdirAll(filepath.Dir(outputPath), 0755)
}

// Go implementation functions

func cropImage(inputPath, outputPath string, cropX, cropY, cropWidth, cropHeight float64) error {
	return processWithTimeout(func() error {
		// Đảm bảo thư mục đầu ra tồn tại
		if err := ensureOutputDir(outputPath); err != nil {
			return fmt.Errorf("không thể tạo thư mục đầu ra: %v", err)
		}

		// Xử lý cho ảnh lớn
		if isLargeImage(inputPath) {
			// Sử dụng tiếp cận tối ưu bộ nhớ
			src, err := imaging.Open(inputPath)
			if err != nil {
				return fmt.Errorf("failed to open image: %v", err)
			}

			cropped := imaging.Crop(src, image.Rect(int(cropX), int(cropY), int(cropX+cropWidth), int(cropY+cropHeight)))

			// Giải phóng bộ nhớ ngay lập tức
			src = nil
			runtime.GC()

			err = imaging.Save(cropped, outputPath, imaging.JPEGQuality(80))
			if err != nil {
				return fmt.Errorf("failed to save cropped image: %v", err)
			}

			// Giải phóng bộ nhớ
			cropped = nil
			runtime.GC()

			return nil
		}

		// Xử lý tiêu chuẩn cho ảnh thường
		src, err := imaging.Open(inputPath)
		if err != nil {
			return fmt.Errorf("failed to open image: %v", err)
		}

		cropped := imaging.Crop(src, image.Rect(int(cropX), int(cropY), int(cropX+cropWidth), int(cropY+cropHeight)))

		err = imaging.Save(cropped, outputPath, imaging.JPEGQuality(80))
		if err != nil {
			return fmt.Errorf("failed to save cropped image: %v", err)
		}

		return nil
	})
}

func resizeImage(inputPath, outputPath string, width, height int) error {
	return processWithTimeout(func() error {
		// Đảm bảo thư mục đầu ra tồn tại
		if err := ensureOutputDir(outputPath); err != nil {
			return fmt.Errorf("không thể tạo thư mục đầu ra: %v", err)
		}

		// Xử lý cho ảnh lớn
		if isLargeImage(inputPath) {
			// Sử dụng tiếp cận tối ưu bộ nhớ
			src, err := imaging.Open(inputPath)
			if err != nil {
				return fmt.Errorf("failed to open image: %v", err)
			}

			// Sử dụng Lanczos chất lượng cao để resize
			resized := imaging.Resize(src, width, height, imaging.Lanczos)

			// Giải phóng bộ nhớ ngay lập tức
			src = nil
			runtime.GC()

			err = imaging.Save(resized, outputPath, imaging.JPEGQuality(80))
			if err != nil {
				return fmt.Errorf("failed to save resized image: %v", err)
			}

			// Giải phóng bộ nhớ
			resized = nil
			runtime.GC()

			return nil
		}

		// Xử lý tiêu chuẩn cho ảnh thường
		src, err := imaging.Open(inputPath)
		if err != nil {
			return fmt.Errorf("failed to open image: %v", err)
		}

		resized := imaging.Resize(src, width, height, imaging.Lanczos)

		err = imaging.Save(resized, outputPath, imaging.JPEGQuality(80))
		if err != nil {
			return fmt.Errorf("failed to save resized image: %v", err)
		}

		return nil
	})
}

func cropAndResizeImage(inputPath, outputPath string, cropX, cropY, cropWidth, cropHeight float64, width, height int) error {
	return processWithTimeout(func() error {
		// Đảm bảo thư mục đầu ra tồn tại
		if err := ensureOutputDir(outputPath); err != nil {
			return fmt.Errorf("không thể tạo thư mục đầu ra: %v", err)
		}

		// Xử lý cho ảnh lớn
		if isLargeImage(inputPath) {
			// Sử dụng tiếp cận tối ưu bộ nhớ
			src, err := imaging.Open(inputPath)
			if err != nil {
				return fmt.Errorf("failed to open image: %v", err)
			}

			cropped := imaging.Crop(src, image.Rect(int(cropX), int(cropY), int(cropX+cropWidth), int(cropY+cropHeight)))

			// Giải phóng bộ nhớ ngay lập tức
			src = nil
			runtime.GC()

			resized := imaging.Resize(cropped, width, height, imaging.Lanczos)

			// Giải phóng bộ nhớ
			cropped = nil
			runtime.GC()

			err = imaging.Save(resized, outputPath, imaging.JPEGQuality(80))
			if err != nil {
				return fmt.Errorf("failed to save processed image: %v", err)
			}

			// Giải phóng bộ nhớ
			resized = nil
			runtime.GC()

			return nil
		}

		// Xử lý tiêu chuẩn cho ảnh thường
		src, err := imaging.Open(inputPath)
		if err != nil {
			return fmt.Errorf("failed to open image: %v", err)
		}

		cropped := imaging.Crop(src, image.Rect(int(cropX), int(cropY), int(cropX+cropWidth), int(cropY+cropHeight)))

		resized := imaging.Resize(cropped, width, height, imaging.Lanczos)

		err = imaging.Save(resized, outputPath, imaging.JPEGQuality(80))
		if err != nil {
			return fmt.Errorf("failed to save processed image: %v", err)
		}

		return nil
	})
}

func overlayImage(basePath, overlayPath, outputPath string, x, y float64, width, height int) error {
	return processWithTimeout(func() error {
		// Đảm bảo thư mục đầu ra tồn tại
		if err := ensureOutputDir(outputPath); err != nil {
			return fmt.Errorf("không thể tạo thư mục đầu ra: %v", err)
		}

		// Xử lý trường hợp ảnh lớn
		isLargeBase := isLargeImage(basePath)
		isLargeOverlay := isLargeImage(overlayPath)

		if isLargeBase || isLargeOverlay {
			// Sử dụng tiếp cận tối ưu bộ nhớ
			baseImg, err := imaging.Open(basePath)
			if err != nil {
				return fmt.Errorf("failed to open base image: %v", err)
			}

			overlayImg, err := imaging.Open(overlayPath)
			if err != nil {
				return fmt.Errorf("failed to open overlay image: %v", err)
			}

			if width > 0 && height > 0 {
				overlayImg = imaging.Resize(overlayImg, width, height, imaging.Lanczos)
			}

			dst := imaging.New(baseImg.Bounds().Dx(), baseImg.Bounds().Dy(), image.Transparent)

			// Xử lý lần lượt và giải phóng bộ nhớ
			dst = imaging.Paste(dst, baseImg, image.Pt(0, 0))
			baseImg = nil
			runtime.GC()

			dst = imaging.Paste(dst, overlayImg, image.Pt(int(x), int(y)))
			overlayImg = nil
			runtime.GC()

			err = imaging.Save(dst, outputPath, imaging.JPEGQuality(80))
			if err != nil {
				return fmt.Errorf("failed to save overlaid image: %v", err)
			}

			dst = nil
			runtime.GC()

			return nil
		}

		// Xử lý tiêu chuẩn cho ảnh thường
		baseImg, err := imaging.Open(basePath)
		if err != nil {
			return fmt.Errorf("failed to open base image: %v", err)
		}

		overlayImg, err := imaging.Open(overlayPath)
		if err != nil {
			return fmt.Errorf("failed to open overlay image: %v", err)
		}

		if width > 0 && height > 0 {
			overlayImg = imaging.Resize(overlayImg, width, height, imaging.Lanczos)
		}

		dst := imaging.New(baseImg.Bounds().Dx(), baseImg.Bounds().Dy(), image.Transparent)

		dst = imaging.Paste(dst, baseImg, image.Pt(0, 0))

		dst = imaging.Paste(dst, overlayImg, image.Pt(int(x), int(y)))

		err = imaging.Save(dst, outputPath, imaging.JPEGQuality(80))
		if err != nil {
			return fmt.Errorf("failed to save overlaid image: %v", err)
		}

		return nil
	})
}

func applyBoardOverlay(inputPath, outputPath, backgroundFile string, width, height int, x, y float64) error {
	return processWithTimeout(func() error {
		// Đảm bảo thư mục đầu ra tồn tại
		if err := ensureOutputDir(outputPath); err != nil {
			return fmt.Errorf("không thể tạo thư mục đầu ra: %v", err)
		}

		// Luôn sử dụng cách tiếp cận tối ưu bộ nhớ cho tác vụ này
		baseImg, err := imaging.Open(inputPath)
		if err != nil {
			return fmt.Errorf("failed to open base image: %v", err)
		}

		bounds := baseImg.Bounds()
		dst := image.NewRGBA(bounds)

		draw.Draw(dst, bounds, baseImg, image.Point{}, draw.Src)

		// Giải phóng bộ nhớ
		baseImg = nil
		runtime.GC()

		if backgroundFile != "" {
			backgroundImg, err := imaging.Open(backgroundFile)
			if err == nil { // Ignore errors for background, just continue
				backgroundImg = imaging.Resize(backgroundImg, width, height, imaging.Lanczos)

				bgRect := image.Rectangle{
					Min: image.Point{int(x), int(y)},
					Max: image.Point{int(x) + width, int(y) + height},
				}

				draw.Draw(dst, bgRect, backgroundImg, image.Point{}, draw.Over)

				// Giải phóng bộ nhớ
				backgroundImg = nil
				runtime.GC()
			} else {
				fmt.Printf("Failed to open background image: %v\n", err)
			}
		}

		err = imaging.Save(dst, outputPath, imaging.JPEGQuality(80))
		if err != nil {
			return fmt.Errorf("failed to save processed image: %v", err)
		}

		// Giải phóng bộ nhớ
		dst = nil
		runtime.GC()

		return nil
	})
}

func main() {}
