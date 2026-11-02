import 'package:flutter/material.dart';

import 'home_screen.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() =>
      _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int _currentIndex = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();

    _pages = [
      const HomeScreen(),
      const _PlaceholderPage(
        title: 'Weekly Contest',
        icon: Icons.emoji_events_rounded,
      ),
      const _PlaceholderPage(
        title: 'Custom Test',
        icon: Icons.edit_note_rounded,
      ),
      const _PlaceholderPage(
        title: 'Daily Problem',
        icon: Icons.today_rounded,
      ),
    ];
  }

  void _onNavigationItemSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF7F8FC),

      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),

      bottomNavigationBar:
          _buildBottomNavigationBar(),
    );
  }

  // ============================================================
  // BOTTOM NAVIGATION
  // ============================================================

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
        child: NavigationBar(
          height: 72,

          backgroundColor: Colors.white,

          elevation: 0,

          selectedIndex: _currentIndex,

          onDestinationSelected:
              _onNavigationItemSelected,

          indicatorColor:
              const Color(0xFFEDEBFF),

          labelBehavior:
              NavigationDestinationLabelBehavior
                  .alwaysShow,

          destinations: const [
            NavigationDestination(
              icon: Icon(
                Icons.home_outlined,
                color: Color(0xFF777A87),
              ),
              selectedIcon: Icon(
                Icons.home_rounded,
                color: Color(0xFF4F46E5),
              ),
              label: 'Home',
            ),

            NavigationDestination(
              icon: Icon(
                Icons.emoji_events_outlined,
                color: Color(0xFF777A87),
              ),
              selectedIcon: Icon(
                Icons.emoji_events_rounded,
                color: Color(0xFF4F46E5),
              ),
              label: 'Contest',
            ),

            NavigationDestination(
              icon: Icon(
                Icons.edit_note_outlined,
                color: Color(0xFF777A87),
              ),
              selectedIcon: Icon(
                Icons.edit_note_rounded,
                color: Color(0xFF4F46E5),
              ),
              label: 'Custom Test',
            ),

            NavigationDestination(
              icon: Icon(
                Icons.today_outlined,
                color: Color(0xFF777A87),
              ),
              selectedIcon: Icon(
                Icons.today_rounded,
                color: Color(0xFF4F46E5),
              ),
              label: 'Daily',
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// TEMPORARY PLACEHOLDER
// ============================================================

class _PlaceholderPage extends StatelessWidget {
  final String title;
  final IconData icon;

  const _PlaceholderPage({
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF7F8FC),

      body: Center(
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Container(
              width: 75,
              height: 75,
              decoration: BoxDecoration(
                color:
                    const Color(0xFFEDEBFF),
                borderRadius:
                    BorderRadius.circular(22),
              ),
              child: Icon(
                icon,
                size: 38,
                color:
                    const Color(0xFF4F46E5),
              ),
            ),

            const SizedBox(height: 18),

            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF171923),
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Coming soon 🚀',
              style: TextStyle(
                color: Color(0xFF777A87),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}