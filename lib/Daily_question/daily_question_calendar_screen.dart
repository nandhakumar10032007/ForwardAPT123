
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DailyQuestionCalendarScreen extends StatefulWidget {
  final DateTime? initialDate;

  const DailyQuestionCalendarScreen({
    super.key,
    this.initialDate,
  });

  @override
  State<DailyQuestionCalendarScreen> createState() =>
      _DailyQuestionCalendarScreenState();
}

class _DailyQuestionCalendarScreenState
    extends State<DailyQuestionCalendarScreen> {
  // ============================================================
  // COLORS
  // ============================================================

  static const Color primary = Color(0xFF4F46E5);
  static const Color background = Color(0xFFF7F8FC);
  static const Color darkText = Color(0xFF171923);
  static const Color muted = Color(0xFF777A87);

  // Active streak - GOLDEN
  static const Color goldenBackground = Color(0xFFFEF3C7);
  static const Color goldenText = Color(0xFFB45309);

  // Previous broken streak - GREEN
  static const Color greenBackground = Color(0xFFDCFCE7);
  static const Color greenText = Color(0xFF15803D);

  // Retrospectively solved - LIGHT BLUE
  static const Color blueBackground = Color(0xFFBAE6FD);
  static const Color blueText = Color(0xFF0369A1);

  // Available but unsolved
  static const Color availableBackground = Color(0xFFEDEBFF);

  // Unavailable
  static const Color unavailableBackground = Color(0xFFF0F1F5);

  // ============================================================
  // MONTH SETTINGS
  // ============================================================

  static final DateTime minimumMonth = DateTime(2026, 11);

  late DateTime currentMonth;

  static const List<String> months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  User? get currentUser => FirebaseAuth.instance.currentUser;

  DateTime get today {
    return DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
  }

  // ============================================================
  // DATE HELPERS
  // ============================================================

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _dateId(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  DateTime? _parseDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return null;
    return _dateOnly(date);
  }

  bool _isSameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  bool _isAfter(DateTime first, DateTime second) {
    return _dateOnly(first).isAfter(_dateOnly(second));
  }

  bool _isAtOrAfterMinimum(DateTime date) {
    return !DateTime(date.year, date.month)
        .isBefore(minimumMonth);
  }

  DateTime _clampMonth(DateTime date) {
    final month = DateTime(date.year, date.month);

    final current = DateTime(today.year, today.month);

    if (month.isBefore(minimumMonth)) {
      return minimumMonth;
    }

    if (month.isAfter(current)) {
      return current;
    }

    return month;
  }

  // ============================================================
  // FIREBASE REFERENCES
  // ============================================================

  CollectionReference<Map<String, dynamic>> get _questionsRef {
    final year = currentMonth.year.toString();

    final month =
        currentMonth.month.toString().padLeft(2, '0');

    return FirebaseFirestore.instance
        .collection('dailyQuestions')
        .doc(year)
        .collection('months')
        .doc(month)
        .collection('questions');
  }

  CollectionReference<Map<String, dynamic>>? get _solvedRef {
    final user = currentUser;

    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('DailyQuestionSolved');
  }

  DocumentReference<Map<String, dynamic>>? get _userRef {
    final user = currentUser;

    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
  }

  // ============================================================
  // INITIALIZATION
  // ============================================================

  @override
  void initState() {
    super.initState();

    final initial = widget.initialDate ?? today;

    currentMonth = _clampMonth(initial);
  }

  // ============================================================
  // MONTH NAVIGATION
  // ============================================================

  bool get canGoPrevious {
    final previous = DateTime(
      currentMonth.year,
      currentMonth.month - 1,
    );

    return !previous.isBefore(minimumMonth);
  }

  bool get canGoNext {
    final next = DateTime(
      currentMonth.year,
      currentMonth.month + 1,
    );

    final maximum = DateTime(today.year, today.month);

    return !next.isAfter(maximum);
  }

  void _changeMonth(int amount) {
    final next = DateTime(
      currentMonth.year,
      currentMonth.month + amount,
    );

    if (next.isBefore(minimumMonth)) return;

    final maximum = DateTime(today.year, today.month);

    if (next.isAfter(maximum)) return;

    setState(() {
      currentMonth = next;
    });
  }

  // ============================================================
  // OPEN QUESTION
  // ============================================================

  void _selectDate(DateTime date, Set<String> availableDates) {
    final selected = _dateOnly(date);

    // No questions for this date.
    if (!availableDates.contains(_dateId(selected))) return;

    // Never open a future question.
    if (_isAfter(selected, today)) return;

    // Never go before November 2026.
    if (!_isAtOrAfterMinimum(selected)) return;

    Navigator.pop(context, selected);
  }

  // ============================================================
  // SOLVED QUESTION STATUS
  // ============================================================

  /// Uses the status saved on each DailyQuestionSolved document.
  /// current_streak = gold, broken_streak = green,
  /// previous_question_solved = light blue.
  Map<String, String> _getSolvedStatuses(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) {
    final result = <String, String>{};

    for (final document in documents) {
      final data = document.data();
      final date = _parseDate((data['date'] ?? document.id).toString());
      if (date == null) continue;

      final status = (data['status'] ?? '').toString().trim();
      if (status.isEmpty) continue;

      result[_dateId(date)] = status;
    }

    return result;
  }

  void _showColorLegend() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.palette_outlined, color: primary),
              SizedBox(width: 10),
              Text(
                'Calendar Colors',
                style: TextStyle(
                  color: darkText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          content: Wrap(
            spacing: 18,
            runSpacing: 16,
            children: [
              _legendItem(goldenBackground, goldenText, 'Active streak'),
              _legendItem(greenBackground, greenText, 'Broken streak'),
              _legendItem(blueBackground, blueText, 'Past solved'),
              _legendItem(availableBackground, primary, 'Available'),
              _legendItem(
                unavailableBackground,
                muted,
                'Unavailable',
                icon: Icons.lock_rounded,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        automaticallyImplyLeading: false,
        toolbarHeight: 68,
        titleSpacing: 16,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                'assets/app_icon.png',
                width: 42,
                height: 42,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Text(
                'ForwardAPT Daily Questions',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: darkText,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filledTonal(
              tooltip: "Today's question",
              onPressed: () => Navigator.pop(context, _dateOnly(today)),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFEDEBFF),
                foregroundColor: primary,
              ),
              icon: const Icon(Icons.exit_to_app_rounded),
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFE7E8EE)),
        ),
      ),

      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Color(0xFFE7E8EE), width: 1),
            ),
          ),
          child: NavigationBar(
            height: 68,
            backgroundColor: Colors.white,
            elevation: 0,
            selectedIndex: 3,
            indicatorColor: const Color(0xFFEDEBFF),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (index) {
              // The calendar is opened from the Daily tab. Keep Daily here;
              // other destinations return to the existing Dashboard route.
              if (index != 3) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined, color: muted),
                selectedIcon: Icon(Icons.home_rounded, color: primary),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.emoji_events_outlined, color: muted),
                selectedIcon: Icon(Icons.emoji_events_rounded, color: primary),
                label: 'Contest',
              ),
              NavigationDestination(
                icon: Icon(Icons.edit_note_outlined, color: muted),
                selectedIcon: Icon(Icons.edit_note_rounded, color: primary),
                label: 'Custom Test',
              ),
              NavigationDestination(
                icon: Icon(Icons.today_outlined, color: muted),
                selectedIcon: Icon(Icons.today_rounded, color: primary),
                label: 'Daily',
              ),
            ],
          ),
        ),
      ),

      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _questionsRef.snapshots(),

        builder: (context, questionSnapshot) {
          if (questionSnapshot.hasError) {
            return _errorMessage(
              'Unable to load questions.',
            );
          }

          if (questionSnapshot.connectionState ==
                  ConnectionState.waiting &&
              !questionSnapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(
                color: primary,
              ),
            );
          }

          // Collect dates having uploaded questions.
          final availableDates = <String>{};

          for (final document
              in questionSnapshot.data?.docs ?? []) {
            final date = _parseDate(document.id);

            if (date == null) continue;

            if (_isAtOrAfterMinimum(date) &&
                !_isAfter(date, today)) {
              availableDates.add(_dateId(date));
            }
          }

          final user = currentUser;

          // If user is not logged in, still show the calendar.
          if (user == null) {
            return _buildCalendar(
              availableDates: availableDates,
              solvedStatuses: {},
            );
          }

          return StreamBuilder<
              QuerySnapshot<Map<String, dynamic>>>(
            stream: _solvedRef!.snapshots(),

            builder: (context, solvedSnapshot) {
              if (solvedSnapshot.hasError) {
                return _errorMessage(
                  'Unable to load solved questions.\n${solvedSnapshot.error}',
                );
              }

              final solvedDocuments =
                  solvedSnapshot.data?.docs ?? [];

              final solvedStatuses =
                  _getSolvedStatuses(solvedDocuments);

              return StreamBuilder<
                  DocumentSnapshot<Map<String, dynamic>>>(
                stream: _userRef!.snapshots(),

                builder: (context, userSnapshot) {
                  if (userSnapshot.hasError) {
                    return _errorMessage(
                      'Unable to load streak information.',
                    );
                  }

                  final userData =
                      userSnapshot.data?.data() ?? {};

                  final currentStreak =
                      (userData['currentStreak'] as num?)
                              ?.toInt() ??
                          0;

                  return _buildCalendar(
                    availableDates: availableDates,
                    solvedStatuses: solvedStatuses,
                    currentStreak: currentStreak,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // ============================================================
  // CALENDAR CONTENT
  // ============================================================

  Widget _buildCalendar({
    required Set<String> availableDates,
    required Map<String, String> solvedStatuses,
    int currentStreak = 0,
  }) {
    final firstDay = DateTime(currentMonth.year, currentMonth.month, 1);
    final totalDays = DateTime(currentMonth.year, currentMonth.month + 1, 0).day;
    final startingOffset = firstDay.weekday - 1;
    final totalCells = ((startingOffset + totalDays + 6) ~/ 7) * 7;

    final monthPrefix =
        '${currentMonth.year.toString().padLeft(4, '0')}-'
        '${currentMonth.month.toString().padLeft(2, '0')}-';
    final monthStatuses = Map<String, String>.fromEntries(
      solvedStatuses.entries.where((entry) => entry.key.startsWith(monthPrefix)),
    );
    final solvedCount = monthStatuses.length;
    final activeCount = monthStatuses.values
        .where((status) => status == 'current_streak')
        .length;
    final retrospectiveCount = monthStatuses.values
        .where((status) => status == 'previous_question_solved')
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 34),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Month and year on one row, with the color-help icon.
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE5E6EB)),
                  ),
                  child: Row(
                    children: [
                      const Spacer(),
                      Text(
                        '${months[currentMonth.month - 1]} ${currentMonth.year}',
                        style: const TextStyle(
                          color: darkText,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Explain calendar colors',
                        onPressed: _showColorLegend,
                        icon: const Icon(
                          Icons.info_outline_rounded,
                          color: primary,
                          size: 25,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 15),

                // Solved progress.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF15803D), size: 18),
                    const SizedBox(width: 7),
                    Text(
                      'Solved ($solvedCount/${availableDates.length})',
                      style: const TextStyle(
                        color: darkText,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Calendar grid.
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE5E6EB)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.025),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          for (final day in const [
                            'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'
                          ])
                            Expanded(
                              child: Center(
                                child: Text(
                                  day,
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 13),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: totalCells,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 5,
                          childAspectRatio: 0.85,
                        ),
                        itemBuilder: (context, index) {
                          final day = index - startingOffset + 1;
                          if (day < 1 || day > totalDays) {
                            return const SizedBox.shrink();
                          }

                          final date = DateTime(
                            currentMonth.year, currentMonth.month, day);
                          final id = _dateId(date);
                          final isAvailable = availableDates.contains(id);
                          final isFuture = _isAfter(date, today);
                          final isBeforeStart = !_isAtOrAfterMinimum(date);
                          final solvedStatus = solvedStatuses[id];
                          final isSolved = solvedStatus != null;
                          final isActiveStreak =
                              solvedStatus == 'current_streak';
                          final isBrokenStreak =
                              solvedStatus == 'broken_streak';
                          final isRetrospective =
                              solvedStatus == 'previous_question_solved';
                          final isToday = _isSameDate(date, today);
                          final isLocked =
                              !isAvailable || isFuture || isBeforeStart;

                          return _dayCell(
                            day: day,
                            isAvailable: isAvailable,
                            isLocked: isLocked,
                            isSolved: isSolved,
                            isActiveStreak: isActiveStreak,
                            isBrokenStreak: isBrokenStreak,
                            isRetrospective: isRetrospective,
                            isToday: isToday,
                            onTap: isLocked
                                ? null
                                : () => _selectDate(date, availableDates),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 15),

                // Previous and Next month controls below the calendar.
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            canGoPrevious ? () => _changeMonth(-1) : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                        label: const Text('Previous'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primary,
                          disabledForegroundColor: Colors.grey.shade400,
                          side: const BorderSide(color: Color(0xFFDCDDF0)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: canGoNext ? () => _changeMonth(1) : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                        label: const Text('Next'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primary,
                          disabledForegroundColor: Colors.grey.shade400,
                          side: const BorderSide(color: Color(0xFFDCDDF0)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),


              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // MONTH HEADER
  // ============================================================

  // ============================================================
  // STREAK SUMMARY
  // ============================================================

  Widget _streakSummary(
    int streak,
    int activeCount,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE5E6EB),
        ),
      ),

      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,

            decoration: BoxDecoration(
              color: goldenBackground,
              borderRadius: BorderRadius.circular(14),
            ),

            child: const Icon(
              Icons.local_fire_department_rounded,
              color: goldenText,
              size: 29,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current Streak',
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  '$streak ${streak == 1 ? 'Day' : 'Days'}',
                  style: const TextStyle(
                    color: darkText,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          const Icon(
            Icons.local_fire_department_rounded,
            color: goldenText,
            size: 22,
          ),

          const SizedBox(width: 4),

          Text(
            '$activeCount',
            style: const TextStyle(
              color: goldenText,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LEGEND
  // ============================================================

  Widget _legend() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 12,

      children: [
        _legendItem(
          goldenBackground,
          goldenText,
          'Active streak',
        ),

        _legendItem(
          greenBackground,
          greenText,
          'Broken streak',
        ),

        _legendItem(
          blueBackground,
          blueText,
          'Past solved',
        ),

        _legendItem(
          availableBackground,
          primary,
          'Available',
        ),

        _legendItem(
          unavailableBackground,
          muted,
          'Unavailable',
          icon: Icons.lock_rounded,
        ),
      ],
    );
  }

  Widget _legendItem(
    Color bg,
    Color fg,
    String label, {
    IconData? icon,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 13,
          height: 13,

          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: fg.withOpacity(0.5),
            ),
          ),

          child: icon == null
              ? null
              : Icon(
                  icon,
                  size: 9,
                  color: fg,
                ),
        ),

        const SizedBox(width: 5),

        Text(
          label,
          style: const TextStyle(
            color: muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // DATE CELL
  // ============================================================

  Widget _dayCell({
    required int day,
    required bool isAvailable,
    required bool isLocked,
    required bool isSolved,
    required bool isActiveStreak,
    required bool isBrokenStreak,
    required bool isRetrospective,
    required bool isToday,
    required VoidCallback? onTap,
  }) {
    Color cellColor;
    Color textColor;

    if (isLocked) {
      cellColor = unavailableBackground;
      textColor = muted;
    } else if (isActiveStreak) {
      cellColor = goldenBackground;
      textColor = goldenText;
    } else if (isBrokenStreak) {
      cellColor = greenBackground;
      textColor = greenText;
    } else if (isRetrospective) {
      cellColor = blueBackground;
      textColor = blueText;
    } else {
      cellColor = availableBackground;
      textColor = primary;
    }

    return Material(
      color: cellColor,
      borderRadius: BorderRadius.circular(11),

      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),

        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),

            border: isToday && !isLocked
                ? Border.all(
                    color: const Color(0xFFF97316),
                    width: 2,
                  )
                : null,
          ),

          child: Stack(
            alignment: Alignment.center,
            children: [
              // UNAVAILABLE = LOCK
              if (isLocked)
                Icon(
                  Icons.lock_rounded,
                  color: Colors.grey.shade400,
                  size: 17,
                )
              else
                Text(
                  '$day',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),

              // SOLVED CHECKMARK
              if (isSolved && !isLocked)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: textColor,
                    size: 10,
                  ),
                ),

              // TODAY LABEL
              if (isToday && !isLocked)
                const Positioned(
                  bottom: 3,
                  child: Text(
                    'TODAY',
                    style: TextStyle(
                      color: Color(0xFFF97316),
                      fontSize: 6,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ERROR MESSAGE
  // ============================================================

  Widget _errorMessage(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 45,
              color: muted,
            ),

            const SizedBox(height: 14),

            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: darkText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),

            const SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
