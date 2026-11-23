
import 'package:flutter/material.dart';

class TestQuestionUploadScreen extends StatelessWidget {
  const TestQuestionUploadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Questions'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 110,
                  width: 110,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.construction_rounded,
                    size: 55,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Coming Soon!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Test questions are currently under development.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'We are working on something exciting. '
                  'Stay tuned!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                Chip(
                  avatar: const Icon(Icons.schedule_rounded, size: 18),
                  label: const Text('Under Development'),
                  backgroundColor: colorScheme.secondaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
