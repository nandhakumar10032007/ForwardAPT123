
import 'package:flutter/material.dart';

import 'Contest_Questions_Screen.dart';
import 'Contest_Solving_Screen.dart';

class ContestDashboard extends StatefulWidget {
  final String contestId;

  const ContestDashboard({
    super.key,
    required this.contestId,
  });

  @override
  State<ContestDashboard> createState() =>
      _ContestDashboardState();
}

class _ContestDashboardState extends State<ContestDashboard> {
  static const Color _primary = Color(0xFF4F46E5);
  static const Color _background = Color(0xFFF7F8FC);
  static const Color _text = Color(0xFF171923);
  static const Color _muted = Color(0xFF777A87);

  // Always open Questions when entering Contest Dashboard.
  int _selectedIndex = 0;

  // Stores the question selected from the Questions tab.
  String? _selectedQuestionId;

  final List<Map<String, dynamic>> _navigationItems = [
    {
      'title': 'Questions',
      'icon': Icons.list_alt_outlined,
      'selectedIcon': Icons.list_alt_rounded,
    },
    {
      'title': 'Doing',
      'icon': Icons.edit_note_outlined,
      'selectedIcon': Icons.edit_note_rounded,
    },
    {
      'title': 'Result',
      'icon': Icons.assessment_outlined,
      'selectedIcon': Icons.assessment_rounded,
    },
    {
      'title': 'Leaderboard',
      'icon': Icons.emoji_events_outlined,
      'selectedIcon': Icons.emoji_events_rounded,
    },
  ];

  // Bottom navigation selection.
  void _onNavigationSelected(int index) {
    if (index < 0 || index >= _navigationItems.length) {
      return;
    }

    setState(() {
      // Directly opening Doing from another tab starts at E01.
      if (index == 1 && _selectedIndex != 1) {
        _selectedQuestionId = null;
      }

      _selectedIndex = index;
    });
  }

  // Called when a student taps a question card.
  void _openSelectedQuestion(String questionId) {
    setState(() {
      _selectedQuestionId = questionId;
      _selectedIndex = 1;
    });
  }

  // Exit Contest and return to the existing Contest Home route.
  void _goToContestHome() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        bottom: false,
        child: _buildMainContent(),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  // Main tab content.
  Widget _buildMainContent() {
    return IndexedStack(
      index: _selectedIndex,
      children: [
        // TAB 1: QUESTIONS
        ContestQuestionsScreen(
          contestId: widget.contestId,
          onExit: _goToContestHome,
          onQuestionSelected: _openSelectedQuestion,
        ),

        // TAB 2: DOING
        ContestSolvingScreen(
          contestId: widget.contestId,
          initialQuestionId: _selectedQuestionId,
        ),

        // TAB 3: RESULT
        _buildComingSoonPage(
          title: 'Result',
          icon: Icons.assessment_rounded,
        ),

        // TAB 4: LEADERBOARD
        _buildComingSoonPage(
          title: 'Leaderboard',
          icon: Icons.emoji_events_rounded,
        ),
      ],
    );
  }

  // Coming Soon pages.
  Widget _buildComingSoonPage({
    required String title,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      color: _background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEBFF),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Icon(
                  icon,
                  size: 43,
                  color: _primary,
                ),
              ),

              const SizedBox(height: 24),

              Text(
                title,
                style: const TextStyle(
                  color: _text,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Coming Soon 🚀',
                style: TextStyle(
                  color: _primary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 9),

              const Text(
                'We are working on this section.\n'
                'Stay tuned for something exciting!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _muted,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),

              const SizedBox(height: 28),

              OutlinedButton.icon(
                onPressed: _goToContestHome,
                icon: const Icon(
                  Icons.home_rounded,
                  size: 19,
                ),
                label: const Text('Contest Home'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primary,
                  side: const BorderSide(color: _primary),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  // Bottom navigation bar.
  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: Color(0xFFE7E8EE),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: List.generate(
              _navigationItems.length,
              (index) {
                final item = _navigationItems[index];
                final isSelected = _selectedIndex == index;

                return Expanded(
                  child: _buildNavigationItem(
                    title: item['title'] as String,
                    icon: item['icon'] as IconData,
                    selectedIcon:
                        item['selectedIcon'] as IconData,
                    isSelected: isSelected,
                    onTap: () => _onNavigationSelected(index),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // Individual navigation item.
  Widget _buildNavigationItem({
    required String title,
    required IconData icon,
    required IconData selectedIcon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(
          vertical: 7,
          horizontal: 2,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFEDEBFF)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                isSelected ? selectedIcon : icon,
                size: 23,
                color: isSelected ? _primary : _muted,
              ),
            ),

            const SizedBox(height: 3),

            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? _primary : _muted,
                fontSize: 10,
                fontWeight: isSelected
                    ? FontWeight.w800
                    : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
