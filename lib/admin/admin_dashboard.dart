
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'question_upload/common_question_upload_screen.dart';
import 'question_upload/contest_question_upload_screen.dart';
import 'question_upload/test_question_upload_screen.dart';
import 'question_upload/daily_question_upload_screen.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  // LOGOUT
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

  // NAVIGATION
  void _openScreen(
    BuildContext context,
    Widget screen,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => screen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,

      // APP BAR
      appBar: AppBar(
        title: const Text(
          'ForwardAPT Admin',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () => logout(context),
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),

      // DASHBOARD BODY
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 600;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // HEADING
                  const Text(
                    'Admin Dashboard',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Manage ForwardAPT questions from here.',
                    style: TextStyle(
                      fontSize: 15,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.65),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // FOUR QUESTION OPTIONS
                  GridView.count(
                    crossAxisCount: isWide ? 2 : 2,
                    shrinkWrap: true,
                    physics:
                        const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 20,
                    childAspectRatio: isWide ? 2.0 : 1.25,

                    children: [

                      // COMMON QUESTIONS
                      _AdminCard(
                        icon: Icons.menu_book_rounded,
                        title: 'Common Question',
                        color: Colors.blue,
                        onTap: () {
                          _openScreen(
                            context,
                            const CommonQuestionUploadScreen(),
                          );
                        },
                      ),

                      // CONTEST QUESTIONS
                      _AdminCard(
                        icon: Icons.emoji_events_rounded,
                        title: 'Contest Question',
                        color: Colors.deepPurple,
                        onTap: () {
                          _openScreen(
                            context,
                            const ContestQuestionUploadScreen(),
                          );
                        },
                      ),

                      // TEST QUESTIONS
                      _AdminCard(
                        icon: Icons.assignment_rounded,
                        title: 'Test Question',
                        color: Colors.green,
                        onTap: () {
                          _openScreen(
                            context,
                            const TestQuestionUploadScreen(),
                          );
                        },
                      ),

                      // DAILY QUESTIONS
                      _AdminCard(
                        icon: Icons.calendar_month_rounded,
                        title: 'Daily Question',
                        color: Colors.orange,
                        onTap: () {
                          _openScreen(
                            context,
                            const DailyQuestionUploadScreen(),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// REUSABLE ADMIN CARD
class _AdminCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _AdminCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shadowColor: color.withValues(alpha: 0.20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: color.withValues(alpha: 0.25),
          width: 1,
        ),
      ),

      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),

          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              // ICON
              Icon(
                icon,
                size: 42,
                color: color,
              ),

              const SizedBox(height: 14),

              // TITLE
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              // ARROW
              Icon(
                Icons.arrow_forward_rounded,
                color: color,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
