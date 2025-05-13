import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:uuid/uuid.dart';

import 'image_processor_bindings_generated.dart';
import 'src/utils/logger.dart';

abstract class ImageEditorConfig {
  final String inputPath;
  final String outPath;
  final String id;
  ImageEditorConfig({
    required this.inputPath,
    required this.outPath,
    required this.id,
  });
}

class CropConfig extends ImageEditorConfig {
  final double cropWidth;
  final double cropHeight;
  final double cropX;
  final double cropY;

  CropConfig({
    required super.id,
    required super.inputPath,
    required super.outPath,
    required this.cropWidth,
    required this.cropHeight,
    required this.cropX,
    required this.cropY,
  });
}

class ResizeConfig extends ImageEditorConfig {
  final double width;
  final double height;

  ResizeConfig({
    required super.inputPath,
    required super.outPath,
    required super.id,
    required this.width,
    required this.height,
  });
}

class OverlayConfig extends ImageEditorConfig {
  final String overlayPath;
  final double overlayWidth;
  final double overlayHeight;
  final double overlayX;
  final double overlayY;

  OverlayConfig({
    required super.id,
    required super.inputPath,
    required super.outPath,
    required this.overlayPath,
    required this.overlayWidth,
    required this.overlayHeight,
    required this.overlayX,
    required this.overlayY,
  });
}

class ApplyBoardOverlayConfig extends ImageEditorConfig {
  final String backgroundFile;
  final double width;
  final double height;
  final double x;
  final double y;

  ApplyBoardOverlayConfig({
    required super.id,
    required super.inputPath,
    required super.outPath,
    required this.backgroundFile,
    required this.width,
    required this.height,
    required this.x,
    required this.y,
  });
}

class ImageEditorResult {
  final bool success;
  final String? errorMessage;
  final int processingTime;
  final String processingText;
  final String id;
  ImageEditorResult({
    required this.id,
    required this.success,
    this.errorMessage,
    required this.processingTime,
    required this.processingText,
  });
}

// Tạo và lưu trữ id
final _uuid = Uuid();

// Mảng lưu trữ yêu cầu để chờ kết quả
final _requests = <String, Completer<ImageEditorResult>>{};

// Port giao tiếp với isolate helper
Future<SendPort> _helperIsolateSendPort = () async {
  final Completer<SendPort> completer = Completer<SendPort>();
  final ReceivePort receivePort =
      ReceivePort()..listen((data) {
        if (data is SendPort) {
          completer.complete(data);
          return;
        }
        if (data is ImageEditorResult) {
          final Completer<ImageEditorResult>? completer = _requests[data.id];
          if (completer != null && !completer.isCompleted) {
            completer.complete(data);
            _requests.remove(data.id);
          } else {
            Logger.e('Không tìm thấy completer cho id: ${data.id}');
          }
          return;
        }
        Logger.e('Không hỗ trợ loại dữ liệu: ${data.runtimeType}');
      });

  /// Khởi động isolate helper
  await Isolate.spawn((SendPort sendPort) async {
    final ReceivePort helperReceivePort =
        ReceivePort()..listen((data) async {
          if (data is ImageEditorConfig) {
            try {
              final result = ImageProcessor.instance.processImage(data);
              sendPort.send(result);
            } catch (e, stackTrace) {
              Logger.e('Lỗi trong isolate: $e\n$stackTrace');
              sendPort.send(
                ImageEditorResult(
                  id: data.id,
                  success: false,
                  errorMessage: 'error:Lỗi xử lý trong isolate: $e',
                  processingTime: 0,
                  processingText: '0 ms',
                ),
              );
            }
            return;
          }
          Logger.e('Không hỗ trợ loại dữ liệu: ${data.runtimeType}');
        });

    sendPort.send(helperReceivePort.sendPort);
  }, receivePort.sendPort);

  return completer.future;
}();

/// Kiểm tra isolate đã khởi động thành công chưa
Future<bool> _ensureIsolateStarted() async {
  try {
    await _helperIsolateSendPort.timeout(
      const Duration(seconds: 5),
      onTimeout:
          () => throw TimeoutException('Khởi động isolate quá thời gian'),
    );
    return true;
  } catch (e) {
    Logger.e('Lỗi khởi động isolate: $e');
    return false;
  }
}

