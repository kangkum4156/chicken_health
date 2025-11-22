import 'package:flutter/material.dart';

import 'screens/model_screen.dart';
import 'model/model_a_classifier.dart';
import 'model/model_b_classifier.dart';
import 'model/model_c_classifier.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChickenDiseaseApp());
}

class ChickenDiseaseApp extends StatelessWidget {
  const ChickenDiseaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '닭 질병 감지',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.orange,
      ),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return ModelScreen(
          key: const ValueKey('modelA'),      // ← 탭마다 다른 key
          title: '모델 A 예측 결과',
          runButtonText: '모델 A 실행',
          onClassify: (file) => ModelAClassifier.instance.classify(file),
        );
      case 1:
        return ModelScreen(
          key: const ValueKey('modelB'),
          title: '모델 B 예측 결과',
          runButtonText: '모델 B 실행',
          onClassify: (file) => ModelBClassifier.instance.classify(file),
        );
      case 2:
      default:
        return ModelScreen(
          key: const ValueKey('modelC'),
          title: '모델 C 예측 결과',
          runButtonText: '모델 C 실행',
          onClassify: (file) => ModelCClassifier.instance.classify(file),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          switch (_selectedIndex) {
            0 => '모델 A - 질병 감지',
            1 => '모델 B - 질병 감지',
            2 => '모델 C - 질병 감지',
            _ => '닭 질병 감지',
          },
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.filter_1),
            label: '모델 A',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.filter_2),
            label: '모델 B',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.filter_3),
            label: '모델 C',
          ),
        ],
      ),
    );
  }
}
