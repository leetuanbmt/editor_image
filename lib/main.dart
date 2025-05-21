import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'image_processor.dart';
import 'overlay_image.dart';
import 'src/utils/logger.dart';

void main() {
  // Đặt handler cho bắt lỗi khi ứng dụng bắt đầu
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('=== Flutter Error: ${details.exception}');
    debugPrint('=== ${details.stack}');
    FlutterError.presentError(details);
  };

  runApp(
    MaterialApp(
      showPerformanceOverlay: true,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final imagePicker = ImagePicker();
  final _uuid = Uuid();
  File? _inputImage;
  File? _outputImage;
  bool _processing = false;
  String _status = '';

  // Biến lưu thông tin thời gian xử lý
  String _processingTimeText = '';
  int _processingTimeMs = 0;

  // Biến lưu thông tin kích thước ảnh
  String _inputImageInfo = '';
  String _outputImageInfo = '';
  double _compressionRatio = 0;

  // Stopwatch để đo thời gian
  final Stopwatch _stopwatch = Stopwatch();

  Future<String> getOutputPath() async {
    final tempDir = await getTemporaryDirectory();
    return '${tempDir.path}/${_uuid.v4()}.jpg';
  }

  late FileInfo inputInfo;
  Future<void> pickImage() async {
    final XFile? image = await imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 4000,
    );
    if (image != null) {
      setState(() {
        _inputImage = File(image.path);
        _outputImage = null;
        _status = '';
        _processingTimeText = '';
        _processingTimeMs = 0;
        _inputImageInfo = '';
        _outputImageInfo = '';
        _compressionRatio = 0;
      });

      // Log thông tin ảnh đầu vào
      inputInfo = await _getFileInfo(_inputImage!);
      final inputSizeKB = (inputInfo.size / 1024).toStringAsFixed(2);
      _inputImageInfo =
          '${inputInfo.width}x${inputInfo.height} px, $inputSizeKB KB';
      Logger.d('Input image: $_inputImageInfo');

      setState(() {});
    }
  }

  Size calculatorSize(Size imageSize, Size adjustSize) {
    final width = imageSize.width;
    final height = imageSize.height;
    final adjustWidth = adjustSize.width;
    final adjustHeight = adjustSize.height;

    /// Determine the miniature rate based on width and height
    final scaleWidth = adjustWidth / width;
    final scaleHeight = adjustHeight / height;

    /// Choose the smaller ratio to ensure the image fits entirely within the target size
    final scale = scaleWidth < scaleHeight ? scaleWidth : scaleHeight;

    /// Ensure the ratio is not greater than 1 (does not exceed the original image size)
    final finalScale = scale > 1.0 ? 1.0 : scale;

    /// Calculate the new size based on the ratio
    final newWidth = width * finalScale;
    final newHeight = height * finalScale;

    return Size(newWidth, newHeight);
  }

  Future<void> _resizeImage() async {
    if (_inputImage == null) {
      setState(() {
        _status = 'Vui lòng chọn ảnh trước';
      });
      return;
    }

    setState(() {
      _processing = true;
      _status = 'Đang thay đổi kích thước ảnh...';
      _processingTimeText = '';
      _processingTimeMs = 0;
      _outputImageInfo = '';
      _compressionRatio = 0;
    });

    // final inputInfo = await _getFileInfo(_inputImage!);
    // final inputSize = inputInfo.size;
    // final inputDimensions =
    //     '${inputInfo.width.toInt()}x${inputInfo.height.toInt()}';
    // Logger.d(
    //   'Input image size: $inputDimensions px, ${(inputSize / 1024).toStringAsFixed(2)} KB',
    // );

    final adjustSize = calculatorSize(inputInfo.dimension, Size(300, 400));
    // Logger.d(
    //   'Target resize dimensions: ${adjustSize.width.toInt()}x${adjustSize.height.toInt()} px',
    // );

    try {
      final outputPath = await getOutputPath();

      // Sử dụng Stopwatch để đo thời gian xử lý
      _stopwatch.reset();
      _stopwatch.start();

      // Sử dụng API mới qua ImageProcessor
      await ImageProcessor.instance.execute(
        inputPath: _inputImage!.path,
        outputPath: outputPath,
        config: ResizeConfig(
          width: adjustSize.width,
          height: adjustSize.height,
        ),
        onCompleted: (file) {
          setState(() {
            _outputImage = File(outputPath);
            _status = 'Đã thay đổi kích thước ảnh thành công';
          });
        },
        onError: (error, stackTrace) {
          Logger.d('Resize error: $error');
          Logger.d('Resize stackTrace: $stackTrace');
          setState(() {
            _status = 'Lỗi khi thay đổi kích thước ảnh: ${error.toString()}';
          });
        },
      );
    } finally {
      _stopwatch.stop();
      final timeMs = _stopwatch.elapsedMilliseconds;
      _processingTimeMs = timeMs;
      _processingTimeText = 'Thời gian xử lý: $timeMs ms';

      // Log thông tin ảnh đầu ra
      if (_outputImage != null) {
        final outputInfo = await _getFileInfo(_outputImage!);

        final outputSize = outputInfo.size;
        final outputDimensions =
            '${outputInfo.width.toInt()}x${outputInfo.height.toInt()}';

        _outputImageInfo =
            '$outputDimensions px, ${(outputSize / 1024).toStringAsFixed(2)} KB';

        // Tính tỷ lệ nén
        _compressionRatio =
            inputInfo.size > 0 ? (1 - outputSize / inputInfo.size) * 100 : 0;

        Logger.d('Output image size: $_outputImageInfo');
        Logger.d('Compression ratio: ${_compressionRatio.toStringAsFixed(2)}%');
      }

      setState(() {
        _processing = false;
      });
    }
  }

  Future<void> _cropImage() async {
    if (_inputImage == null) {
      setState(() {
        _status = 'Vui lòng chọn ảnh trước';
      });
      return;
    }

    setState(() {
      _processing = true;
      _status = 'Đang cắt ảnh...';
      _processingTimeText = '';
      _processingTimeMs = 0;
      _outputImageInfo = '';
      _compressionRatio = 0;
    });

    final inputInfo = await _getFileInfo(_inputImage!);
    final inputSize = inputInfo.size;
    final inputDimensions =
        '${inputInfo.width.toInt()}x${inputInfo.height.toInt()}';
    Logger.d(
      'Input image size: $inputDimensions px, ${(inputSize / 1024).toStringAsFixed(2)} KB',
    );

    try {
      final outputPath = await getOutputPath();

      // Lấy kích thước của ảnh để xác định vùng cắt
      final imageSize = _inputImage!.size;
      final imageWidth = imageSize.width;
      final imageHeight = imageSize.height;

      // Cắt 50px từ mỗi cạnh
      final cropX = 50.0;
      final cropY = 50.0;
      final cropWidth = imageWidth - cropX * 2;
      final cropHeight = imageHeight - cropY * 2;

      Logger.d(
        'Crop region: [X:$cropX, Y:$cropY, W:$cropWidth, H:$cropHeight]',
      );

      // Sử dụng Stopwatch để đo thời gian
      _stopwatch.reset();
      _stopwatch.start();

      // Sử dụng API mới qua ImageProcessor
      await ImageProcessor.instance.execute(
        inputPath: _inputImage!.path,
        outputPath: outputPath,
        config: CropConfig(
          cropX: cropX,
          cropY: cropY,
          cropWidth: cropWidth,
          cropHeight: cropHeight,
        ),
        onCompleted: (file) {
          setState(() {
            _outputImage = File(outputPath);
            _status = 'Đã cắt ảnh thành công';
          });
        },
        onError: (error, stackTrace) {
          Logger.d('Crop error: $error');
          Logger.d('Crop stackTrace: $stackTrace');
          setState(() {
            _status = 'Lỗi khi cắt ảnh: ${error.toString()}';
          });
        },
      );
    } catch (e) {
      setState(() {
        _status = 'Lỗi: $e';
      });
      debugPrint(e.toString());
    } finally {
      _stopwatch.stop();
      final timeMs = _stopwatch.elapsedMilliseconds;
      _processingTimeMs = timeMs;
      _processingTimeText = 'Thời gian xử lý: $timeMs ms';

      // Log thông tin ảnh đầu ra
      if (_outputImage != null) {
        final outputInfo = await _getFileInfo(_outputImage!);
        final inputInfo = await _getFileInfo(_inputImage!);

        final outputSize = outputInfo.size;
        final outputDimensions =
            '${outputInfo.width.toInt()}x${outputInfo.height.toInt()}';

        _outputImageInfo =
            '$outputDimensions px, ${(outputSize / 1024).toStringAsFixed(2)} KB';

        // Tính tỷ lệ nén
        _compressionRatio =
            inputInfo.size > 0 ? (1 - outputSize / inputInfo.size) * 100 : 0;

        Logger.d('Output image size: $_outputImageInfo');
        Logger.d('Compression ratio: ${_compressionRatio.toStringAsFixed(2)}%');
      }

      setState(() {
        _processing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLibSymbols = ImageProcessor.instance.symbolCache.values.any(
      (exists) => exists,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Image Processor Demo')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Thông tin thư viện native:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Platform: ${Platform.operatingSystem}'),
              Text(
                'Thư viện đã tải: ${hasLibSymbols ? "Thành công" : "Thất bại"}',
                style: TextStyle(
                  color: hasLibSymbols ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Hiển thị trạng thái của từng ký hiệu
              ExpansionTile(
                initiallyExpanded: true,
                title: const Text('Chi tiết về Symbols'),
                children: [
                  ...ImageProcessor.instance.symbolCache.entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: Text(
                        '${entry.key}: ${entry.value ? "✓" : "✗"}',
                        style: TextStyle(
                          color: entry.value ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: pickImage,
                child: const Text('Chọn ảnh'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const OverlayImageEditorScreen(),
                    ),
                  );
                },
                child: const Text('Overlay Image Editor'),
              ),
              const SizedBox(height: 16),
              if (_inputImage != null) ...[
                Image.file(
                  _inputImage!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
                // Thêm hiển thị chi tiết ảnh gốc
                const SizedBox(height: 8),
                FutureBuilder<FileInfo>(
                  future: _getFileInfo(_inputImage!),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      final info = snapshot.data!;
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chi tiết ảnh gốc:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Kích thước: ${info.width.toInt()} x ${info.height.toInt()} px',
                            ),
                            Text(
                              'Dung lượng: ${(info.size / 1024).toStringAsFixed(2)} KB',
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox();
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed:
                          _processing ||
                                  !(ImageProcessor
                                          .instance
                                          .symbolCache['ResizeImage'] ??
                                      false)
                              ? null
                              : _resizeImage,
                      child: const Text('Resize'),
                    ),
                    ElevatedButton(
                      onPressed:
                          _processing ||
                                  !(ImageProcessor
                                          .instance
                                          .symbolCache['CropImage'] ??
                                      false)
                              ? null
                              : _cropImage,
                      child: const Text('Cắt'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (_processing)
                const Center(child: CircularProgressIndicator())
              else if (_status.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _status,
                      style: TextStyle(
                        color:
                            _status.contains('Lỗi') ? Colors.red : Colors.green,
                      ),
                    ),
                    if (_processingTimeText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _processingTimeText,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color:
                              _processingTimeMs > 1000
                                  ? Colors.orange
                                  : Colors.blue,
                        ),
                      ),
                      // Hiển thị đánh giá tốc độ xử lý
                      Text(
                        _getPerformanceRating(_processingTimeMs),
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: _getPerformanceColor(_processingTimeMs),
                        ),
                      ),
                      // Thêm biểu đồ thanh đơn giản để trực quan hóa thời gian xử lý
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        width: double.infinity,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: _getPerformanceBarWidth(
                            _processingTimeMs,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _getPerformanceColor(_processingTimeMs),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: 16),
              if (_outputImage != null) ...[
                Text('Ảnh sau xử lý:'),
                if (_outputImageInfo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kích thước: $_outputImageInfo',
                          style: const TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        if (_compressionRatio > 0)
                          Text(
                            'Tỷ lệ nén: ${_compressionRatio.toStringAsFixed(2)}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color:
                                  _compressionRatio > 30
                                      ? Colors.green
                                      : Colors.blue,
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Image.file(
                  _outputImage!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Hàm lấy đánh giá hiệu suất dựa trên thời gian xử lý
  String _getPerformanceRating(int timeMs) {
    if (timeMs < 200) return 'Rất nhanh ⚡';
    if (timeMs < 500) return 'Nhanh 👍';
    if (timeMs < 1000) return 'Bình thường ⏱️';
    if (timeMs < 2000) return 'Hơi chậm ⏳';
    return 'Chậm, cần tối ưu ⏰';
  }

  // Màu sắc tương ứng với đánh giá hiệu suất
  Color _getPerformanceColor(int timeMs) {
    if (timeMs < 200) return Colors.green.shade800;
    if (timeMs < 500) return Colors.green;
    if (timeMs < 1000) return Colors.blue;
    if (timeMs < 2000) return Colors.orange;
    return Colors.red;
  }

  // Tính độ rộng tương đối của thanh hiển thị hiệu suất
  double _getPerformanceBarWidth(int timeMs) {
    if (timeMs < 100) return 0.1;
    if (timeMs < 200) return 0.2;
    if (timeMs < 500) return 0.4;
    if (timeMs < 1000) return 0.6;
    if (timeMs < 2000) return 0.8;
    return 1.0;
  }

  // Lấy thông tin ảnh
  Future<FileInfo> _getFileInfo(File file) async {
    final size = await file.length();
    final dimensions = file.size;
    return FileInfo(
      size: size,
      width: dimensions.width,
      height: dimensions.height,
    );
  }
}

// Lớp lưu thông tin kết quả xử lý
class ProcessResult {
  ProcessResult({
    required this.success,
    this.errorMessage,
    required this.processingTime,
    required this.processingText,
  });
  final bool success;
  final String? errorMessage;
  final int processingTime;
  final String processingText;
}

// Lớp lưu thông tin file
class FileInfo {
  FileInfo({required this.size, required this.width, required this.height});
  final int size;
  final double width;
  final double height;

  Size get dimension => Size(width, height);
}

extension on File {
  Size get size {
    final data = readAsBytesSync();
    final img.Image image = img.decodeImage(data)!;
    return Size(image.width.toDouble(), image.height.toDouble());
  }
}
