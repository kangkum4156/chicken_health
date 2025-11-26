import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class ModelBClassifier {
  ModelBClassifier._();
  static final instance = ModelBClassifier._();

  late final Interpreter _interpreter;
  late final List<String> _labels;
  late final List<int> _inputShape; // [1, H, W, 3] 가정
  late final TensorType _inputType;
  late final TensorType _outputType;

  // 초기화 중복 호출 방지용
  Future<void>? _initFuture;

  Future<void> _init() {
    if (_initFuture != null) return _initFuture!;
    _initFuture = _doInit();
    return _initFuture!;
  }

  Future<void> _doInit() async {
    // 1) TFLite 모델 로드
    _interpreter = await Interpreter.fromAsset(
      'assets/models/mnv_final_int8.tflite',
    );

    // 2) 입력/출력 텐서 정보
    final inputTensor = _interpreter.getInputTensor(0);
    final outputTensor = _interpreter.getOutputTensor(0);

    _inputShape = inputTensor.shape; // 예: [1, H, W, 3]
    _inputType = inputTensor.type;   // float32 / int8 / uint8
    _outputType = outputTensor.type; // float32 / int8 / uint8

    // 3) 클래스 파일 로드
    // mnv_classes.txt 예:
    // 0 Coccidiosis - go to hospital
    // 1 Healthy!
    // 2 New Castle - go to hospital
    // 3 Salmonella - go to hospital
    final labelsStr =
    await rootBundle.loadString('assets/models/label_mobile.txt');

    _labels = labelsStr
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((line) {
      // Python: parts = line.split(maxsplit=1); classes.append(parts[1])
      final idx = line.indexOf(' ');
      if (idx >= 0 && idx + 1 < line.length) {
        // "0 Coccidiosis - go to hospital" -> "Coccidiosis - go to hospital"
        return line.substring(idx + 1).trim();
      }
      return line;
    })
        .toList();
  }

  /// Python infer_tflite()와 거의 동일한 동작
  Future<String> classify(File imageFile) async {
    await _init();

    // 1) 이미지 디코딩
    final bytes = await imageFile.readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) {
      return '이미지 디코딩 실패';
    }

    // 2) 입력 크기 (height, width = input_shape[1], input_shape[2])
    if (_inputShape.length != 4) {
      return '지원하지 않는 입력 shape: $_inputShape';
    }
    final int h = _inputShape[1];
    final int w = _inputShape[2];

    image = img.copyResize(image, height: h, width: w);

    // 3) 입력 텐서 생성
    // Python:
    //   if float32: img.astype(np.float32) / 255.0
    //   elif int8 : img.astype(np.int8)
    //   elif uint8: 그대로
    dynamic input;

    if (_inputType == TensorType.float32) {
      // [1, H, W, 3] float32, 0~1 스케일
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
              return [r01, g01, b01];
            },
          ),
        ),
      );
    } else if (_inputType == TensorType.int8) {
      // [1, H, W, 3] int8, 0~255 -> -128~127 (np.int8과 동일)
      int toInt8(num v) {
        int iv = v.toInt();
        if (iv < 0) iv = 0;
        if (iv > 255) iv = 255;
        return (iv >= 128) ? (iv - 256) : iv;
      }

      input = List.generate(
        1,
            (_) => List.generate(
          h,
              (y) => List.generate(
            w,
                (x) {
              final p = image!.getPixel(x, y);
              final r = toInt8(p.r);
              final g = toInt8(p.g);
              final b = toInt8(p.b);
              return [r, g, b];
            },
          ),
        ),
      );
    } else if (_inputType == TensorType.uint8) {
      // [1, H, W, 3] uint8, 0~255 그대로
      int clamp255(num v) {
        int iv = v.toInt();
        if (iv < 0) iv = 0;
        if (iv > 255) iv = 255;
        return iv;
      }

      input = List.generate(
        1,
            (_) => List.generate(
          h,
              (y) => List.generate(
            w,
                (x) {
              final p = image!.getPixel(x, y);
              final r = clamp255(p.r);
              final g = clamp255(p.g);
              final b = clamp255(p.b);
              return [r, g, b];
            },
          ),
        ),
      );
    } else {
      return '지원하지 않는 입력 타입: $_inputType';
    }

    // 4) 출력 버퍼 준비 (Python: output_details["shape"] = [1, numClasses])
    final outTensor = _interpreter.getOutputTensor(0);
    final outShape = outTensor.shape;
    if (outShape.length != 2 || outShape[0] != 1) {
      return '지원하지 않는 출력 shape: $outShape';
    }
    final int numClasses = outShape[1];

    dynamic output;
    if (_outputType == TensorType.float32) {
      output = List.generate(
        1,
            (_) => List<double>.filled(numClasses, 0.0),
      );
    } else if (_outputType == TensorType.int8 ||
        _outputType == TensorType.uint8) {
      // 양자화 출력 버퍼 (int8/uint8 공용)
      output = List.generate(
        1,
            (_) => List<int>.filled(numClasses, 0),
      );
    } else {
      return '지원하지 않는 출력 타입: $_outputType';
    }

    // 5) 추론 실행
    _interpreter.run(input, output);

    // 6) 출력 후처리 (dequantize + softmax용 logits)
    late List<double> logits;

    if (_outputType == TensorType.float32) {
      logits = (output[0] as List).map((e) => (e as num).toDouble()).toList();
    } else if (_outputType == TensorType.int8 ||
        _outputType == TensorType.uint8) {
      // int8/uint8 공통 dequantization: (q - zp) * scale
      final qParams = outTensor.params; // (scale, zeroPoint)
      final double scale = qParams.scale;
      final int zeroPoint = qParams.zeroPoint;

      final raw = (output[0] as List).cast<int>();
      logits = List<double>.generate(
        raw.length,
            (i) => (raw[i] - zeroPoint) * scale,
      );
    } else {
      return '지원하지 않는 출력 타입: $_outputType';
    }

    // 7) softmax → argmax
    final probs = _softmax(logits);

    int bestIdx = 0;
    double bestProb = probs[0];
    for (int i = 1; i < probs.length; i++) {
      if (probs[i] > bestProb) {
        bestProb = probs[i];
        bestIdx = i;
      }
    }

    final label = bestIdx < _labels.length
        ? _labels[bestIdx]
        : 'Unknown class $bestIdx';

    // 디버그가 필요하면 주석 풀고 확인
    // print('logits: $logits');
    // print('probs: $probs, bestIdx=$bestIdx, bestProb=$bestProb');

    return label;
  }

  // Python softmax와 동일
  List<double> _softmax(List<double> x) {
    final maxVal = x.reduce(math.max);
    final exps = x.map((v) => math.exp(v - maxVal)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((v) => v / sum).toList();
  }
}
