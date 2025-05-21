import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:uuid/uuid.dart';

import 'image_processor_bindings_generated.dart';
import 'src/utils/logger.dart';

abstract class ImageEditorConfig {
  ImageEditorConfig({
    this.inputPath = '',
    this.outPath = '',
    this.id = '',
    this.quality = 80,
  });
  String inputPath;
  String outPath;
  int quality;
  String id;
}

class CropConfig extends ImageEditorConfig {
  CropConfig({
    super.id,
    super.quality,
    required this.cropWidth,
    required this.cropHeight,
    required this.cropX,
    required this.cropY,
  });
  final double cropWidth;
  final double cropHeight;
  final double cropX;
  final double cropY;
}

class ResizeConfig extends ImageEditorConfig {
  ResizeConfig({
    super.id,
    super.quality,
    required this.width,
    required this.height,
  });
  final double width;
  final double height;
}

class OverlayConfig extends ImageEditorConfig {
  OverlayConfig({
    super.id,
    super.quality,
    required this.overlayPath,
    required this.overlayWidth,
    required this.overlayHeight,
    required this.overlayX,
    required this.overlayY,
  });
  final String overlayPath;
  final double overlayWidth;
  final double overlayHeight;
  final double overlayX;
  final double overlayY;

  @override
  String toString() {
    return 'OverlayConfig(overlayPath: $overlayPath, overlayWidth: $overlayWidth, overlayHeight: $overlayHeight, overlayX: $overlayX, overlayY: $overlayY)';
  }
}

class CropAndResizeConfig extends ImageEditorConfig {
  CropAndResizeConfig({
    required this.cropWidth,
    required this.cropHeight,
    required this.cropX,
    required this.cropY,
    required this.width,
    required this.height,
    super.quality = 80,
  });
  final double cropWidth;
  final double cropHeight;
  final double cropX;
  final double cropY;
  final double width;
  final double height;
}

class FixImageOrientationConfig extends ImageEditorConfig {
  FixImageOrientationConfig({
    required super.id,
    required super.inputPath,
    required super.outPath,
    super.quality = 80,
  });
}

class ImageEditorResult {
  ImageEditorResult({
    required this.id,
    required this.success,
    this.errorMessage,
    required this.processingTime,
    required this.processingText,
  });
  final bool success;
  final String? errorMessage;
  final int processingTime;
  final String processingText;
  final String id;
}

const _uuid = Uuid();

final _requests = <String, Completer<ImageEditorResult>>{};

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
            Logger.e('Do not find the completer for ID: ${data.id}');
          }
          return;
        }
        Logger.e('No data type support: ${data.runtimeType}');
      });

  await Isolate.spawn((SendPort sendPort) async {
    final ReceivePort helperReceivePort =
        ReceivePort()..listen((data) async {
          if (data is ImageEditorConfig) {
            try {
              final result = ImageProcessor.instance.processImage(data);
              sendPort.send(result);
            } catch (e, stackTrace) {
              Logger.e('Error in Isolate: $e\n$stackTrace');
              sendPort.send(
                ImageEditorResult(
                  id: data.id,
                  success: false,
                  errorMessage: 'Processing errors in Isolate: $e',
                  processingTime: 0,
                  processingText: '0 ms',
                ),
              );
            }
            return;
          }
          Logger.e('No data type support: ${data.runtimeType}');
        });

    sendPort.send(helperReceivePort.sendPort);
  }, receivePort.sendPort);

  return completer.future;
}();

Future<bool> _ensureIsolateStarted() async {
  try {
    await _helperIsolateSendPort.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException('Start Isolate too much time'),
    );
    return true;
  } catch (e) {
    Logger.e('Error starting isolate: $e');
    return false;
  }
}

String _generateRequestId() {
  return _uuid.v4();
}

