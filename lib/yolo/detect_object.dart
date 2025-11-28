import 'dart:io';
import 'dart:math';

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

  double _sigmoid(double x) => 1 / (1 + exp(-x));

  Future<List<Detection>> detectFromFile(
      File imageFile, {
        double scoreThreshold = 0.3,
      }) async {
    if (!_initialized) throw Exception("Call init() first");

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
            p.r.toDouble() / 255.0,
            p.g.toDouble() / 255.0,
            p.b.toDouble() / 255.0,
          ];
        });
      }),
    );

    debugPrint("resize 완료");

    // 4. Output 미리 생성
    final outputTensor = _interpreter.getOutputTensor(0);
    final shape = outputTensor.shape; // [1,5,21504]

    final output = List.generate(
      shape[0],
          (_) => List.generate(
        shape[1],
            (_) => List.filled(shape[2], 0.0),
      ),
    );

    // 5. Inference
    _interpreter.run(input, output);
    debugPrint("interpret 완료");

    final detections = <Detection>[];
    final batch = output[0];
    final B = batch[0].length;

    for (int i = 0; i < B; i++) {
      final score = _sigmoid(batch[4][i].toDouble());
      if (score < scoreThreshold) continue;

      final cx = batch[0][i].toDouble() * oriImage.width;
      final cy = batch[1][i].toDouble() * oriImage.height;
      final w = batch[2][i].toDouble() * oriImage.width;
      final h = batch[3][i].toDouble() * oriImage.height;

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
          classIndex: 0,
          score: score,
        ),
      );
    }

    // NMS 대체: 최대 영역 박스 하나만 반환
    if (detections.length > 1) {
      detections.sort((a, b) {
        final areaA = (a.x2 - a.x1) * (a.y2 - a.y1);
        final areaB = (b.x2 - b.x1) * (b.y2 - b.y1);
        return areaB.compareTo(areaA);
      });
      return [detections.first];
    }

    return detections;
  }

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
