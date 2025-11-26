import 'dart:io';

import 'package:flutter/material.dart';

import '../camera/camera_service.dart';
import '../widgets/primary_button.dart';
import '../widgets/prediction_card.dart';
import '../yolo/detect_object.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 이미지 파일을 받아서 예측 텍스트를 돌려주는 함수 타입
typedef ClassifyFunc = Future<String> Function(File imageFile);

class ModelScreen extends StatefulWidget {
  final String title;          // 예: "모델 A 예측 결과"
  final String runButtonText;  // 예: "모델 A 실행"
  final ClassifyFunc onClassify;

  const ModelScreen({
    super.key,
    required this.title,
    required this.runButtonText,
    required this.onClassify,
  });

  @override
  State<ModelScreen> createState() => _ModelScreenState();
}

class _ModelScreenState extends State<ModelScreen> {
  File? _imageFile;
  String? _resultText;
  bool _isLoading = false;

  Future<void> checkAsset() async {
    try {
      final data = await rootBundle.load('assets/models/yolov11_f32.tflite');
      print('Asset loaded, size: ${data.lengthInBytes}');
    } catch (e) {
      print('Asset load failed: $e');
    }
  }

  /// 카메라에서 촬영
  Future<void> _pickFromCamera() async {
    final file = await CameraService.instance.takePicture();
    if (file == null) return;

    setState(() {
      _imageFile = file;
      _resultText = null;
    });
  }

  /// 갤러리에서 선택
  Future<void> _pickFromGallery() async {
    final file = await CameraService.instance.pickFromGallery();
    if (file == null) return;

    setState(() {
      _imageFile = file;
      _resultText = null;
    });
  }

  /// 사진 촬영 버튼 눌렀을 때: 바텀시트로 카메라/갤러리 선택
  Future<void> _selectImageSource() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('사진 촬영'),
                onTap: () async {
                  Navigator.pop(context); // 바텀시트 닫기
                  await _pickFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('갤러리에서 선택'),
                onTap: () async {
                  Navigator.pop(context); // 바텀시트 닫기
                  await _pickFromGallery();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// "모델 실행" 버튼을 눌렀을 때
  Future<void> _runModel() async {
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 사진을 촬영하거나 선택해 주세요.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 여기서 실제 모델(A/B/C)이 돌아감
      final result = await widget.onClassify(_imageFile!);
      setState(() => _resultText = result);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('모델 실행 중 오류: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _detectObject() async {
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 사진을 선택하세요!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      debugPrint("객체 탐지 시작");
      final dets = await YoloDetector.instance.detectFromFile(
        _imageFile!,
        scoreThreshold: 0.25,
      );

      if (dets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('객체를 찾지 못했습니다.')),
        );
        return;
      }

      // 👇 여기에서 "최상위 confidence 하나" 뽑기
      dets.sort((a, b) => b.score.compareTo(a.score));
      final best = dets.first;

      final croppedFile = await YoloDetector.instance.cropImageFile(
        _imageFile!,
        best,
      );

      final confidence = (best.score * 100).toStringAsFixed(1);

      setState(() {
        _imageFile = croppedFile;
        _resultText = 'Confidence: $confidence%';
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('객체 탐지 중 오류: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: _imageFile == null
                  ? const Text(
                '버튼을 눌러 닭 사진을 촬영하거나\n갤러리에서 선택하세요.',
                textAlign: TextAlign.center,
              )
                  : Image.file(_imageFile!),
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            text: '사진 촬영',
            onPressed: _selectImageSource,
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            text: '객체 탐지',
            onPressed: _detectObject,
            isLoading: _isLoading,
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            text: widget.runButtonText,
            onPressed: _runModel,
            isLoading: _isLoading,
          ),
          PredictionCard(
            title: widget.title,
            resultText: _resultText,
          ),
        ],
      ),
    );
  }
}
