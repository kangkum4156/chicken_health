import 'package:flutter/material.dart';

class PredictionCard extends StatelessWidget {
  final String title;
  final String? resultText;

  const PredictionCard({
    super.key,
    required this.title,
    required this.resultText,
  });

  @override
  Widget build(BuildContext context) {
    if (resultText == null) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(top: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              resultText!,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
