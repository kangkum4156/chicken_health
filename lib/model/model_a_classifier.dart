import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class ModelAClassifier {
  ModelAClassifier._();
  static final instance = ModelAClassifier._();

  late final Interpreter _interpreter;
  late final List<String> _labels;
  late final List<int> _inputShape; // [1, 3, 224, 224] 또는 [1, 224, 224, 3]

  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;

    _interpreter = await Interpreter.fromAsset(
      'assets/models/efficientnet_final.tflite',
    );

    final inputTensor = _interpreter.getInputTensor(0);
    _inputShape = inputTensor.shape; // 예: [1, 3, 224, 224] or [1, 224, 224, 3]
    // 디버그용: 실제 쉐이프 확인하고 싶으면 한 번 찍어봐도 됨
    // debugPrint('ModelA inputShape: $_inputShape');

    // label.txt 로드
    final labelsStr =
    await rootBundle.loadString('assets/models/label.txt');
    _labels = labelsStr
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    _initialized = true;
  }

  /// ModelScreen.onClassify 에 그대로 넘길 함수
  /// Future<String> Function(File imageFile)
  Future<String> classify(File imageFile) async {
    await _init();

    // 1) 이미지 디코딩
    final bytes = await imageFile.readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return '이미지 디코딩 실패';

    // 2) 레이아웃 판별: NCHW vs NHWC
    final isNCHW = _inputShape.length == 4 && _inputShape[1] == 3;
    late int h;
    late int w;

    if (isNCHW) {
      // [1, 3, H, W]
      h = _inputShape[2];
      w = _inputShape[3];
    } else {
      // [1, H, W, 3] 라고 가정
      h = _inputShape[1];
      w = _inputShape[2];
    }

    image = img.copyResize(image, height: h, width: w);

    // 3) PyTorch ImageNet 정규화 값
    const mean = [0.485, 0.456, 0.406]; // R, G, B
    const std = [0.229, 0.224, 0.225];

    // 4) 입력 텐서 만들기 (float32, 0~1 스케일 + mean/std 정규화)
    dynamic input;

    if (isNCHW) {
      // [1, 3, H, W]
      input = List.generate(
        1,
            (_) => List.generate(
          3,
              (c) => List.generate(
            h,
                (y) => List.generate(
              w,
                  (x) {
                final p = image!.getPixel(x, y);
                final raw = (c == 0)
                    ? p.r.toDouble()
                    : (c == 1)
                    ? p.g.toDouble()
                    : p.b.toDouble();

                // 0~1 스케일 후 채널별 정규화
                final v01 = raw / 255.0;
                final norm = (v01 - mean[c]) / std[c];
                return norm;
              },
            ),
          ),
        ),
      );
    } else {
      // [1, H, W, 3]
      input = List.generate(
        1,
            (_) => List.generate(
          h,
              (y) => List.generate(
            w,
                (x) {
              final p = image!.getPixel(x, y);

              final r01 = p.r.toDouble() / 255.0;
              final g01 = p.g.toDouble() / 255.0;
              final b01 = p.b.toDouble() / 255.0;

              final rn = (r01 - mean[0]) / std[0];
              final gn = (g01 - mean[1]) / std[1];
              final bn = (b01 - mean[2]) / std[2];

              return [rn, gn, bn];
            },
          ),
        ),
      );
    }

    // 5) 출력 버퍼 준비 (shape: [1, numClasses] = [1, 4])
    final outTensor = _interpreter.getOutputTensor(0);
    final outShape = outTensor.shape;
    final numClasses = outShape[1];

    final output = List.generate(
      1,
          (_) => List<double>.filled(numClasses, 0.0),
    );

    // 6) 추론 실행
    _interpreter.run(input, output);

    // 7) 가장 점수 높은 클래스 찾기 (argmax)
    final scores = output[0];
    int bestIdx = 0;
    double bestScore = scores[0];

    for (int i = 1; i < scores.length; i++) {
      if (scores[i] > bestScore) {
        bestScore = scores[i];
        bestIdx = i;
      }
    }

    final label = bestIdx < _labels.length
        ? _labels[bestIdx]
        : 'Unknown class $bestIdx';

    // 확률까지 보고 싶으면 이렇게 돌려도 됨:
    // return '$label  (${(bestScore * 100).toStringAsFixed(1)}%)';
    return label;
  }
}
