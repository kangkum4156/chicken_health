import 'dart:io';

import 'package:image_picker/image_picker.dart';

class CameraService {
  CameraService._internal();

  static final CameraService instance = CameraService._internal();

  final ImagePicker _picker = ImagePicker();

  // 카메라로 사진 촬영
  Future<File?> takePicture() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (file == null) return null;
    return File(file.path);
  }

  // 필요하다면 갤러리에서 선택하는 기능도 추가 가능
  Future<File?> pickFromGallery() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (file == null) return null;
    return File(file.path);
  }
}
