import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/contest_submit_service.dart';

/// Contest solving screen with Firebase-backed submission and live penalty display.
class ContestSolvingScreen extends StatefulWidget {
  final String contestId;
  final String? initialQuestionId;
  final VoidCallback? onSubmit;

  const ContestSolvingScreen({
    super.key,
    required this.contestId,
    this.initialQuestionId,
    this.onSubmit,
  });

  @override
  State<ContestSolvingScreen> createState() => _ContestSolvingScreenState();
}

class _ContestSolvingScreenState extends State<ContestSolvingScreen> {
  static const Color _primary = Color(0xFF4F46E5);
  static const Color _background = Color(0xFFF7F8FC);
  static const Color _text = Color(0xFF171923);
  static const Color _muted = Color(0xFF777A87);
  static const Color _error = Color(0xFFDC2626);

  final TextEditingController _answerController = TextEditingController();
  final FocusNode _answerFocusNode = FocusNode();
  final Map<String, String> _answers = {};
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _questionsStream;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _progressSubscription;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _questions = [];
  int _currentIndex = 0;
  bool _loadedInitialSelection = false;
  bool _isAnswerInvalid = false;
  bool _isSubmitting = false;
  final Set<String> _solvedQuestionIds = {};
  final ContestSubmitService _submitService = ContestSubmitService();
  String _answerLabel = 'Enter your answer';

