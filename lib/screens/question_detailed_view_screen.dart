import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/answer_submission_service.dart';

class QuestionDetailedViewScreen extends StatefulWidget {
  final String questionId;
  final int? questionNo;
  final String? title;
  final String? question;
  final String? topic;
  final String? difficulty;
  final String? answerType;

  const QuestionDetailedViewScreen({
    super.key,
    required this.questionId,
    this.questionNo,
    this.title,
    this.question,
    this.topic,
    this.difficulty,
    this.answerType,
  });

  @override
  State<QuestionDetailedViewScreen> createState() =>
      _QuestionDetailedViewScreenState();
}

class _QuestionDetailedViewScreenState
    extends State<QuestionDetailedViewScreen> {
  static const Color _primary = Color(0xFF4F46E5);
  static const Color _background = Color(0xFFF7F8FC);
  static const Color _text = Color(0xFF171923);
  static const Color _muted = Color(0xFF777A87);
  static const Color _error = Color(0xFFDC2626);

  final TextEditingController _answerController =
      TextEditingController();

  final FocusNode _answerFocusNode = FocusNode();

  final AnswerSubmissionService _answerService =
      AnswerSubmissionService();

  bool _isSubmitting = false;
  bool _isAnswerInvalid = false;

  String _answerLabel = 'Enter your answer';

  User? get _user => FirebaseAuth.instance.currentUser;

  DocumentReference<Map<String, dynamic>> get _questionReference =>
      FirebaseFirestore.instance
          .collection('commonQuestions')
          .doc(widget.questionId);

  DocumentReference<Map<String, dynamic>>? get _solvedReference {
    final user = _user;

    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('solvedQuestions')
        .doc(widget.questionId);
  }

  @override
  void dispose() {
    _answerController.dispose();
    _answerFocusNode.dispose();
    super.dispose();
  }

  // ============================================================
  // CUSTOM KEYBOARD INPUT
  // ============================================================

  void _insertSymbol(String symbol) {
    if (_isSubmitting) return;

    final currentText = _answerController.text;

    // Always append the new character.
    // This prevents previous characters from being replaced.
    final actualSymbol = symbol == '−' ? '-' : symbol;

    final newText = currentText + actualSymbol;

    _answerController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: newText.length,
      ),
      composing: TextRange.empty,
    );

    _resetAnswerLabel();

    _answerFocusNode.requestFocus();

    setState(() {});
  }

  void _backspace() {
    if (_isSubmitting) return;

    final currentText = _answerController.text;

    if (currentText.isEmpty) return;

    // Remove only the last character.
    final newText = currentText.substring(
      0,
      currentText.length - 1,
    );

    _answerController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: newText.length,
      ),
      composing: TextRange.empty,
    );

    _resetAnswerLabel();

    _answerFocusNode.requestFocus();

    setState(() {});
  }

  void _clearAnswer() {
    if (_isSubmitting) return;

    _answerController.value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
    );

    _resetAnswerLabel();

    _answerFocusNode.requestFocus();

    setState(() {});
  }

  void _resetAnswerLabel() {
    if (!mounted) return;

    setState(() {
      _isAnswerInvalid = false;
      _answerLabel = 'Enter your answer';
    });
  }

  // ============================================================
  // ANSWER SUBMISSION
  // ============================================================

  Future<void> _submitAnswer() async {
    if (_isSubmitting) return;

    final submittedAnswer = _answerController.text.trim();

    if (submittedAnswer.isEmpty) {
      setState(() {
        _isAnswerInvalid = true;
        _answerLabel =
            'Invalid answer. Please enter the answer in the correct format.';
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSubmitting = true;
      _isAnswerInvalid = false;
      _answerLabel = 'Checking your answer...';
    });

    try {
      final result = await _answerService.submitAnswer(
        questionId: widget.questionId,
        submittedAnswer: submittedAnswer,
      );

      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      switch (result.status) {
        case AnswerSubmissionStatus.invalidFormat:
          setState(() {
            _isAnswerInvalid = true;
            _answerLabel =
                'Invalid answer. Please enter the answer in the correct format.';
          });
          break;

        case AnswerSubmissionStatus.correct:
          setState(() {
            _isAnswerInvalid = false;
            _answerLabel = 'Correct answer!';
          });

          _showCorrectAnswerPopup();
          break;

        case AnswerSubmissionStatus.incorrect:
          setState(() {
            _isAnswerInvalid = false;
            _answerLabel = 'Enter your answer';
          });

          _showWrongAnswerPopup();
          break;

        case AnswerSubmissionStatus.questionNotFound:
        case AnswerSubmissionStatus.notLoggedIn:
        case AnswerSubmissionStatus.error:
          setState(() {
            _isAnswerInvalid = false;
            _answerLabel = 'Enter your answer';
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
        _isSubmitting = false;
        _answerLabel = 'Enter your answer';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Submission failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
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
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
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
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                    ),
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
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                    ),
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
  // ANSWER TYPE INFORMATION
  // ============================================================

  _AnswerTypeInfo _answerTypeInfo(String rawType) {
    final type = rawType
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_-]+'), '');

    switch (type) {
      case 'percentage':
      case 'percent':
        return const _AnswerTypeInfo(
          label: 'Percentage',
          format: 'Number optionally followed by %',
          example: '100%',
        );

      case 'fraction':
        return const _AnswerTypeInfo(
          label: 'Fraction',
          format: 'Numerator/denominator (p/q)',
          example: '3/4',
        );

      case 'mixedfraction':
      case 'mixednumber':
        return const _AnswerTypeInfo(
          label: 'Mixed Fraction',
          format: 'Whole number followed by a fraction',
          example: '5 1/2',
        );

      case 'radio':
      case 'ratio':
        return const _AnswerTypeInfo(
          label: 'Ratio',
          format: 'Two values separated by a colon (a:b)',
          example: '5:17',
        );

      case 'exponent':
      case 'exponential':
        return const _AnswerTypeInfo(
          label: 'Exponent',
          format: 'Base^exponent',
          example: '2^3',
        );

      case 'integer':
        return const _AnswerTypeInfo(
          label: 'Integer',
          format: 'Whole number, positive or negative',
          example: '-5',
        );

      case 'decimal':
        return const _AnswerTypeInfo(
          label: 'Decimal',
          format: 'A number using decimal notation',
          example: '5.17',
        );

      default:
        return _AnswerTypeInfo(
          label: rawType.trim().isEmpty
              ? 'Not specified'
              : rawType.trim(),
          format: 'Follow the format specified in the question',
          example: 'Example not available',
        );
    }
  }

  void _showAnswerTypeInfo(String rawType) {
    final info = _answerTypeInfo(rawType);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9DAE2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),

                const SizedBox(height: 22),

                const Text(
                  'Answer Type Guide',
                  style: TextStyle(
                    color: _text,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 18),

                _infoRow('Type', info.label),

                const SizedBox(height: 12),

                _infoRow('Expected Format', info.format),

                const SizedBox(height: 12),

                _infoRow(
                  'Example',
                  info.example,
                  emphasize: true,
                ),

                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: const Text('Got it'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _infoRow(
    String label,
    String value, {
    bool emphasize = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE8E9F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            value,
            style: TextStyle(
              color: emphasize ? _primary : _text,
              fontSize: emphasize ? 17 : 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MAIN SCREEN
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: _text,
          ),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Question Details',
          style: TextStyle(
            color: _text,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: Color(0xFFE7E8EE),
          ),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _questionReference.snapshots(),
          builder: (context, questionSnapshot) {
            if (questionSnapshot.hasError) {
              return _messageState(
                icon: Icons.cloud_off_rounded,
                title: 'Could Not Load Question',
                message: 'Please check your connection and try again.',
              );
            }

            if (questionSnapshot.connectionState ==
                    ConnectionState.waiting &&
                !questionSnapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                  color: _primary,
                ),
              );
            }

            final document = questionSnapshot.data;

            if (document == null || !document.exists) {
              return _messageState(
                icon: Icons.search_off_rounded,
                title: 'Question Not Found',
                message: 'This question may have been removed.',
              );
            }

            final data = document.data() ?? <String, dynamic>{};

            final questionNo =
                data['questionNo'] ?? widget.questionNo ?? '?';

            final title =
                (data['title'] ?? widget.title ?? 'Question').toString();

            final questionText =
                (data['question'] ?? widget.question ?? '').toString();

            final topic =
                (data['topic'] ?? widget.topic ?? 'General').toString();

            final difficulty =
                (data['difficulty'] ?? widget.difficulty ?? '').toString();

            final answerType =
                (data['answerType'] ?? widget.answerType ?? '').toString();

            return StreamBuilder<
                DocumentSnapshot<Map<String, dynamic>>>(
              stream: _solvedReference?.snapshots(),
              builder: (context, solvedSnapshot) {
                final isSolved =
                    solvedSnapshot.hasData && solvedSnapshot.data!.exists;

                final isStatusLoading = _user != null &&
                    solvedSnapshot.connectionState ==
                        ConnectionState.waiting &&
                    !solvedSnapshot.hasData;

                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStatusAndType(
                        isSolved: isSolved,
                        isStatusLoading: isStatusLoading,
                        answerType: answerType,
                      ),

                      const SizedBox(height: 18),

                      _buildQuestionCard(
                        questionNo: questionNo.toString(),
                        title: title,
                        questionText: questionText,
                        topic: topic,
                        difficulty: difficulty,
                      ),

                      const SizedBox(height: 20),

                      _buildAnswerInput(),

                      const SizedBox(height: 16),

                      _buildCustomKeyboard(),
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

  // ============================================================
  // SOLVED STATUS AND ANSWER TYPE
  // ============================================================

  Widget _buildStatusAndType({
    required bool isSolved,
    required bool isStatusLoading,
    required String answerType,
  }) {
    final statusColor =
        isSolved ? const Color(0xFF15803D) : const Color(0xFFDC2626);

    final statusBackground =
        isSolved ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: isStatusLoading
                ? const Color(0xFFF0F1F5)
                : statusBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSolved
                    ? Icons.check_circle_rounded
                    : Icons.circle_rounded,
                color: isStatusLoading ? _muted : statusColor,
                size: 15,
              ),

              const SizedBox(width: 6),

              Text(
                isStatusLoading
                    ? 'Checking...'
                    : isSolved
                        ? 'Solved'
                        : 'Unsolved',
                style: TextStyle(
                  color: isStatusLoading ? _muted : statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),

        const Spacer(),

        Flexible(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showAnswerTypeInfo(answerType),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFE3E4EA),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'Type: ${_answerTypeInfo(answerType).label}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                  const SizedBox(width: 5),

                  const Icon(
                    Icons.info_outline_rounded,
                    color: _primary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // QUESTION CARD
  // ============================================================

  Widget _buildQuestionCard({
    required String questionNo,
    required String title,
    required String questionText,
    required String topic,
    required String difficulty,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEBFF),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  'Q$questionNo',
                  style: const TextStyle(
                    color: _primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              const Spacer(),

              if (difficulty.trim().isNotEmpty)
                _smallBadge(
                  difficulty,
                  _difficultyColor(difficulty),
                ),
            ],
          ),

          const SizedBox(height: 17),

          Text(
            title,
            style: const TextStyle(
              color: _text,
              fontSize: 19,
              height: 1.3,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 12),

          SelectableText(
            questionText,
            style: const TextStyle(
              color: Color(0xFF444754),
              fontSize: 16,
              height: 1.65,
            ),
          ),

          if (topic.trim().isNotEmpty) ...[
            const SizedBox(height: 18),

            Row(
              children: [
                const Icon(
                  Icons.category_outlined,
                  color: _muted,
                  size: 16,
                ),

                const SizedBox(width: 6),

                Expanded(
                  child: Text(
                    topic,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _difficultyColor(String difficulty) {
    switch (difficulty.trim().toLowerCase()) {
      case 'easy':
        return const Color(0xFF15803D);

      case 'medium':
        return const Color(0xFFB45309);

      case 'hard':
        return const Color(0xFFDC2626);

      default:
        return _primary;
    }
  }

  Widget _smallBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // ============================================================
  // ANSWER INPUT
  // ============================================================

  Widget _buildAnswerInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            _answerLabel,
            style: TextStyle(
              color: _isAnswerInvalid
                  ? _error
                  : _isSubmitting
                      ? _primary
                      : _muted,
              fontSize: 13,
              fontWeight: _isAnswerInvalid
                  ? FontWeight.w700
                  : FontWeight.w600,
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
                  ? _error
                  : const Color(0xFFDADCE5),
              width: _isAnswerInvalid ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.edit_outlined,
                color: _isAnswerInvalid ? _error : _muted,
                size: 21,
              ),

              const SizedBox(width: 10),

              Expanded(
                child: TextField(
                  controller: _answerController,
                  focusNode: _answerFocusNode,
                  readOnly: true,
                  showCursor: true,

                  // Prevent automatic text selection.
                  enableInteractiveSelection: false,

                  onTap: () {
                    _answerController.selection =
                        TextSelection.collapsed(
                      offset: _answerController.text.length,
                    );

                    _answerFocusNode.requestFocus();
                  },

                  decoration: const InputDecoration(
                    hintText: 'Enter your answer...',
                    hintStyle: TextStyle(
                      color: Color(0xFF9A9DA8),
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),

                  style: const TextStyle(
                    color: _text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              if (_answerController.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear answer',
                  onPressed: _isSubmitting ? null : _clearAnswer,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: _muted,
                    size: 19,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CUSTOM KEYBOARD
  // ============================================================

  Widget _buildCustomKeyboard() {
    const numberRows = <List<String>>[
      ['1', '2', '3', '4', '5'],
      ['6', '7', '8', '9', '0'],
    ];

    const symbolKeys = [
      '.',
      '−',
      '/',
      '%',
      ':',
      '^',
      '√',
    ];

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
                      child: _keyboardKey(
                        label: key,
                        onTap: () => _insertSymbol(key),
                      ),
                    ),
                  ),
              ],
            ),

          Row(
            children: [
              for (final key in symbolKeys)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: _keyboardKey(
                      label: key,
                      compact: true,
                      onTap: () => _insertSymbol(key),
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
                            width: 16,
                            height: 16,
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
                      _isSubmitting ? 'CHECKING...' : 'SUBMIT',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF9CA3AF),
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
                child: _keyboardKey(
                  label: 'Backspace',
                  icon: Icons.backspace_outlined,
                  onTap: _backspace,
                  isUtility: true,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            _isSubmitting
                ? 'Checking your answer. Please wait...'
                : 'Enter your answer using the keyboard above.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyboardKey({
    required String label,
    required VoidCallback onTap,
    IconData? icon,
    bool compact = false,
    bool isUtility = false,
  }) {
    return Material(
      color: isUtility
          ? const Color(0xFFEDEBFF)
          : const Color(0xFFF7F8FC),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: _isSubmitting ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: compact ? 47 : 50,
          child: Center(
            child: icon == null
                ? Text(
                    label,
                    style: TextStyle(
                      color: isUtility ? _primary : _text,
                      fontSize: compact ? 16 : 19,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 17,
                        color: _primary,
                      ),

                      const SizedBox(width: 5),

                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ERROR / EMPTY STATES
  // ============================================================

  Widget _messageState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: const Color(0xFF9A9DA8),
            ),

            const SizedBox(height: 14),

            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _text,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _muted,
                fontSize: 14,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 18),

            OutlinedButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerTypeInfo {
  final String label;
  final String format;
  final String example;

  const _AnswerTypeInfo({
    required this.label,
    required this.format,
    required this.example,
  });
}