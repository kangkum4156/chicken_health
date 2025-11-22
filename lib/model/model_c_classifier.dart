import 'dart:io';
import 'dart:math';

class ModelCClassifier {
  ModelCClassifier._internal();

  static final ModelCClassifier instance = ModelCClassifier._internal();

  bool _isLoaded = false;

  Future<void> loadModel() async {
    if (_isLoaded) return;

    // TODO: 실제 TFLite 모델 C 로딩
    await Future.delayed(const Duration(milliseconds: 300));

    _isLoaded = true;
  }

  Future<String> classify(File imageFile) async {
    if (!_isLoaded) {
      await loadModel();
    }

    final labels = [
      '정상 (모델 C)',
      '호흡기 + 소화기 복합 질병 의심 (모델 C)',
      '긴급 진료 필요 (모델 C)',
    ];

    final random = Random();
    final label = labels[random.nextInt(labels.length)];
    final confidence = 0.6 + random.nextDouble() * 0.4;

    return '$label\n신뢰도: ${(confidence * 100).toStringAsFixed(1)}%';
  }
}