  @override
  void initState() {
    super.initState();
    _questionsStream = FirebaseFirestore.instance
        .collection('Contest_Questions')
        .doc(widget.contestId)
        .collection('Questions')
        .snapshots();

    // Restore solved-question state from Firestore whenever this screen opens.
    // This listener also keeps the solving UI synchronized with live progress.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _progressSubscription = FirebaseFirestore.instance
          .collection('Contest_Questions')
          .doc(widget.contestId)
          .collection('Registered')
          .doc(uid)
          .collection('Result')
          .snapshots()
          .listen((snapshot) {
        if (!mounted) return;

        final solvedIds = snapshot.docs
            .where((doc) =>
                (doc.data()['Status'] ?? '').toString().toLowerCase() ==
                'solved')
            .map((doc) => doc.id)
            .toSet();

        setState(() {
          _solvedQuestionIds
            ..clear()
            ..addAll(solvedIds);
        });
      });
    }
  }

  @override
  void didUpdateWidget(covariant ContestSolvingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuestionId != widget.initialQuestionId) {
      _loadedInitialSelection = false;
      if (_questions.isNotEmpty) _selectInitialQuestion();
    }
  }

  @override
  void dispose() {
    _saveCurrentAnswer();
    _progressSubscription?.cancel();
    _answerController.dispose();
    _answerFocusNode.dispose();
    super.dispose();
  }

  String? get _currentQuestionId => _questions.isEmpty ? null : _questions[_currentIndex].id;
  Map<String, dynamic> get _currentData => _questions.isEmpty ? {} : _questions[_currentIndex].data();

  String _difficulty(String id, Map<String, dynamic> data) {
    final value = (data['difficulty'] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
    if (id.startsWith('M')) return 'Medium';
    if (id.startsWith('H')) return 'Hard';
    return 'Easy';
  }

  int _difficultyOrder(String value) {
    switch (value.toLowerCase()) {
      case 'easy': return 0;
      case 'medium': return 1;
      case 'hard': return 2;
      default: return 3;
    }
  }

  void _sortAndSetQuestions(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final oldId = _currentQuestionId;
    final sorted = [...docs];
    sorted.sort((a, b) {
      final compare = _difficultyOrder(_difficulty(a.id, a.data()))
          .compareTo(_difficultyOrder(_difficulty(b.id, b.data())));
      return compare != 0 ? compare : a.id.compareTo(b.id);
    });
    _questions = sorted;
    if (!_loadedInitialSelection) {
      _selectInitialQuestion();
    } else if (_questions.isNotEmpty) {
      final found = oldId == null ? -1 : _questions.indexWhere((q) => q.id == oldId);
      _currentIndex = found >= 0 ? found : 0;
      _restoreAnswer();
    }
  }

  void _selectInitialQuestion() {
    if (_questions.isEmpty) return;
    final requested = widget.initialQuestionId;
    final index = requested == null ? -1 : _questions.indexWhere((q) => q.id == requested);
    _currentIndex = index >= 0 ? index : 0;
    _loadedInitialSelection = true;
    _restoreAnswer();
  }

  void _saveCurrentAnswer() {
    final id = _currentQuestionId;
    if (id != null) _answers[id] = _answerController.text;
  }

  void _restoreAnswer() {
    if (_questions.isEmpty) return;
    final answer = _answers[_questions[_currentIndex].id] ?? '';
    _answerController.value = TextEditingValue(
      text: answer,
      selection: TextSelection.collapsed(offset: answer.length),
    );
    _isAnswerInvalid = false;
    _answerLabel = 'Enter your answer';
  }

  void _goToQuestion(int index) {
    if (index < 0 || index >= _questions.length) return;
    _saveCurrentAnswer();
    FocusScope.of(context).unfocus();
    setState(() {
      _currentIndex = index;
      _restoreAnswer();
    });
  }

  void _insertSymbol(String symbol) {
    final text = _answerController.text + (symbol == '−' ? '-' : symbol);
    _answerController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
    _saveCurrentAnswer();
    _resetAnswerLabel();
  }

  void _backspace() {
    final current = _answerController.text;
    if (current.isEmpty) return;
    final text = current.substring(0, current.length - 1);
    _answerController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
    _saveCurrentAnswer();
    _resetAnswerLabel();
  }

  void _clearAnswer() {
    _answerController.clear();
    _saveCurrentAnswer();
    _resetAnswerLabel();
  }

  void _resetAnswerLabel() {
    setState(() {
      _isAnswerInvalid = false;
      _answerLabel = 'Enter your answer';
    });
    _answerFocusNode.requestFocus();
  }


  // Submit the currently selected question's answer.
  // Uses the same correct/wrong dialogs as QuestionDetailedViewScreen.
  Future<void> _submitAnswer() async {
    final questionId = _currentQuestionId;
    if (questionId == null || _isSubmitting) return;

    // Firestore progress is authoritative; never submit an already-solved question.
    if (_solvedQuestionIds.contains(questionId)) {
      setState(() {
        _answerController.clear();
        _answers.remove(questionId);
        _isAnswerInvalid = false;
        _answerLabel = 'This question is already solved.';
      });
      return;
    }

    final answer = _answerController.text.trim();
    if (answer.isEmpty) {
      setState(() {
        _isAnswerInvalid = true;
        _answerLabel =
            'Invalid answer. Please enter the answer in the correct format.';
      });
      return;
    }

    _saveCurrentAnswer();
    FocusScope.of(context).unfocus();

    setState(() {
      _isSubmitting = true;
      _isAnswerInvalid = false;
      _answerLabel = 'Checking your answer...';
    });

    try {
      final result = await _submitService.submitAnswer(
        contestId: widget.contestId,
        questionId: questionId,
        submittedAnswer: answer,
      );

      if (!mounted) return;

      switch (result.status) {
        case ContestSubmissionStatus.correct:
          setState(() {
            _solvedQuestionIds.add(questionId);
            _answers.remove(questionId);
            _answerController.clear();
            _isAnswerInvalid = false;
            _answerLabel = 'Correct answer!';
          });
          _showCorrectAnswerPopup();
          break;

        case ContestSubmissionStatus.alreadySolved:
          setState(() {
            _solvedQuestionIds.add(questionId);
            _answers.remove(questionId);
            _answerController.clear();
            _isAnswerInvalid = false;
            _answerLabel = 'Already solved';
          });
          _showCorrectAnswerPopup();
          break;

        case ContestSubmissionStatus.incorrect:
          setState(() {
            _isAnswerInvalid = false;
            _answerLabel = 'Enter your answer';
            _answers[questionId] = answer;
          });
          _showWrongAnswerPopup(
            penaltyMark: result.penaltyMark,
            penaltyCount: result.penaltyCount,
          );
          break;

        case ContestSubmissionStatus.invalidFormat:
          setState(() {
            _isAnswerInvalid = true;
            _answerLabel =
                'Invalid answer. Please enter the answer in the correct format.';
            _answers[questionId] = answer;
          });
          break;

        case ContestSubmissionStatus.contestNotStarted:
        case ContestSubmissionStatus.contestEnded:
        case ContestSubmissionStatus.notRegistered:
        case ContestSubmissionStatus.notLoggedIn:
        case ContestSubmissionStatus.questionNotFound:
        case ContestSubmissionStatus.error:
          setState(() {
            _answerLabel = result.message;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red.shade700,
            ),
          );
          break;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _answerLabel = 'Enter your answer';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Submission failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  // Same popup design as QuestionDetailedViewScreen.
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
              const Text('🎉🥳🏆', style: TextStyle(fontSize: 48)),
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
                style: TextStyle(color: _text, fontSize: 15, height: 1.5),
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

  // Same popup design as QuestionDetailedViewScreen, with Contest penalty info.
  void _showWrongAnswerPopup({
    required double penaltyMark,
    required int penaltyCount,
  }) {
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
              const Text('😢💭', style: TextStyle(fontSize: 48)),
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
                "Your answer is incorrect. Don't give up, try again!",
                textAlign: TextAlign.center,
                style: TextStyle(color: _text, fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 12),
              Text(
                'Penalty: -${penaltyMark.toStringAsFixed(2)} marks  •  Wrong attempts: $penaltyCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _answerFocusNode.requestFocus();
                  },
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

  _AnswerTypeInfo _answerTypeInfo(String rawType) {
    final type = rawType.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    switch (type) {
      case 'percentage': case 'percent':
        return const _AnswerTypeInfo(label: 'Percentage', format: 'Number optionally followed by %', example: '100%');
      case 'fraction':
        return const _AnswerTypeInfo(label: 'Fraction', format: 'Numerator/denominator (p/q)', example: '3/4');
      case 'mixedfraction': case 'mixednumber':
        return const _AnswerTypeInfo(label: 'Mixed Fraction', format: 'Whole number followed by a fraction', example: '5 1/2');
      case 'radio': case 'ratio':
        return const _AnswerTypeInfo(label: 'Ratio', format: 'Two values separated by a colon (a:b)', example: '5:17');
      case 'exponent': case 'exponential':
        return const _AnswerTypeInfo(label: 'Exponent', format: 'Base^exponent', example: '2^3');
      case 'integer':
        return const _AnswerTypeInfo(label: 'Integer', format: 'Whole number, positive or negative', example: '-5');
      case 'decimal':
        return const _AnswerTypeInfo(label: 'Decimal', format: 'A number using decimal notation', example: '5.17');
      default:
        return _AnswerTypeInfo(label: rawType.trim().isEmpty ? 'Not specified' : rawType.trim(), format: 'Follow the format specified in the question', example: 'Example not available');
    }
  }

  void _showAnswerTypeInfo(String rawType) {
    final info = _answerTypeInfo(rawType);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFD9DAE2), borderRadius: BorderRadius.circular(20)))),
            const SizedBox(height: 22),
            const Text('Answer Type Guide', style: TextStyle(color: _text, fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            _infoRow('Type', info.label),
            const SizedBox(height: 12),
            _infoRow('Expected Format', info.format),
            const SizedBox(height: 12),
            _infoRow('Example', info.example, emphasize: true),
            const SizedBox(height: 22),
            SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
              onPressed: () => Navigator.pop(sheetContext),
              style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
              child: const Text('Got it'),
            )),
          ]),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool emphasize = false}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: _background, borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFFE8E9F0))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 5),
      Text(value, style: TextStyle(color: emphasize ? _primary : _text, fontSize: emphasize ? 17 : 14, fontWeight: FontWeight.w700)),
    ]),
  );

  Color _difficultyColor(String difficulty) {
    switch (difficulty.trim().toLowerCase()) {
      case 'easy': return const Color(0xFF15803D);
      case 'medium': return const Color(0xFFB45309);
      case 'hard': return const Color(0xFFDC2626);
      default: return _primary;
    }
  }

  Widget _smallBadge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Doing', style: TextStyle(color: _text, fontSize: 19, fontWeight: FontWeight.w800)),
        actions: [Padding(padding: const EdgeInsets.only(right: 18), child: Center(child: Text(_questions.isEmpty ? '' : '${_currentIndex + 1} / ${_questions.length}', style: const TextStyle(color: _muted, fontWeight: FontWeight.w700))))],
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Color(0xFFE7E8EE))),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _questionsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) return _messageState(icon: Icons.cloud_off_rounded, title: 'Could Not Load Questions', message: 'Please check your connection and try again.');
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: _primary));
            _sortAndSetQuestions(snapshot.data!.docs);
            if (_questions.isEmpty) return _messageState(icon: Icons.search_off_rounded, title: 'No Questions Found', message: 'There are no questions available in this contest.');
            final data = _currentData;
            final id = _currentQuestionId ?? '';
            final questionNo = (data['questionNo'] ?? id).toString();
            final title = (data['title'] ?? 'Question').toString();
            final question = (data['question'] ?? '').toString();
            final topic = (data['topic'] ?? 'General').toString();
            final difficulty = _difficulty(id, data);
            final answerType = (data['answerType'] ?? '').toString();
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _buildStatusAndType(answerType),
                const SizedBox(height: 18),
                _buildQuestionCard(questionId: id, questionNo: questionNo, title: title, questionText: question, topic: topic, difficulty: difficulty),
                const SizedBox(height: 20),
                _buildAnswerInput(),
                const SizedBox(height: 16),
                _buildPreviousNext(),
                const SizedBox(height: 16),
                _buildCustomKeyboard(),
              ]),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusAndType(String answerType) {
    final isSolved = _currentQuestionId != null &&
        _solvedQuestionIds.contains(_currentQuestionId);
    final statusColor = isSolved ? const Color(0xFF15803D) : _error;

    return Row(children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle_rounded, color: statusColor, size: 15),
        const SizedBox(width: 6),
        Text(
          isSolved ? 'Solved' : 'Unsolved',
          style: TextStyle(
            color: statusColor,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ]),
    ),
    const Spacer(),
    Flexible(child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showAnswerTypeInfo(answerType),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE3E4EA))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text('Type: ${_answerTypeInfo(answerType).label}', overflow: TextOverflow.ellipsis, style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w700))),
          const SizedBox(width: 5),
          const Icon(Icons.info_outline_rounded, color: _primary, size: 18),
        ]),
      ),
    )),
    ]);
  }

  /// Live penalty indicator for the currently displayed question.
  /// It reads the signed-in student's own Result/{questionId} document.
  Widget _buildPenaltyIndicator(String questionId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    final progressStream = FirebaseFirestore.instance
        .collection('Contest_Questions')
        .doc(widget.contestId)
        .collection('Registered')
        .doc(uid)
        .collection('Result')
        .doc(questionId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: progressStream,
      builder: (context, snapshot) {
        final rawCount = snapshot.data?.data()?['Penalty_Count'];
        final penaltyCount = rawCount is num
            ? rawCount.toInt()
            : int.tryParse(rawCount?.toString() ?? '') ?? 0;

        // Do not occupy any space when there have been no wrong attempts.
        if (!snapshot.hasData || penaltyCount <= 0) {
          return const SizedBox.shrink();
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: const Size(30, 25),
              painter: _RedDinosaurPainter(),
            ),
            const SizedBox(width: 4),
            Container(
              constraints: const BoxConstraints(minWidth: 21, minHeight: 21),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: const BoxDecoration(
                color: Color(0xFFDC2626),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$penaltyCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuestionCard({required String questionId, required String questionNo, required String title, required String questionText, required String topic, required String difficulty}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE5E6EB)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .025), blurRadius: 12, offset: const Offset(0, 4))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _smallBadge('Q$questionNo', _difficultyColor(difficulty)),
          ),
        ),
        Expanded(
          child: Center(child: _buildPenaltyIndicator(questionId)),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: difficulty.trim().isNotEmpty
                ? _smallBadge(difficulty, _difficultyColor(difficulty))
                : const SizedBox.shrink(),
          ),
        ),
      ]),
      const SizedBox(height: 17),
      Text(title, style: const TextStyle(color: _text, fontSize: 19, height: 1.3, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      SelectableText(questionText, style: const TextStyle(color: Color(0xFF444754), fontSize: 16, height: 1.65)),
      if (topic.trim().isNotEmpty) ...[
        const SizedBox(height: 18),
        Row(children: [const Icon(Icons.category_outlined, color: _muted, size: 16), const SizedBox(width: 6), Expanded(child: Text(topic, style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600))) ]),
      ],
    ]),
  );

  Widget _buildAnswerInput() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text(_answerLabel, style: TextStyle(color: _isAnswerInvalid ? _error : _muted, fontSize: 13, fontWeight: _isAnswerInvalid ? FontWeight.w700 : FontWeight.w600))),
    Container(
      padding: const EdgeInsets.fromLTRB(15, 7, 8, 7),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _isAnswerInvalid ? _error : const Color(0xFFDADCE5), width: _isAnswerInvalid ? 1.5 : 1)),
      child: Row(children: [
        Icon(Icons.edit_outlined, color: _isAnswerInvalid ? _error : _muted, size: 21),
        const SizedBox(width: 10),
        Expanded(child: TextField(
          controller: _answerController,
          focusNode: _answerFocusNode,
          readOnly: true,
          showCursor: true,
          enableInteractiveSelection: false,
          onTap: () { _answerController.selection = TextSelection.collapsed(offset: _answerController.text.length); _answerFocusNode.requestFocus(); },
          decoration: const InputDecoration(hintText: 'Enter your answer...', hintStyle: TextStyle(color: Color(0xFF9A9DA8), fontSize: 14), border: InputBorder.none, isDense: true),
          style: const TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w600),
        )),
        if (_answerController.text.isNotEmpty) IconButton(tooltip: 'Clear answer', onPressed: _clearAnswer, icon: const Icon(Icons.close_rounded, color: _muted, size: 19)),
      ]),
    ),
  ]);

  Widget _buildPreviousNext() => Row(children: [
    Expanded(child: OutlinedButton.icon(
      onPressed: _currentIndex > 0 ? () => _goToQuestion(_currentIndex - 1) : null,
      icon: const Icon(Icons.chevron_left_rounded),
      label: const Text('Previous'),
      style: OutlinedButton.styleFrom(foregroundColor: _primary, disabledForegroundColor: const Color(0xFFB8B9C4), padding: const EdgeInsets.symmetric(vertical: 13), side: const BorderSide(color: Color(0xFFD8D6FA)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
    )),
    const SizedBox(width: 12),
    Expanded(child: ElevatedButton.icon(
      onPressed: _currentIndex < _questions.length - 1 ? () => _goToQuestion(_currentIndex + 1) : null,
      icon: const Icon(Icons.chevron_right_rounded),
      label: const Text('Next'),
      iconAlignment: IconAlignment.end,
      style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white, disabledBackgroundColor: const Color(0xFFE5E7EB), disabledForegroundColor: const Color(0xFF9CA3AF), padding: const EdgeInsets.symmetric(vertical: 13), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
    )),
  ]);

  Widget _buildCustomKeyboard() {
    const numberRows = <List<String>>[['1', '2', '3', '4', '5'], ['6', '7', '8', '9', '0']];
    const symbolKeys = ['.', '−', '/', '%', ':', '^', '√'];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE5E6EB))),
      child: Column(children: [
        for (final row in numberRows) Row(children: [for (final key in row) Expanded(child: Padding(padding: const EdgeInsets.all(4), child: _keyboardKey(label: key, onTap: () => _insertSymbol(key))))]),
        Row(children: [for (final key in symbolKeys) Expanded(child: Padding(padding: const EdgeInsets.all(3), child: _keyboardKey(label: key, compact: true, onTap: () => _insertSymbol(key))))]),
        const SizedBox(height: 7),
        Row(children: [
          Expanded(flex: 2, child: SizedBox(height: 48, child: ElevatedButton.icon(
            onPressed: (_isSubmitting ||
                    (_currentQuestionId != null &&
                        _solvedQuestionIds.contains(_currentQuestionId)))
                ? null
                : _submitAnswer,
            icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
            label: Text(
              _isSubmitting ? 'SUBMITTING...' : 'SUBMIT',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: .4,
              ),
            ),
            style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white, disabledBackgroundColor: const Color(0xFF9CA3AF), disabledForegroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          ))),
          const SizedBox(width: 8),
          Expanded(child: _keyboardKey(label: 'Backspace', icon: Icons.backspace_outlined, onTap: _backspace, isUtility: true)),
        ]),
        const SizedBox(height: 8),
        const Text('Enter your answer using the keyboard above.', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 11, height: 1.3)),
      ]),
    );
  }

  Widget _keyboardKey({required String label, required VoidCallback onTap, IconData? icon, bool compact = false, bool isUtility = false}) => Material(
    color: isUtility ? const Color(0xFFEDEBFF) : const Color(0xFFF7F8FC),
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(height: compact ? 47 : 50, child: Center(child: icon == null
        ? Text(label, style: TextStyle(color: isUtility ? _primary : _text, fontSize: compact ? 16 : 19, fontWeight: FontWeight.w700))
        : Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 17, color: _primary), const SizedBox(width: 5), Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _primary, fontSize: 11, fontWeight: FontWeight.w700))) ]))),
    ),
  );

  Widget _messageState({required IconData icon, required String title, required String message}) => Center(
    child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 48, color: const Color(0xFF9A9DA8)),
      const SizedBox(height: 14),
      Text(title, textAlign: TextAlign.center, style: const TextStyle(color: _text, fontSize: 19, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 14, height: 1.5)),
    ])),
  );
}