/// Tạo ID mới cho request
String _generateRequestId() {
  return _uuid.v4();
}

/// Gửi request đến isolate và chờ kết quả
Future<ImageEditorResult> _sendRequest(ImageEditorConfig config) async {
  final isIsolateReady = await _ensureIsolateStarted();
  if (!isIsolateReady) {
    return ImageEditorResult(
      id: config.id,
      success: false,
      errorMessage: 'error:Không thể khởi động isolate xử lý ảnh',
      processingTime: 0,
      processingText: '0 ms',
    );
  }

  try {
    final SendPort sendPort = await _helperIsolateSendPort;
    final completer = Completer<ImageEditorResult>();
    _requests[config.id] = completer;
    sendPort.send(config);

    // Thêm timeout để tránh đợi vô hạn
    return await completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _requests.remove(config.id);
        return ImageEditorResult(
          id: config.id,
          success: false,
          errorMessage: 'error:Quá thời gian xử lý ảnh',
          processingTime: 60000,
          processingText: '60000 ms (timeout)',
        );
      },
    );
  } catch (e) {
    Logger.e('Lỗi khi gửi yêu cầu: $e');
    return ImageEditorResult(
      id: config.id,
      success: false,
      errorMessage: 'error:Lỗi gửi yêu cầu xử lý: $e',
      processingTime: 0,
      processingText: '0 ms',
    );
  }
}

class ImageProcessor {
  static ImageProcessor? _instance;
  static ImageProcessor get instance => _instance ??= ImageProcessor._();

  // Bindings đến thư viện native
  late ImageProcessorBindings _bindings;

  // Cache kết quả kiểm tra symbol
  final Map<String, bool> _symbolCache = {};

  Map<String, bool> get symbolCache => _symbolCache;

  static const int defaultTimeout = 30000;

  final symbolsToCheck = [
    'CropImage',
    'ResizeImage',
    'CropAndResizeImage',
    'OverlayImage',
    'ApplyBoardOverlay',
  ];

  /// Thông tin debug khi tải thư viện
  ImageProcessor._() {
    _initBindings();
    _checkLibrarySymbols();
  }

  /// Lấy thư viện native dựa trên nền tảng hiện tại
  final DynamicLibrary _library = () {
    const String libName = 'image_processor';
    try {
      if (Platform.isIOS) {
        return DynamicLibrary.process();
      } else if (Platform.isAndroid) {
        return DynamicLibrary.open('lib$libName.so');
      } else if (Platform.isMacOS) {
        return DynamicLibrary.open('$libName.framework/$libName');
      } else {
        throw UnsupportedError(
          'Nền tảng không được hỗ trợ: ${Platform.operatingSystem}',
        );
      }
    } catch (e) {
      rethrow;
    }
  }();

  void _initBindings() {
    try {
      _bindings = ImageProcessorBindings(_library);
      Logger.d('Đã khởi tạo bindings thành công');
    } catch (e) {
      Logger.e(e.toString());
    }
  }

  bool providesSymbol(String symbol) {
    try {
      // Kiểm tra cache trước
      if (_symbolCache.containsKey(symbol)) {
        return _symbolCache[symbol]!;
      }

      final result = _library.providesSymbol(symbol);

      // Lưu kết quả vào cache
      _symbolCache[symbol] = result;
      return result;
    } catch (e) {
      Logger.e('Lỗi kiểm tra symbol $symbol: $e');
      _symbolCache[symbol] = false;
      return false;
    }
  }

  void _checkLibrarySymbols() {
    try {
      for (final symbol in symbolsToCheck) {
        providesSymbol(symbol);
      }
    } catch (e) {
      Logger.e('Lỗi kiểm tra symbol: $e');
    }
  }

