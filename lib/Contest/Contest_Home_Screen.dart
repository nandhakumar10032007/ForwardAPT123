import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'Contest_Dashboard.dart';

class ContestHomeScreen extends StatefulWidget {
  const ContestHomeScreen({super.key});

  @override
  State<ContestHomeScreen> createState() => _ContestHomeScreenState();
}

class _ContestHomeScreenState extends State<ContestHomeScreen> {
  static const Color _primary = Color(0xFF4F46E5);
  static const Color _background = Color(0xFFF7F8FC);
  static const Color _text = Color(0xFF171923);
  static const Color _muted = Color(0xFF777A87);
  static const Color _border = Color(0xFFE7E8EE);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Timer? _timer;
  DateTime _now = DateTime.now();
  bool _isRegistering = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  DateTime? _dateValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _stringValue(dynamic value, {String fallback = ''}) =>
      value == null ? fallback : value.toString();

  int _intValue(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _formatDate(DateTime date) {
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${weekdays[date.weekday - 1]}, ${date.day} '
        '${months[date.month - 1]} ${date.year}';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${date.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _formatDuration(Duration duration) {
    if (duration.isNegative) duration = Duration.zero;
    return '${duration.inHours.toString().padLeft(2, '0')} : '
        '${duration.inMinutes.remainder(60).toString().padLeft(2, '0')} : '
        '${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  List<String> _topics(dynamic value) {
    if (value is Iterable) {
      return value.map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty).toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value.split(',').map((e) => e.trim())
          .where((e) => e.isNotEmpty).toList();
    }
    return [];
  }

  String _topicText(Map<String, dynamic> data) {
    final topics = _topics(data['Topics']);
    return topics.isEmpty ? 'Topics will be announced' : topics.join(', ');
  }

  bool _isCompleted(Map<String, dynamic> data) {
    final end = _dateValue(data['End_Time']);
    if (end != null) return !_now.isBefore(end);
    return _stringValue(data['Status']).toLowerCase() == 'completed';
  }

  bool _isLive(Map<String, dynamic> data) {
    final start = _dateValue(data['Start_Time']);
    final end = _dateValue(data['End_Time']);
    return start != null && end != null &&
        !_now.isBefore(start) && _now.isBefore(end);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortContests(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final docs = snapshot.docs.toList();
    docs.sort((a, b) {
      final aDate = _dateValue(a.data()['Start_Time']) ??
          _dateValue(a.data()['Contest_Date']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = _dateValue(b.data()['Start_Time']) ??
          _dateValue(b.data()['Contest_Date']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final compare = aDate.compareTo(bDate);
      return compare != 0 ? compare : a.id.compareTo(b.id);
    });
    return docs;
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _nextContest(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> contests,
  ) {
    final candidates = contests.where((doc) {
      final end = _dateValue(doc.data()['End_Time']);
      return end != null && _now.isBefore(end);
    }).toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final aStart = _dateValue(a.data()['Start_Time']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bStart = _dateValue(b.data()['Start_Time']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return aStart.compareTo(bStart);
    });
    return candidates.first;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _previousContests(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> contests,
  ) {
    final previous = contests.where((doc) => _isCompleted(doc.data())).toList();
    previous.sort((a, b) {
      final aDate = _dateValue(a.data()['End_Time']) ??
          _dateValue(a.data()['Contest_Date']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = _dateValue(b.data()['End_Time']) ??
          _dateValue(b.data()['Contest_Date']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return previous;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _registrationStream(
    String contestId,
  ) {
    final user = _user;
    if (user == null) return null;
    return _firestore.collection('Contest_Questions').doc(contestId)
        .collection('Registered').doc(user.uid).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? _resultsStream() {
    final user = _user;
    if (user == null) return null;

    // Contest summaries are stored separately from ordinary question results.
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('Contest_Result')
        .snapshots();
  }

  String _scoreFor(String contestId, Map<String, dynamic>? result) {
    if (result == null) return '—';
    final raw = result['Score'] ?? result['score'] ??
        result['Final_Score'] ?? result['finalScore'] ??
        result['Total_Score'] ?? result['totalScore'];
    if (raw == null) return '—';
    final score = raw is num ? raw.toDouble() : double.tryParse('$raw');
    if (score == null) return '—';
    return score == score.roundToDouble()
        ? score.toStringAsFixed(0)
        : score.toStringAsFixed(1);
  }


Future<void> _register(String contestId) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _message('Please sign in to register.', error: true);
      return;
    }

    if (_isRegistering) return;
    setState(() => _isRegistering = true);

    try {
      final contestRef =
          _firestore.collection('Contest_Questions').doc(contestId);
      final registrationRef =
          contestRef.collection('Registered').doc(user.uid);
      final profileRef = _firestore.collection('users').doc(user.uid);
      final resultCollection = registrationRef.collection('Result');

      const questionIds = <String>[
        'E01', 'E02', 'E03', 'E04', 'E05',
        'M01', 'M02', 'M03', 'M04', 'M05',
        'H01', 'H02', 'H03',
      ];

      final questionRefs = <String, DocumentReference<Map<String, dynamic>>>{
        for (final questionId in questionIds)
          questionId: resultCollection.doc(questionId),
      };
      final summaryRef = resultCollection.doc('Summary');
      final studentSummaryRef =
          profileRef.collection('Contest_Result').doc(contestId);

      await _firestore.runTransaction((transaction) async {
        // Firestore transactions require all reads before any writes.
        final contestSnapshot = await transaction.get(contestRef);
        final registrationSnapshot = await transaction.get(registrationRef);
        final profileSnapshot = await transaction.get(profileRef);
        final summarySnapshot = await transaction.get(summaryRef);
        final studentSummarySnapshot =
            await transaction.get(studentSummaryRef);

        final progressSnapshots =
            <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final entry in questionRefs.entries) {
          progressSnapshots[entry.key] = await transaction.get(entry.value);
        }

        if (!contestSnapshot.exists) {
          throw StateError('This contest is no longer available.');
        }

        final contestData = contestSnapshot.data()!;
        final end = _dateValue(contestData['End_Time']);
        if (end == null || !DateTime.now().isBefore(end)) {
          throw StateError('Registration for this contest has closed.');
        }

        final profileData = profileSnapshot.data() ?? {};
        final userName =
            profileData['username'] ??
            profileData['Username'] ??
            profileData['name'] ??
            profileData['Name'] ??
            profileData['fullName'] ??
            profileData['Full_Name'] ??
            user.displayName ??
            user.email?.split('@').first ??
            'Student';

        // Keep an existing registration and its original registration time.
        if (!registrationSnapshot.exists) {
          transaction.set(registrationRef, {
            'User_ID': user.uid,
            'User_Name': userName.toString(),
            'Registered_At': FieldValue.serverTimestamp(),
          });
        } else {
          final existingData = registrationSnapshot.data() ?? {};
          final existingName =
              existingData['User_Name']?.toString().trim() ?? '';
          if (existingName.isEmpty) {
            transaction.update(registrationRef, {
              'User_Name': userName.toString(),
            });
          }
        }

        // Create only missing progress documents; never reset existing progress.
        for (final questionId in questionIds) {
          if (!(progressSnapshots[questionId]?.exists ?? false)) {
            final difficulty = questionId.startsWith('E')
                ? 'Easy'
                : questionId.startsWith('M')
                    ? 'Medium'
                    : 'Hard';
            transaction.set(questionRefs[questionId]!, {
              'Question_ID': questionId,
              'Difficulty': difficulty,
              'Penalty_Count': 0,
              'Status': 'Unsolved',
            });
          }
        }

        // Aggregate contest score. Created once, so repeat registration
        // cannot reset marks or penalties.
        if (!summarySnapshot.exists) {
          transaction.set(summaryRef, {
            'Bonus_Point': 0,
            'Easy_Total_Mark': 0.0,
            'Medium_Total_Mark': 0.0,
            'Hard_Total_Mark': 0.0,
            'Easy_Total_Penalty_Mark': 0.0,
            'Medium_Total_Penalty_Mark': 0.0,
            'Hard_Total_Penalty_Mark': 0.0,
            'Final_Score': 0.0,
            'Last_Submission_Time': null,
            'Solved_Questions': <String>[],
          });
        }

        // Lightweight profile-level summary used by Previous Contests.
        if (!studentSummarySnapshot.exists) {
          transaction.set(studentSummaryRef, {
            'Contest_ID': contestId,
            'Solved_Questions': <String>[],
            'Final_Score': 0.0,
          });
        }
      });

      if (mounted) {
        _message('Registration successful for Contest $contestId.');
      }
    } catch (e) {
      if (mounted) {
        _message('Registration failed: ${e.toString()}', error: true);
      }
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  void _enterContest(String contestId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ContestDashboard(contestId: contestId)),
    );
  }

  void _message(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : const Color(0xFF15803D),
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Contest', style: TextStyle(
          color: _text, fontSize: 21, fontWeight: FontWeight.w800,
        )),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none_rounded, color: _text),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: _border),
        ),
      ),
      body: SafeArea(
        top: false,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _firestore.collection('Contest_Questions').snapshots(),
          builder: (context, contestSnapshot) {
            if (contestSnapshot.hasError) {
              return _messageState('Unable to load contests. '
                  '${contestSnapshot.error}', Icons.cloud_off_outlined);
            }
            if (!contestSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final contests = _sortContests(contestSnapshot.data!);
            final next = _nextContest(contests);
            final previous = _previousContests(contests);

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _resultsStream(),
              builder: (context, resultSnapshot) {
                final results = <String, Map<String, dynamic>>{};
                for (final doc in resultSnapshot.data?.docs ?? []) {
                  results[doc.id] = doc.data();
                }
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _upcomingSection(next),
                      const SizedBox(height: 28),
                      _previousSection(previous, results),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _upcomingSection(
    QueryDocumentSnapshot<Map<String, dynamic>>? contest,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Upcoming Contest', style: TextStyle(
          color: _text, fontSize: 19, fontWeight: FontWeight.w800,
        )),
        const SizedBox(height: 14),
        contest == null ? _emptyUpcoming() : _contestCard(contest),
      ],
    );
  }

  Widget _emptyUpcoming() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: _border),
      ),
      child: const Column(
        children: [
          Icon(Icons.event_available_outlined, size: 42, color: _primary),
          SizedBox(height: 12),
          Text('No upcoming contest', style: TextStyle(
            color: _text, fontSize: 17, fontWeight: FontWeight.w800,
          )),
          SizedBox(height: 6),
          Text(
            'The next weekly contest will appear here once it is uploaded.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _contestCard(QueryDocumentSnapshot<Map<String, dynamic>> contest) {
    final data = contest.data();
    final id = _stringValue(data['Contest_ID'], fallback: contest.id);
    final start = _dateValue(data['Start_Time']);
    final end = _dateValue(data['End_Time']);
    final completed = end != null && !_now.isBefore(end);
    final live = start != null && end != null &&
        !_now.isBefore(start) && _now.isBefore(end);
    final target = live ? end : start;
    final remaining = completed || target == null
        ? Duration.zero : target.difference(_now);
    final duration = _intValue(data['Duration_Minutes'], fallback: 30);
    final questionCount = _intValue(data['Question_Count'], fallback: 13);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.025),
          blurRadius: 14,
          offset: const Offset(0, 4),
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEBFF),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text('CONTEST #$id', style: const TextStyle(
                  color: _primary, fontSize: 12, fontWeight: FontWeight.w800,
                )),
              ),
              _statusBadge(completed: completed, live: live),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Weekly Coding Challenge', style: TextStyle(
            color: _text, fontSize: 19, fontWeight: FontWeight.w800,
          )),
          const SizedBox(height: 13),
          _informationRow(
            icon: Icons.category_outlined,
            title: 'Topics',
            value: _topics(data['Topics']).join(', ').isEmpty
                ? 'Topics will be announced'
                : _topics(data['Topics']).join(', '),
          ),
          const SizedBox(height: 13),
          _informationRow(
            icon: Icons.calendar_month_outlined,
            title: 'Date',
            value: start == null ? 'Date not available' : _formatDate(start),
          ),
          const SizedBox(height: 13),
          _informationRow(
            icon: Icons.access_time_rounded,
            title: 'Time',
            value: start == null || end == null
                ? 'Time not available'
                : '${_formatTime(start)} - ${_formatTime(end)} IST',
          ),
          const SizedBox(height: 13),
          Row(children: [
            _detailChip(Icons.timer_outlined, '$duration Minutes'),
            const SizedBox(width: 8),
            _detailChip(Icons.quiz_outlined, '$questionCount Questions'),
            const SizedBox(width: 8),
            _detailChip(Icons.stars_rounded, '30 Marks'),
          ]),
          const SizedBox(height: 20),
          _countdownCard(
            title: completed ? 'Contest has ended'
                : live ? 'Contest ends in' : 'Contest starts in',
            remaining: remaining,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: _contestActionButton(id, data, completed, live),
          ),
        ],
      ),
    );
  }

  Widget _contestActionButton(
    String contestId,
    Map<String, dynamic> data,
    bool completed,
    bool live,
  ) {
    if (completed) {
      return _actionButton(
        title: 'Contest Completed',
        icon: Icons.check_circle_outline_rounded,
        enabled: false,
        onTap: () {},
      );
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _actionButton(
        title: 'Sign in to Register',
        icon: Icons.login_rounded,
        enabled: false,
        onTap: () {},
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('Contest_Questions').doc(contestId)
          .collection('Registered').doc(user.uid).snapshots(),
      builder: (context, registrationSnapshot) {
        final registered = registrationSnapshot.data?.exists ?? false;
        if (registrationSnapshot.hasError) {
          return _actionButton(
            title: 'Registration unavailable',
            icon: Icons.error_outline,
            enabled: false,
            onTap: () {},
          );
        }
        if (_isRegistering) {
          return _actionButton(
            title: 'Registering...',
            icon: Icons.hourglass_top_rounded,
            enabled: false,
            onTap: () {},
          );
        }
        if (live && registered) {
          return _actionButton(
            title: 'Enter Contest',
            icon: Icons.play_arrow_rounded,
            enabled: true,
            onTap: () => _enterContest(contestId),
          );
        }
        if (registered) {
          return _actionButton(
            title: 'Registered Successfully',
            icon: Icons.check_circle_rounded,
            enabled: false,
            onTap: () {},
          );
        }
        return _actionButton(
          title: live ? 'Register to Enter' : 'Register for Contest',
          icon: Icons.how_to_reg_rounded,
          enabled: true,
          onTap: () => _register(contestId),
        );
      },
    );
  }

  Widget _statusBadge({required bool completed, required bool live}) {
    final label = completed ? 'Completed' : live ? 'LIVE' : 'Upcoming';
    final color = completed ? _muted
        : live ? const Color(0xFF15803D) : const Color(0xFFB45309);
    final background = completed ? const Color(0xFFF0F1F5)
        : live ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(
        color: color, fontSize: 11, fontWeight: FontWeight.w800,
      )),
    );
  }

  Widget _countdownCard({
    required String title,
    required Duration remaining,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE4E0FF)),
      ),
      child: Column(children: [
        Text(title, style: const TextStyle(
          color: _muted, fontSize: 12, fontWeight: FontWeight.w600,
        )),
        const SizedBox(height: 9),
        Text(_formatDuration(remaining), style: const TextStyle(
          color: _primary, fontSize: 27, fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        )),
        const SizedBox(height: 4),
        const Text('Hours : Minutes : Seconds',
            style: TextStyle(color: _muted, fontSize: 10)),
      ]),
    );
  }

  Widget _previousSection(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> previous,
    Map<String, Map<String, dynamic>> results,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Previous Contests', style: TextStyle(
              color: _text, fontSize: 19, fontWeight: FontWeight.w800,
            )),
            if (previous.length > 3)
              TextButton(
                onPressed: () => _showAllPrevious(previous, results),
                child: const Text('View All', style: TextStyle(
                  color: _primary, fontWeight: FontWeight.w700,
                )),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (previous.isEmpty)
          _emptyPrevious()
        else
          ...previous.take(3).map((doc) =>
              _previousCard(doc, results[doc.id])),
      ],
    );
  }

  Widget _emptyPrevious() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: const Text(
        'No previous contests yet. Completed contests will appear here.',
        style: TextStyle(color: _muted, fontSize: 13),
      ),
    );
  }

  void _showAllPrevious(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> previous,
    Map<String, Map<String, dynamic>> results,
  ) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _AllPreviousContestsScreen(
        contests: previous,
        resultByContest: results,
        formatDate: _formatDate,
        scoreForContest: _scoreFor,
      ),
    ));
  }

  Widget _previousCard(
    QueryDocumentSnapshot<Map<String, dynamic>> contest,
    Map<String, dynamic>? result,
  ) {
    final data = contest.data();
    final id = _stringValue(data['Contest_ID'], fallback: contest.id);
    final date = _dateValue(data['Contest_Date']) ?? _dateValue(data['Start_Time']);
    final topics = _topics(data['Topics']);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Contest #$id', style: const TextStyle(
                color: _text, fontSize: 15, fontWeight: FontWeight.w800,
              )),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Completed', style: TextStyle(
                  color: Color(0xFF15803D), fontSize: 10,
                  fontWeight: FontWeight.w700,
                )),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(topics.isEmpty ? 'Topics not available' : topics.join(', '),
              style: const TextStyle(color: _muted, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(
                date == null ? 'Date unavailable' : _formatDate(date),
                style: const TextStyle(color: _muted, fontSize: 11),
              )),
              Text('Your score: ${_scoreFor(contest.id, result)}',
                  style: const TextStyle(
                    color: _primary, fontSize: 12, fontWeight: FontWeight.w800,
                  )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _informationRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: _primary),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(
              color: _muted, fontSize: 11, fontWeight: FontWeight.w600,
            )),
            const SizedBox(height: 3),
            Text(value, style: const TextStyle(
              color: _text, fontSize: 13, fontWeight: FontWeight.w700,
            )),
          ],
        )),
      ],
    );
  }

  Widget _detailChip(IconData icon, String label) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(children: [
        Icon(icon, color: _primary, size: 17),
        const SizedBox(height: 5),
        Text(label, textAlign: TextAlign.center, style: const TextStyle(
          color: _text, fontSize: 9, fontWeight: FontWeight.w700,
        )),
      ]),
    ));
  }

  Widget _actionButton({
    required String title,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 49,
      child: ElevatedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 19),
        label: Text(title, style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w800,
        )),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE5E7EB),
          disabledForegroundColor: _muted,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
    );
  }

  Widget _messageState(String message, IconData icon) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 42, color: _muted),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center,
            style: const TextStyle(color: _muted)),
      ]),
    ));
  }
}

class _AllPreviousContestsScreen extends StatelessWidget {
  const _AllPreviousContestsScreen({
    required this.contests,
    required this.resultByContest,
    required this.formatDate,
    required this.scoreForContest,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> contests;
  final Map<String, Map<String, dynamic>> resultByContest;
  final String Function(DateTime) formatDate;
  final String Function(String, Map<String, dynamic>?) scoreForContest;

  DateTime? _date(Map<String, dynamic> data) {
    final value = data['Contest_Date'] ?? data['Start_Time'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: const Text('Previous Contests'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: contests.map((contest) {
          final data = contest.data();
          final id = (data['Contest_ID'] ?? contest.id).toString();
          final rawTopics = data['Topics'];
          final topics = rawTopics is Iterable
              ? rawTopics.map((e) => e.toString()).join(', ')
              : (rawTopics?.toString() ?? '');
          final date = _date(data);
          return Card(
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text('Contest #$id',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('$topics\n${date == null ? 'Date unavailable' : formatDate(date)}'),
              isThreeLine: true,
              trailing: Text(
                scoreForContest(id, resultByContest[id]),
                style: const TextStyle(
                  color: Color(0xFF4F46E5),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