/// Small red dinosaur mascot drawn with Flutter Canvas, so no image asset is
/// required in the project or pubspec.yaml.
class _RedDinosaurPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final red = Paint()..color = const Color(0xFFEF2929);
    final darkRed = Paint()..color = const Color(0xFFB91C1C);
    final cream = Paint()..color = const Color(0xFFFFE1B8);
    final white = Paint()..color = Colors.white;
    final black = Paint()..color = const Color(0xFF262626);

    // Tail and body.
    final tail = Path()
      ..moveTo(size.width * .28, size.height * .60)
      ..lineTo(size.width * .02, size.height * .38)
      ..lineTo(size.width * .13, size.height * .72)
      ..close();
    canvas.drawPath(tail, red);
    canvas.drawOval(
      Rect.fromLTWH(size.width * .18, size.height * .39, size.width * .53, size.height * .49),
      red,
    );

    // Neck, head and snout.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .53, size.height * .25, size.width * .22, size.height * .49),
        const Radius.circular(5),
      ),
      red,
    );
    canvas.drawCircle(Offset(size.width * .69, size.height * .25), size.height * .22, red);
    canvas.drawOval(
      Rect.fromLTWH(size.width * .69, size.height * .20, size.width * .29, size.height * .22),
      red,
    );

    // Back spikes.
    final spikes = Path()
      ..moveTo(size.width * .27, size.height * .43)
      ..lineTo(size.width * .34, size.height * .18)
      ..lineTo(size.width * .43, size.height * .43)
      ..lineTo(size.width * .48, size.height * .12)
      ..lineTo(size.width * .57, size.height * .40)
      ..close();
    canvas.drawPath(spikes, darkRed);

    // Belly and smile.
    canvas.drawOval(
      Rect.fromLTWH(size.width * .39, size.height * .62, size.width * .29, size.height * .22),
      cream,
    );
    final smile = Path()
      ..moveTo(size.width * .76, size.height * .34)
      ..quadraticBezierTo(size.width * .86, size.height * .43, size.width * .95, size.height * .34);
    canvas.drawPath(
      smile,
      Paint()
        ..color = const Color(0xFF7F1D1D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );

    // Legs and eye.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .30, size.height * .76, size.width * .15, size.height * .20),
        const Radius.circular(3),
      ),
      darkRed,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .58, size.height * .76, size.width * .15, size.height * .20),
        const Radius.circular(3),
      ),
      darkRed,
    );
    canvas.drawCircle(Offset(size.width * .70, size.height * .18), size.height * .065, white);
    canvas.drawCircle(Offset(size.width * .72, size.height * .18), size.height * .035, black);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AnswerTypeInfo {
  final String label;
  final String format;
  final String example;
  const _AnswerTypeInfo({required this.label, required this.format, required this.example});
}