  // Xử lý ảnh trong isolate
  ImageEditorResult processImage(ImageEditorConfig data) {
    final stopwatch = Stopwatch()..start();

    try {
      Pointer<Char>? result;

      if (data is CropConfig) {
        result = _bindings.cropImage(
          data.inputPath.toNativeUtf8().cast<Char>(),
          data.outPath.toNativeUtf8().cast<Char>(),
          data.cropX,
          data.cropY,
          data.cropWidth,
          data.cropHeight,
        );
      } else if (data is ResizeConfig) {
        result = _bindings.resizeImage(
          data.inputPath.toNativeUtf8().cast<Char>(),
          data.outPath.toNativeUtf8().cast<Char>(),
          data.width,
          data.height,
        );
      } else if (data is OverlayConfig) {
        result = _bindings.overlayImage(
          data.inputPath.toNativeUtf8().cast<Char>(),
          data.overlayPath.toNativeUtf8().cast<Char>(),
          data.outPath.toNativeUtf8().cast<Char>(),
          data.overlayX,
          data.overlayY,
          data.overlayWidth,
          data.overlayHeight,
        );
      } else if (data is ApplyBoardOverlayConfig) {
        result = _bindings.applyBoardOverlay(
          data.inputPath.toNativeUtf8().cast<Char>(),
          data.outPath.toNativeUtf8().cast<Char>(),
          data.backgroundFile.toNativeUtf8().cast<Char>(),
          data.width,
          data.height,
          data.x,
          data.y,
        );
      } else {
        stopwatch.stop();
        return ImageEditorResult(
          id: data.id,
          success: false,
          errorMessage:
              'error:Loại cấu hình không được hỗ trợ: ${data.runtimeType}',
          processingTime: stopwatch.elapsedMilliseconds,
          processingText: '${stopwatch.elapsedMilliseconds} ms',
        );
      }

      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMilliseconds;
      final errorMsg = result.cast<Utf8>().toDartString();
      calloc.free(result);
      return ImageEditorResult(
        id: data.id,
        success: true,
        errorMessage: errorMsg,
        processingTime: elapsedMs,
        processingText: '$elapsedMs ms',
      );
    } catch (e) {
      stopwatch.stop();
      return ImageEditorResult(
        id: data.id,
        success: false,
        errorMessage: 'error:Lỗi xử lý trong isolate: $e',
        processingTime: stopwatch.elapsedMilliseconds,
        processingText: '${stopwatch.elapsedMilliseconds} ms',
      );
    }
  }

  // API Methods
  Future<ImageEditorResult> resizeImage({
    required String inputPath,
    required String outputPath,
    required double width,
    required double height,
  }) async {
    final config = ResizeConfig(
      id: _generateRequestId(),
      inputPath: inputPath,
      outPath: outputPath,
      width: width,
      height: height,
    );
    return await _sendRequest(config);
  }

  Future<ImageEditorResult> cropImage({
    required String inputPath,
    required String outputPath,
    required double x,
    required double y,
    required double width,
    required double height,
  }) async {
    final config = CropConfig(
      id: _generateRequestId(),
      inputPath: inputPath,
      outPath: outputPath,
      cropX: x,
      cropY: y,
      cropWidth: width,
      cropHeight: height,
    );
    return await _sendRequest(config);
  }

  Future<ImageEditorResult> overlayImage({
    required String baseImagePath,
    required String overlayImagePath,
    required String outputPath,
    required double x,
    required double y,
    required double width,
    required double height,
  }) async {
    final config = OverlayConfig(
      id: _generateRequestId(),
      inputPath: baseImagePath,
      outPath: outputPath,
      overlayPath: overlayImagePath,
      overlayX: x,
      overlayY: y,
      overlayWidth: width,
      overlayHeight: height,
    );
    return await _sendRequest(config);
  }

  Future<ImageEditorResult> applyBoardOverlay({
    required String inputPath,
    required String outputPath,
    required String backgroundFile,
    required double width,
    required double height,
    double x = 0,
    double y = 0,
  }) async {
    final config = ApplyBoardOverlayConfig(
      id: _generateRequestId(),
      inputPath: inputPath,
      outPath: outputPath,
      backgroundFile: backgroundFile,
      width: width,
      height: height,
      x: x,
      y: y,
    );
    return await _sendRequest(config);
  }
}
