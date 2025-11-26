import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class Detection {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final int classIndex;
  final double score;

  Detection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.classIndex,
    required this.score,
  });

  @override
  String toString() =>
      'Detection(cls:$classIndex score:${score.toStringAsFixed(3)} '
          'box:[${x1.toStringAsFixed(1)},${y1.toStringAsFixed(1)},'
          '${x2.toStringAsFixed(1)},${y2.toStringAsFixed(1)}])';
}

class YoloDetector {
  YoloDetector._();
  static final instance = YoloDetector._();

  late Interpreter _interpreter;
  late List<int> _inputShape;
  bool _initialized = false;

  Future<void> init(String assetPath, {InterpreterOptions? options}) async {
    if (_initialized) return;
    _interpreter = await Interpreter.fromAsset(assetPath, options: options);
    final inputTensor = _interpreter.getInputTensor(0);
    _inputShape = inputTensor.shape; // [1,H,W,3]
    _initialized = true;
    debugPrint("YOLO init: inputShape=$_inputShape");
  }

  Future<List<Detection>> detectFromFile(
      File imageFile, {
        double scoreThreshold = 0.2,
      }) async {
    if (!_initialized) {
      throw Exception("Call init() first");
    }

    // 1. 이미지 로드
    final bytes = await imageFile.readAsBytes();
    final oriImage = img.decodeImage(bytes);
    if (oriImage == null) return [];

    final int inH = _inputShape[1];
    final int inW = _inputShape[2];

    // 2. Resize (no letterbox)
    final resized = img.copyResize(
      oriImage,
      width: inW,
      height: inH,
    );

    // 3. Normalize float32
    final input = List.generate(
      1,
          (_) => List.generate(inH, (y) {
        return List.generate(inW, (x) {
          final p = resized.getPixel(x, y);
          return [
            p.r / 255.0,
            p.g / 255.0,
            p.b / 255.0,
          ];
        });
      }),
    );

    debugPrint("resize 완료");

    // 4. Output 미리 생성 (Float32List 1D)
    final outputTensor = _interpreter.getOutputTensor(0);
    final shape = outputTensor.shape; // [1, 5, 21504]

    // 3D 리스트로 미리 생성
        final output = List.generate(
          shape[0], // 1
              (_) => List.generate(
            shape[1], // 5
                (_) => List.filled(shape[2], 0.0), // 21504
          ),
        );

    // Inference 실행
    _interpreter.run(input, output);

    debugPrint("interpret 완료");


    // output: [1][5][21504]
    final detections = <Detection>[];
    final batch = output[0]; // batch 0
    final B = batch[0].length; // 21504

    for (int i = 0; i < B; i++) {
      final score = batch[4][i]; // 4번 채널 = score
      if (score < scoreThreshold) continue;

      final cx = batch[0][i] * oriImage.width;
      final cy = batch[1][i] * oriImage.height;
      final w  = batch[2][i] * oriImage.width;
      final h  = batch[3][i] * oriImage.height;

      final x1 = cx - w / 2;
      final y1 = cy - h / 2;
      final x2 = cx + w / 2;
      final y2 = cy + h / 2;

      detections.add(
        Detection(
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          classIndex: 0, // class 없으면 0 고정
          score: score,
        ),
      );
    }

// Score 기준 정렬 후 반환
    detections.sort((a, b) => b.score.compareTo(a.score));
    return detections;

  }

  /// Crop function
  Future<File> cropImageFile(File originalFile, Detection box) async {
    final bytes = await originalFile.readAsBytes();
    final oriImage = img.decodeImage(bytes)!;

    final left = max(0, box.x1.round());
    final top = max(0, box.y1.round());
    final right = min(oriImage.width, box.x2.round());
    final bottom = min(oriImage.height, box.y2.round());

    final cropped = img.copyCrop(
      oriImage,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );

    final temp = await getTemporaryDirectory();
    final path =
        '${temp.path}/crop_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return File(path)..writeAsBytesSync(img.encodeJpg(cropped, quality: 90));
  }
}
