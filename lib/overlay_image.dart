import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'image_processor.dart';
import 'src/utils/logger.dart';

class OverlayImageEditorScreen extends StatefulWidget {
  const OverlayImageEditorScreen({super.key});

  @override
  State<OverlayImageEditorScreen> createState() =>
      _OverlayImageEditorScreenState();
}

class _OverlayImageEditorScreenState extends State<OverlayImageEditorScreen> {
  File? _backgroundImage;
  File? _overlayImage;
  final ImagePicker _picker = ImagePicker();

  // Overlay position and size (in display coordinates)
  Offset _overlayPosition = const Offset(50, 50);
  double _overlayWidth = 100;
  double _overlayHeight = 100;

  // For drag
  Offset? _dragStart;
  Offset? _overlayStartPosition;

  // For image display size
  double _displayedBgWidth = 1;
  double _displayedBgHeight = 1;

  // For result
  bool _loaderImage = false;
  bool _processing = false;

  Future<void> _pickBackgroundImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _backgroundImage = File(image.path);
        _loaderImage = false;
      });
    }
  }

  Future<void> _pickOverlayImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _overlayImage = File(image.path);
      });
    }
  }

  void _onPanStart(DragStartDetails details) {
    _dragStart = details.localPosition;
    _overlayStartPosition = _overlayPosition;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dragStart != null && _overlayStartPosition != null) {
      final Offset delta = details.localPosition - _dragStart!;
      setState(() {
        _overlayPosition = _overlayStartPosition! + delta;
      });
    }
  }

  Future<void> _onConfirm() async {
    if (_backgroundImage == null || _overlayImage == null) {
      return;
    }
    setState(() {
      _processing = true;
    });
    // Get original background image size
    final decodedBg = await decodeImageFromList(
      _backgroundImage!.readAsBytesSync(),
    );

    final double originalBgWidth = decodedBg.width.toDouble();
    final double originalBgHeight = decodedBg.height.toDouble();
    // Calculate scale between displayed and original
    final double scaleX = originalBgWidth / _displayedBgWidth;
    final double scaleY = originalBgHeight / _displayedBgHeight;
    // Calculate overlay position and size in original image coordinates
    final double overlayX = _overlayPosition.dx * scaleX;
    final double overlayY = _overlayPosition.dy * scaleY;
    final double overlayW = _overlayWidth * scaleX;
    final double overlayH = _overlayHeight * scaleY;
    // Output path
    final String outputPath =
        '${_backgroundImage!.parent.path}/overlay_result_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final StringBuffer config = StringBuffer();
    config.writeln('Input path ${_backgroundImage!.path}');
    config.writeln('Output path $outputPath');
    config.writeln('Overlay path ${_overlayImage!.path}');
    config.writeln('Overlay X $overlayX');
    config.writeln('Overlay Y $overlayY');
    config.writeln('Overlay width $overlayW');
    config.writeln('Overlay height $overlayH');
    Logger.d(config.toString());
    try {
      await ImageProcessor.instance.execute(
        inputPath: _backgroundImage!.path,
        outputPath: outputPath,
        config: OverlayConfig(
          overlayPath: _overlayImage!.path,
          overlayX: overlayX,
          overlayY: overlayY,
          overlayWidth: overlayW,
          overlayHeight: overlayH,
          quality: 90,
        ),
        onCompleted: (file) {
          showDialog(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: const Text('Overlay success!'),
                  content: Image.file(File(outputPath)),
                ),
          );
        },
        onError: (error, stackTrace) {
          Logger.d('Error: $error');
        },
      );
    } catch (e) {
      Logger.d('Error: $e');
    } finally {
      setState(() {
        _processing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Overlay Image Editor')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _pickBackgroundImage,
                    child: const Text('Pick Background'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _pickOverlayImage,
                    child: const Text('Pick Overlay'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child:
                  _backgroundImage == null
                      ? const Center(
                        child: Text('No background image selected'),
                      )
                      : LayoutBuilder(
                        builder: (context, constraints) {
                          final double maxW = constraints.maxWidth;
                          final double maxH = constraints.maxHeight;
                          return Stack(
                            children: [
                              Image.file(
                                _backgroundImage!,
                                width: maxW,
                                height: maxH,
                                fit: BoxFit.contain,
                                // Save displayed size for coordinate mapping
                                frameBuilder: (
                                  context,
                                  child,
                                  frame,
                                  wasSynchronouslyLoaded,
                                ) {
                                  if (_loaderImage) return child;
                                  _loaderImage = true;

                                  WidgetsBinding.instance.endOfFrame.then((_) {
                                    setState(() {
                                      _displayedBgWidth = maxW;
                                      _displayedBgHeight = maxH;
                                    });
                                  });
                                  return child;
                                },
                              ),
                              if (_overlayImage != null)
                                Positioned(
                                  left: _overlayPosition.dx,
                                  top: _overlayPosition.dy,
                                  child: GestureDetector(
                                    onPanStart: _onPanStart,
                                    onPanUpdate: _onPanUpdate,
                                    child: SizedBox(
                                      width: _overlayWidth,
                                      height: _overlayHeight,
                                      child: Image.file(
                                        _overlayImage!,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Overlay size:'),
                Expanded(
                  child: Slider(
                    value: _overlayWidth,
                    min: 30,
                    max: 300,
                    label: 'Width: ${_overlayWidth.toInt()}',
                    onChanged: (v) {
                      setState(() {
                        _overlayWidth = v;
                      });
                    },
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _overlayHeight,
                    min: 30,
                    max: 300,
                    label: 'Height: ${_overlayHeight.toInt()}',
                    onChanged: (v) {
                      setState(() {
                        _overlayHeight = v;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _processing ? null : _onConfirm,
              child: const Text('Confirm & Overlay'),
            ),
          ],
        ),
      ),
    );
  }
}
