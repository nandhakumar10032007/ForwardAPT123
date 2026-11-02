
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'question_upload/common_question_upload_screen.dart';
import 'question_upload/contest_question_upload_screen.dart';
import 'question_upload/test_question_upload_screen.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  Future<void> logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();

      if (!context.mounted) return;

      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (route) => false,
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logout failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openQuestionManagement(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const QuestionManagementScreen(),
      ),
    );
  }

  void _showComingSoon(
    BuildContext context,
    String feature,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature will be available soon!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ForwardAPT Admin'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () => logout(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Admin Dashboard',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Manage ForwardAPT from here.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 30),

              // Question management
              _AdminCard(
                icon: Icons.quiz_outlined,
                title: 'Questions',
                subtitle: 'Upload and manage aptitude questions',
                onTap: () => _openQuestionManagement(context),
              ),

              const SizedBox(height: 16),

              // Question statistics
              _AdminCard(
                icon: Icons.bar_chart_rounded,
                title: 'Question Statistics',
                subtitle: 'View topic and difficulty counts',
                onTap: () => _showComingSoon(
                  context,
                  'Question Statistics',
                ),
              ),

              const SizedBox(height: 16),

              // User management
              _AdminCard(
                icon: Icons.people_outline_rounded,
                title: 'Users',
                subtitle: 'View ForwardAPT users',
                onTap: () => _showComingSoon(
                  context,
                  'User Management',
                ),
              ),

              const SizedBox(height: 16),

              // Settings
              _AdminCard(
                icon: Icons.settings_outlined,
                title: 'Settings',
                subtitle: 'Manage application settings',
                onTap: () => _showComingSoon(
                  context,
                  'Settings',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the three separate question-upload options.
class QuestionManagementScreen extends StatelessWidget {
  const QuestionManagementScreen({super.key});

  void _openCommonUpload(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CommonQuestionUploadScreen(),
      ),
    );
  }

  void _openContestUpload(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ContestQuestionUploadScreen(),
      ),
    );
  }

  void _openTestUpload(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const TestQuestionUploadScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Question Management'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose Question Category',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Select the category for which you want to '
                'upload questions from an Excel file.',
                style: TextStyle(fontSize: 15),
              ),

              const SizedBox(height: 26),

              // Common Questions
              _AdminCard(
                icon: Icons.menu_book_outlined,
                title: 'Common Questions',
                subtitle: 'Upload general aptitude questions',
                onTap: () => _openCommonUpload(context),
              ),

              const SizedBox(height: 16),

              // Contest Questions
              _AdminCard(
                icon: Icons.emoji_events_outlined,
                title: 'Contest Questions',
                subtitle: 'Upload questions for contests',
                onTap: () => _openContestUpload(context),
              ),

              const SizedBox(height: 16),

              // Test Questions
              _AdminCard(
                icon: Icons.assignment_outlined,
                title: 'Test Questions',
                subtitle: 'Upload questions for test sets',
                onTap: () => _openTestUpload(context),
              ),

              const SizedBox(height: 24),

              // Global question-number information
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Question numbers are assigned through '
                          'one global counter shared by Common, '
                          'Contest, and Test questions. Each new '
                          'upload continues from the last assigned '
                          'question number.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable card used throughout the admin dashboard.
class _AdminCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AdminCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(
                icon,
                size: 36,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
