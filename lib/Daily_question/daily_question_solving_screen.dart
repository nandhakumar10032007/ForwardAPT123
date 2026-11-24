import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'daily_question_calendar_screen.dart';
import '../services/daily_question_submission_service.dart';

/// Daily Question UI only. Answer submission will be connected later.
class DailyQuestionSolvingScreen extends StatefulWidget {
  final DateTime? selectedDate;

  const DailyQuestionSolvingScreen({super.key, this.selectedDate});

  @override
  State<DailyQuestionSolvingScreen> createState() =>
      _DailyQuestionSolvingScreenState();
}

class _DailyQuestionSolvingScreenState
    extends State<DailyQuestionSolvingScreen> {
  static const _primary = Color(0xFF4F46E5);
  static const _background = Color(0xFFF7F8FC);
  static const _text = Color(0xFF171923);
  static const _muted = Color(0xFF777A87);

  final _answerController = TextEditingController();
  final DailyQuestionSubmissionService _submissionService =
      DailyQuestionSubmissionService();
  bool _isSubmitting = false;
  bool _isAnswerInvalid = false;
  late DateTime _selectedDate;

  User? get _user => FirebaseAuth.instance.currentUser;

  String _dateId(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  DocumentReference<Map<String, dynamic>> get _questionRef {
    final year = _selectedDate.year.toString();
    final month = _selectedDate.month.toString().padLeft(2, '0');
    return FirebaseFirestore.instance
        .collection('dailyQuestions')
        .doc(year)
        .collection('months')
        .doc(month)
        .collection('questions')
        .doc(_dateId(_selectedDate));
  }

  DocumentReference<Map<String, dynamic>>? get _solvedRef {
    final user = _user;
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('DailyQuestionSolved')
        .doc(_dateId(_selectedDate));
  }

  @override
  void initState() {
    super.initState();
    final date = widget.selectedDate ?? DateTime.now();
    _selectedDate = DateTime(date.year, date.month, date.day);

    // Sync only the Daily Questions streak when this page opens.
    // This does not touch the Common Questions streak fields.
    _syncDailyQuestionsStreak();
  }

  Future<void> _syncDailyQuestionsStreak() async {
    try {
      // This service method updates Daily Questions streak fields only.
      await _submissionService.syncStreakOnDailyQuestionsOpen();
    } catch (e) {
      debugPrint('Daily Questions streak sync failed: $e');
    }
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _openCalendar() async {
    final date = await Navigator.push<DateTime>(
      context,
      MaterialPageRoute(
        builder: (_) => DailyQuestionCalendarScreen(initialDate: _selectedDate),
      ),
    );
    if (!mounted || date == null) return;
    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
      _answerController.clear();
    });
  }

  void _insert(String value) {
    _resetInvalidAnswer();
    _answerController.text += value == '−' ? '-' : value;
    _answerController.selection = TextSelection.collapsed(
      offset: _answerController.text.length,
    );
    setState(() {});
  }

  void _backspace() {
    _resetInvalidAnswer();
    final value = _answerController.text;
    if (value.isEmpty) return;
    _answerController.text = value.substring(0, value.length - 1);
    _answerController.selection = TextSelection.collapsed(
      offset: _answerController.text.length,
    );
    setState(() {});
  }

  Future<void> _submitAnswer() async {
    if (_isSubmitting) return;

    final answer = _answerController.text.trim();

    if (answer.isEmpty) {
      setState(() {});
      _showInvalidAnswerLabel();
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final result = await _submissionService.submitAnswer(
        questionDate: _selectedDate,
        submittedAnswer: answer,
      );

      if (!mounted) return;

      switch (result.status) {
        case DailyAnswerStatus.correct:
          _answerController.clear();
          _showCorrectAnswerPopup();
          break;

        case DailyAnswerStatus.incorrect:
          _showWrongAnswerPopup();
          break;

        case DailyAnswerStatus.invalidFormat:
          _showInvalidAnswerLabel();
          break;

        case DailyAnswerStatus.alreadySolved:
          _showCorrectAnswerPopup();
          break;

        case DailyAnswerStatus.questionNotFound:
        case DailyAnswerStatus.futureQuestion:
        case DailyAnswerStatus.notLoggedIn:
        case DailyAnswerStatus.error:
          _showSubmissionMessage(result.message, Colors.red);
          break;
      }

      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _showSubmissionMessage(
        'Something went wrong. Please try again.',
        Colors.red,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ============================================================
  // INVALID ANSWER INLINE LABEL (MATCHES COMMON QUESTIONS)
  // ============================================================

  void _showInvalidAnswerLabel() {
    if (!mounted) return;
    setState(() {
      _isAnswerInvalid = true;
    });
  }

  void _resetInvalidAnswer() {
    if (!_isAnswerInvalid || !mounted) return;
    setState(() {
      _isAnswerInvalid = false;
    });
  }

  // ============================================================
  // CORRECT ANSWER POPUP
  // ============================================================

  void _showCorrectAnswerPopup() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '🎉🥳🏆',
                style: TextStyle(fontSize: 48),
              ),
              const SizedBox(height: 16),
              const Text(
                'Amazing!',
                style: TextStyle(
                  color: Color(0xFF15803D),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your answer is absolutely correct!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _text,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF15803D),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Awesome!',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // WRONG ANSWER POPUP
  // ============================================================

  void _showWrongAnswerPopup() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '😢💭',
                style: TextStyle(fontSize: 48),
              ),
              const SizedBox(height: 16),
              const Text(
                'Not Quite!',
                style: TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your answer is incorrect. Don\'t give up, try again!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _text,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Try Again',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSubmissionMessage(String message, Color color) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  void _showTypeInfo(String rawType) {
    final type = rawType.trim().toLowerCase();
    final info = switch (type) {
      'radio' || 'ratio' => ('Ratio', 'Two values separated by a colon (a:b)', '5:17'),
      'fraction' => ('Fraction', 'Numerator/denominator (p/q)', '3/4'),
      'percentage' || 'percent' => ('Percentage', 'Number optionally followed by %', '100%'),
      'decimal' => ('Decimal', 'A number using decimal notation', '5.17'),
      _ => (rawType.isEmpty ? 'Not specified' : rawType,
          'Follow the format specified in the question', 'Example not available'),
    };

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Answer Type Guide',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              _infoRow('Type', info.$1),
              const SizedBox(height: 10),
              _infoRow('Expected Format', info.$2),
              const SizedBox(height: 10),
              _infoRow('Example', info.$3),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: _dateId(_selectedDate) == _dateId(DateTime.now())
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: _text),
                onPressed: _openCalendar,
              ),
       title: Row(
  children: [
    Image.asset(
      'assets/app_icon.png',
      width: 38,
      height: 38,
      fit: BoxFit.cover,
    ),

    const SizedBox(width: 10),

    const Flexible(
      child: Text(
        'ForwardAPT Daily Question',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _text,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  ],
),
        actions: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _user == null
                ? null
                : FirebaseFirestore.instance.collection('users').doc(_user!.uid).snapshots(),
            builder: (context, snapshot) {
              final streak = (snapshot.data?.data()?['currentStreak'] as num?)?.toInt() ?? 0;
              return Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1E8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.local_fire_department_rounded,
                          color: Color(0xFFF97316), size: 20),
                      const SizedBox(width: 3),
                      Text('$streak',
                          style: const TextStyle(
                              color: Color(0xFF9A3412), fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Calendar',
            onPressed: _openCalendar,
            icon: const Icon(Icons.calendar_month_rounded, color: _primary),
          ),
          const SizedBox(width: 5),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFE7E8EE)),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _questionRef.snapshots(),
          builder: (context, questionSnapshot) {
            if (questionSnapshot.hasError) {
              return _message('Could Not Load Question',
                  'Please check your connection and try again.', Icons.cloud_off_rounded);
            }
            if (questionSnapshot.connectionState == ConnectionState.waiting &&
                !questionSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator(color: _primary));
            }
            final document = questionSnapshot.data;
            if (document == null || !document.exists) {
              return _message(
                'No Daily Question',
                'There is no question uploaded for ${_dateId(_selectedDate)}. '
                    'Choose an available date from the calendar.',
                Icons.event_busy_rounded,
                showCalendar: true,
              );
            }

            final data = document.data() ?? {};
            final questionNo = (data['questionNo'] ?? '?').toString();
            final title = (data['title'] ?? 'Question').toString();
            final question = (data['question'] ?? '').toString();
            final topic = (data['topic'] ?? 'General').toString();
            final difficulty = (data['difficulty'] ?? '').toString();
            final answerType = (data['answerType'] ?? '').toString();

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _solvedRef?.snapshots(),
              builder: (context, solvedSnapshot) {
                final solved = solvedSnapshot.hasData && solvedSnapshot.data!.exists;
                final statusColor = solved ? const Color(0xFF15803D) : const Color(0xFFDC2626);
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: solved ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(solved ? Icons.check_circle_rounded : Icons.circle_rounded,
                                color: statusColor, size: 15),
                            const SizedBox(width: 6),
                            Text(solved ? 'Solved' : 'Unsolved',
                                style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w800)),
                          ]),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => _showTypeInfo(answerType),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE3E4EA)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('Type: ${answerType.isEmpty ? 'Not specified' : answerType}',
                                  style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w700)),
                              const SizedBox(width: 5),
                              const Icon(Icons.info_outline_rounded, color: _primary, size: 18),
                            ]),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 18),
                      _questionCard(questionNo, title, question, topic, difficulty),
                      const SizedBox(height: 20),
                      _answerInput(),
                      const SizedBox(height: 16),
                      _keyboard(),
                      const SizedBox(height: 12),
                      Text('Question date: ${_dateId(_selectedDate)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _muted, fontSize: 12)),
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

  Widget _questionCard(String no, String title, String question, String topic, String difficulty) {
    final color = switch (difficulty.toLowerCase()) {
      'easy' => const Color(0xFF15803D),
      'medium' => const Color(0xFFB45309),
      'hard' => const Color(0xFFDC2626),
      _ => _primary,
    };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E6EB)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.025), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(color: const Color(0xFFEDEBFF), borderRadius: BorderRadius.circular(9)),
            child: Text('Q$no', style: const TextStyle(color: _primary, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const Spacer(),
          if (difficulty.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(20)),
              child: Text(difficulty, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
        ]),
        const SizedBox(height: 17),
        Text(title, style: const TextStyle(color: _text, fontSize: 19, height: 1.3, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        SelectableText(question, style: const TextStyle(color: Color(0xFF444754), fontSize: 16, height: 1.65)),
        if (topic.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(children: [
            const Icon(Icons.category_outlined, color: _muted, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(topic, style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600))),
          ]),
        ],
      ]),
    );
  }

  Widget _answerInput() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            _isAnswerInvalid
                ? 'Invalid answer. Please enter the answer in the correct format.'
                : 'Enter your answer',
            style: TextStyle(
              color: _isAnswerInvalid ? const Color(0xFFDC2626) : _muted,
              fontSize: 13,
              fontWeight: _isAnswerInvalid ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(15, 7, 8, 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isAnswerInvalid
                  ? const Color(0xFFDC2626)
                  : const Color(0xFFDADCE5),
              width: _isAnswerInvalid ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            const Icon(Icons.edit_outlined, color: _muted, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _answerController,
                readOnly: true,
                showCursor: true,
                enableInteractiveSelection: false,
                decoration: const InputDecoration(
                  hintText: 'Enter your answer...',
                  hintStyle: TextStyle(color: Color(0xFF9A9DA8), fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                ),
                style: const TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            if (_answerController.text.isNotEmpty)
              IconButton(
                onPressed: () { _answerController.clear(); setState(() {}); },
                icon: const Icon(Icons.close_rounded, color: _muted),
              ),
          ]),
        ),
      ]);

  Widget _keyboard() {
    const numberRows = [
      ['1', '2', '3', '4', '5'],
      ['6', '7', '8', '9', '0'],
    ];
    const symbols = ['.', '−', '/', '%', ':', '^', '√'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E6EB)),
      ),
      child: Column(
        children: [
          for (final row in numberRows)
            Row(
              children: [
                for (final key in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _key(key, () => _insert(key)),
                    ),
                  ),
              ],
            ),
          Row(
            children: [
              for (final key in symbols)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: _key(
                      key,
                      () => _insert(key),
                      compact: true,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitAnswer,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 17,
                          ),
                    label: Text(
                      _isSubmitting ? 'SUBMITTING...' : 'SUBMIT',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .4,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      disabledBackgroundColor: _primary,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _key(
                  'Backspace',
                  _backspace,
                  icon: Icons.backspace_outlined,
                  utility: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _isSubmitting
                ? 'Checking your answer...'
                : 'Enter your answer and tap submit.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _key(String label, VoidCallback onTap, {IconData? icon, bool compact = false, bool utility = false}) {
    return Material(
      color: utility ? const Color(0xFFEDEBFF) : _background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: compact ? 47 : 50,
          child: Center(
            child: icon == null
                ? Text(label, style: TextStyle(color: utility ? _primary : _text, fontSize: compact ? 16 : 19, fontWeight: FontWeight.w700))
                : Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 17, color: _primary),
                    const SizedBox(width: 5),
                    Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _primary, fontSize: 11, fontWeight: FontWeight.w700))),
                  ]),
          ),
        ),
      ),
    );
  }

  Widget _message(String title, String message, IconData icon, {bool showCalendar = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: const Color(0xFF9A9DA8)),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: _text, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 14, height: 1.5)),
            if (showCalendar) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(onPressed: _openCalendar, icon: const Icon(Icons.calendar_month_rounded), label: const Text('Open Calendar')),
            ],
          ]),
        ),
      );
}
