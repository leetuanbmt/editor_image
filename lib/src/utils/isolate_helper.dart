import 'dart:async';
import 'dart:isolate';

import 'package:uuid/uuid.dart';

import 'logger.dart';

/// Type definition for processor functions
typedef ProcessorFunction<I, O> = FutureOr<O> Function(I input);

/// A registry of processor functions that can be accessed by ID across isolates
class _ProcessorRegistry {
  /// Private constructor
  _ProcessorRegistry._();

  /// Factory constructor to return singleton
  factory _ProcessorRegistry() => _instance;

  /// Singleton instance
  static final _ProcessorRegistry _instance = _ProcessorRegistry._();

  /// Map of processor functions by ID
  final Map<String, Function> _processors = {};

  /// Register a processor function
  String registerProcessor<I, O>(ProcessorFunction<I, O> processor) {
    final id = const Uuid().v4();
    _processors[id] = processor;
    Logger.d('registered processor: $id');
    return id;
  }

  /// Get a processor function by ID
  ProcessorFunction<I, O>? getProcessor<I, O>(String id) {
    Logger.d('registered getProcessor: $id');
    Logger.d('get list of processors: ${_processors.keys}');

    final processor = _processors[id];
    if (processor == null) return null;

    return processor as ProcessorFunction<I, O>;
  }

  /// Remove a processor
  void removeProcessor(String id) {
    _processors.remove(id);
  }
}

/// A message to send to the isolate worker
class _IsolateMessage<I> {
  _IsolateMessage({
    required this.processorId,
    required this.input,
    required this.responsePort,
  });

  final String processorId;
  final I input;
  final SendPort responsePort;
}

/// A response from the isolate worker
class _IsolateResponse<O> {
  _IsolateResponse({required this.result, this.error, this.stackTrace});

  final O? result;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isSuccess => error == null;
}

/// The isolate worker function
void _isolateWorker(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((message) async {
    if (message is _IsolateMessage) {
      try {
        // Get the processor function from the registry
        final processor = _ProcessorRegistry().getProcessor(
          message.processorId,
        );

        if (processor == null) {
          message.responsePort.send(
            _IsolateResponse(
              result: null,
              error: 'Processor not found: ${message.processorId}',
              stackTrace: StackTrace.current,
            ),
          );
          return;
        }

        // Process the input
        final result = await processor(message.input);

        // Send the result back
        message.responsePort.send(_IsolateResponse(result: result));
      } catch (e, stackTrace) {
        Logger.e('Error in isolate worker: $e');
        Logger.e('Stack trace: $stackTrace');

        // Send the error back
        message.responsePort.send(
          _IsolateResponse(result: null, error: e, stackTrace: stackTrace),
        );
      }
    }
  });
}

/// A generic helper class to manage isolate operations
class IsolateHelper<I, O> {
  /// Create a new IsolateHelper
  IsolateHelper({
    required ProcessorFunction<I, O> processor,
    this.timeoutDuration = const Duration(seconds: 60),
  }) {
    // Register the processor function
    _processorId = _ProcessorRegistry().registerProcessor<I, O>(processor);
  }

  /// The ID of the processor function
  late final String _processorId;

  /// Timeout duration for requests
  final Duration timeoutDuration;

  /// Shared isolate instance
  static Isolate? _isolate;

  /// Shared receive port
  static ReceivePort? _receivePort;

  /// Shared send port
  static SendPort? _sendPort;

  /// Initialization completer
  static Completer<void>? _initCompleter;

  /// Initialize the isolate
  static Future<void> _initialize() async {
    // If already initialized, return
    if (_sendPort != null) return;

    // If initialization is in progress, wait for it
    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }

    _initCompleter = Completer<void>();

    try {
      Logger.d('Initializing isolate helper...');

      // Create the receive port
      _receivePort = ReceivePort();

      // Spawn the isolate
      _isolate = await Isolate.spawn(
        _isolateWorker,
        _receivePort!.sendPort,
        errorsAreFatal: true,
        onExit: _receivePort!.sendPort,
        onError: _receivePort!.sendPort,
      );

      // Get the send port
      _sendPort = await _receivePort!.first as SendPort;

      Logger.d('Isolate helper initialized successfully');
      _initCompleter!.complete();
    } catch (e, stackTrace) {
      Logger.e('Error initializing isolate helper: $e');
      Logger.e('Stack trace: $stackTrace');

      // Clean up
      _cleanup();

      // Complete with error
      _initCompleter!.completeError(e, stackTrace);
      _initCompleter = null;

      // Rethrow
      rethrow;
    }
  }

  /// Clean up the isolate
  static void _cleanup() {
    _isolate?.kill();
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;
  }

  /// Process a request in the isolate
  Future<O> process(I input) async {
    // Initialize the isolate
    await _initialize();

    // Create a receive port for the response
    final responsePort = ReceivePort();

    // Generate a request ID

    try {
      // Create the message
      final message = _IsolateMessage<I>(
        processorId: _processorId,
        input: input,
        responsePort: responsePort.sendPort,
      );

      // Send the message
      _sendPort!.send(message);

      // Wait for the response
      final response =
          await responsePort.first.timeout(
                timeoutDuration,
                onTimeout: () {
                  responsePort.close();
                  throw TimeoutException(
                    'Processing timeout after ${timeoutDuration.inSeconds} seconds',
                  );
                },
              )
              as _IsolateResponse;

      // Close the response port
      responsePort.close();

      // Handle the response
      if (response.isSuccess) {
        return response.result as O;
      } else {
        throw response.error ?? 'Unknown error';
      }
    } catch (e, stackTrace) {
      Logger.e('Error processing request: $e');
      Logger.e('Stack trace: $stackTrace');

      // Close the response port
      responsePort.close();

      // Rethrow
      rethrow;
    }
  }

  /// Dispose the helper
  void dispose() {
    _ProcessorRegistry().removeProcessor(_processorId);
  }

  /// Dispose all helpers and clean up the isolate
  static void disposeAll() {
    _cleanup();
  }
}