Future<ImageEditorResult> _sendRequest(ImageEditorConfig config) async {
  final isIsolateReady = await _ensureIsolateStarted();
  if (!isIsolateReady) {
    return ImageEditorResult(
      id: config.id,
      success: false,
      errorMessage: 'Cannot start image processing isolate',
      processingTime: 0,
      processingText: '0 ms',
    );
  }

  try {
    final SendPort sendPort = await _helperIsolateSendPort;
    final completer = Completer<ImageEditorResult>();
    _requests[config.id] = completer;
    sendPort.send(config);

    return await completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _requests.remove(config.id);
        return ImageEditorResult(
          id: config.id,
          success: false,
          errorMessage: 'Image processing timeout',
          processingTime: 60000,
          processingText: '60000 ms (timeout)',
        );
      },
    );
  } catch (e) {
    Logger.e('Error sending request: $e');
    return ImageEditorResult(
      id: config.id,
      success: false,
      errorMessage: 'Error sending request: $e',
      processingTime: 0,
      processingText: '0 ms',
    );
  }
}

class ImageProcessor {
  ImageProcessor._() {
    _initBindings();
    _checkLibrarySymbols();
  }
  static ImageProcessor? _instance;
  static ImageProcessor get instance => _instance ??= ImageProcessor._();

  late ImageProcessorBindings _bindings;

  final Map<String, bool> _symbolCache = {};

  Map<String, bool> get symbolCache => _symbolCache;

  static const int defaultTimeout = 30000;

  final symbolsToCheck = [
    'CropImage',
    'ResizeImage',
    'CropAndResizeImage',
    'OverlayImage',
    'ApplyBoardOverlay',
    'CropAndResizeImage',
    'FixImageOrientation',
  ];

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
          'Platform not supported: ${Platform.operatingSystem}',
        );
      }
    } catch (e) {
      rethrow;
    }
  }();

  void _initBindings() {
    try {
      _bindings = ImageProcessorBindings(_library);
      Logger.d('Successfully initialized Bindings');
    } catch (e) {
      Logger.e(e.toString());
    }
  }

  bool providesSymbol(String symbol) {
    try {
      if (_symbolCache.containsKey(symbol)) {
        return _symbolCache[symbol]!;
      }

      final result = _library.providesSymbol(symbol);

      _symbolCache[symbol] = result;
      return result;
    } catch (e) {
      Logger.e('Error checking symbol $symbol: $e');
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
      Logger.e('Symbol test error: $e');
    }
  }

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
          data.quality,
        );
      } else if (data is ResizeConfig) {
        result = _bindings.resizeImage(
          data.inputPath.toNativeUtf8().cast<Char>(),
          data.outPath.toNativeUtf8().cast<Char>(),
          data.width,
          data.height,
          data.quality,
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
          data.quality,
        );
      } else if (data is CropAndResizeConfig) {
        result = _bindings.cropAndResizeImage(
          data.inputPath.toNativeUtf8().cast<Char>(),
          data.outPath.toNativeUtf8().cast<Char>(),
          data.cropX,
          data.cropY,
          data.cropWidth,
          data.cropHeight,
          data.width,
          data.height,
          data.quality,
        );
      } else if (data is FixImageOrientationConfig) {
        result = _bindings.fixImageOrientation(
          data.inputPath.toNativeUtf8().cast<Char>(),
          data.outPath.toNativeUtf8().cast<Char>(),
          data.quality,
        );
      } else {
        stopwatch.stop();
        return ImageEditorResult(
          id: data.id,
          success: false,
          errorMessage:
              'The type of configuration is not supported: ${data.runtimeType}',
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

  Future<String?> execute({
    required String inputPath,
    required String outputPath,
    required ImageEditorConfig config,
    void Function(File file)? onCompleted,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      config.inputPath = inputPath;
      config.outPath = outputPath;
      config.id = _generateRequestId();
      final result = await _sendRequest(config);
      Logger.d('Time execute: ${result.processingTime} ms');
      onCompleted?.call(File(outputPath));
      return result.success ? outputPath : null;
    } catch (e, stackTrace) {
      onError?.call(e, stackTrace);
      return null;
    }
  }
}
