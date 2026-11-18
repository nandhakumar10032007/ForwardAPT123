import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ContestQuestionsScreen extends StatefulWidget {
  final String contestId;
  final VoidCallback onExit;
  final ValueChanged<String> onQuestionSelected;

  /// True when this screen is opened from a previous contest for practice.
  /// Practice mode reads historical progress but never writes to Firestore.
  final bool isPracticeMode;

  const ContestQuestionsScreen({
    super.key,
    required this.contestId,
    required this.onExit,
    required this.onQuestionSelected,
    this.isPracticeMode = false,
  });

  @override
  State<ContestQuestionsScreen> createState() =>
      _ContestQuestionsScreenState();
}

class _ContestQuestionsScreenState extends State<ContestQuestionsScreen> {
  static const Color _primary = Color(0xFF4F46E5);
  static const Color _background = Color(0xFFF7F8FC);
  static const Color _text = Color(0xFF171923);
  static const Color _muted = Color(0xFF777A87);

  final TextEditingController _searchController = TextEditingController();

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _questionsStream;
  String? _progressCacheKey;
  Future<Map<String, Map<String, dynamic>>>? _progressFuture;

  @override
  void initState() {
    super.initState();

    _questionsStream = FirebaseFirestore.instance
        .collection('Contest_Questions')
        .doc(widget.contestId)
        .collection('Questions')
        .snapshots();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _difficultyFromId(String id, Map<String, dynamic> data) {
    final stored = (data['difficulty'] ?? '').toString().trim();
    if (stored.isNotEmpty) return stored;

    switch (id.toUpperCase().isNotEmpty ? id[0].toUpperCase() : '') {
      case 'E':
        return 'Easy';
      case 'M':
        return 'Medium';
      case 'H':
        return 'Hard';
      default:
        return 'Easy';
    }
  }

  int _difficultyOrder(String difficulty) {
    switch (difficulty) {
      case 'Easy':
        return 0;
      case 'Medium':
        return 1;
      case 'Hard':
        return 2;
      default:
        return 3;
    }
  }

  Future<Map<String, Map<String, dynamic>>> _getProgressFuture(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> questions,
  ) {
    final key = questions.map((question) => question.id).join('|');
    if (_progressFuture == null || _progressCacheKey != key) {
      _progressCacheKey = key;
      _progressFuture = _loadProgress(questions);
    }
    return _progressFuture!;
  }

  Future<Map<String, Map<String, dynamic>>> _loadProgress(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> questions,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};

    final registeredDocument = FirebaseFirestore.instance
        .collection('Contest_Questions')
        .doc(widget.contestId)
        .collection('Registered')
        .doc(user.uid);

    // In practice mode, first check whether this user originally attended.
    // A non-attendee must not try to read another user's or a missing
    // registration's Result subcollection; their displayed progress is zero.
    if (widget.isPracticeMode) {
      final registrationSnapshot = await registeredDocument.get();
      if (!registrationSnapshot.exists) {
        return {};
      }
    }

    final resultCollection = registeredDocument.collection('Result');

    final snapshots = await Future.wait(
      questions.map((question) => resultCollection.doc(question.id).get()),
    );

    final progress = <String, Map<String, dynamic>>{};
    for (var i = 0; i < questions.length; i++) {
      final snapshot = snapshots[i];
      if (snapshot.exists) {
        progress[questions[i].id] = snapshot.data() ?? {};
      }
    }
    return progress;
  }

  List<Map<String, dynamic>> _prepareQuestions(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
    Map<String, Map<String, dynamic>> progress,
  ) {
    final questions = documents.map((document) {
      final data = document.data();
      final status = (progress[document.id]?['Status'] ?? 'Unsolved')
          .toString();
      final penaltyValue = progress[document.id]?['Penalty_Count'];
      final penalty = penaltyValue is num
          ? penaltyValue.toInt()
          : int.tryParse(penaltyValue?.toString() ?? '') ?? 0;

      return <String, dynamic>{
        'documentId': document.id,
        'number': document.id,
        'title': data['title'] ?? 'Untitled Question',
        'description': data['question'] ?? '',
        'topic': data['topic'] ?? 'General',
        'difficulty': _difficultyFromId(document.id, data),
        'answerType': data['answerType'] ?? '',
        'status': status,
        'penalty': penalty < 0 ? 0 : penalty,
      };
    }).toList();

    questions.sort((a, b) {
      final difficultyComparison = _difficultyOrder(
        a['difficulty'].toString(),
      ).compareTo(_difficultyOrder(b['difficulty'].toString()));

      if (difficultyComparison != 0) return difficultyComparison;
      return a['documentId'].toString().compareTo(
            b['documentId'].toString(),
          );
    });

    return questions;
  }

  List<Map<String, dynamic>> _searchQuestions(
    List<Map<String, dynamic>> questions,
  ) {
    final search = _searchController.text.trim().toLowerCase();
    if (search.isEmpty) return questions;

    return questions.where((question) {
      final title = question['title'].toString().toLowerCase();
      final description = question['description'].toString().toLowerCase();
      final topic = question['topic'].toString().toLowerCase();
      final number = question['number'].toString().toLowerCase();

      return title.contains(search) ||
          description.contains(search) ||
          topic.contains(search) ||
          number.contains(search);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _background,
      child: SafeArea(
        bottom: false,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _questionsStream,
          builder: (context, questionSnapshot) {
            if (questionSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _primary),
              );
            }

            if (questionSnapshot.hasError) {
              return _buildErrorState(
                'Could not load contest questions. Please try again.',
              );
            }

            final documents = questionSnapshot.data?.docs ?? [];

            if (FirebaseAuth.instance.currentUser == null) {
              return _buildErrorState('Please log in to view contest questions.');
            }

            return FutureBuilder<Map<String, Map<String, dynamic>>>(
              future: _getProgressFuture(documents),
              builder: (context, progressSnapshot) {
                if (progressSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: _primary),
                  );
                }

                if (progressSnapshot.hasError) {
                  return _buildErrorState(
                    'Could not load your contest progress. Please try again.',
                  );
                }

                final allQuestions = _prepareQuestions(
                  documents,
                  progressSnapshot.data ?? {},
                );
                final questions = _searchQuestions(allQuestions);

                return CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    SliverToBoxAdapter(child: _buildIntro(allQuestions)),
                    SliverToBoxAdapter(child: _buildSearchBar()),
                    SliverToBoxAdapter(
                      child: _buildQuestionsTitle(questions.length),
                    ),
                    _buildQuestionList(questions),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 28),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE7E8EE)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: _primary,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Center(
              child: Text(
                'F',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Contest Questions',
              style: TextStyle(
                color: _text,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEDEBFF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.contestId,
              style: const TextStyle(
                color: _primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Exit contest',
            onPressed: widget.onExit,
            icon: const Icon(
              Icons.exit_to_app_rounded,
              color: _primary,
              size: 25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntro(List<Map<String, dynamic>> questions) {
    final solved = questions
        .where((question) => question['status'] == 'Solved')
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 25, 20, 19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ready for the challenge? 🚀',
            style: TextStyle(
              color: _text,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          if (widget.isPracticeMode) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFEDEBFF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'PRACTICE MODE',
                style: TextStyle(
                  color: _primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 9),
          ],
          Text(
            widget.isPracticeMode
                ? 'Practice with these previous contest questions. Your original contest record will not change.'
                : 'Explore the questions and track your contest progress.',
            style: const TextStyle(
              color: _muted,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 17),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E6EB)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDEBFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.task_alt_rounded,
                    color: _primary,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Questions solved',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '$solved / ${questions.length}',
                  style: const TextStyle(
                    color: _text,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFE0E1E7)),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search contest questions...',
            hintStyle: const TextStyle(
              color: Color(0xFF9A9DA8),
              fontSize: 13,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: _muted,
              size: 26,
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded, size: 19),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 17),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionsTitle(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 27, 20, 14),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Questions',
              style: TextStyle(
                color: _text,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '$count shown',
            style: const TextStyle(
              color: Color(0xFF858894),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionList(List<Map<String, dynamic>> questions) {
    if (questions.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 38),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E6EB)),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 46,
                  color: Color(0xFFB0B3BE),
                ),
                SizedBox(height: 13),
                Text(
                  'No questions found',
                  style: TextStyle(
                    color: Color(0xFF252733),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Try another search or change your filters.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF858894),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                widget.onQuestionSelected(
                  questions[index]['documentId'].toString(),
                );
              },
              child: _buildQuestionCard(questions[index]),
            ),
          ),
          childCount: questions.length,
        ),
      ),
    );
  }

  Widget _buildQuestionCard(Map<String, dynamic> question) {
    final id = question['documentId'].toString();
    final difficulty = question['difficulty'].toString();
    final isSolved = question['status'] == 'Solved';
    final penalty = question['penalty'] as int;

    Color difficultyColor;
    Color difficultyBackground;

    switch (difficulty) {
      case 'Easy':
        difficultyColor = const Color(0xFF15803D);
        difficultyBackground = const Color(0xFFDCFCE7);
        break;
      case 'Medium':
        difficultyColor = const Color(0xFFB45309);
        difficultyBackground = const Color(0xFFFFF4C7);
        break;
      default:
        difficultyColor = const Color(0xFFDC2626);
        difficultyBackground = const Color(0xFFFEE2E2);
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E6EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 3),
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
                  color: difficultyBackground,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  id,
                  style: TextStyle(
                    color: difficultyColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (isSolved)
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF16A34A),
                      size: 15,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Solved',
                      style: TextStyle(
                        color: Color(0xFF15803D),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              const Spacer(),
              if (penalty > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFDC2626),
                      size: 15,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Penalty $penalty',
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            question['title'].toString(),
            style: const TextStyle(
              color: _text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            question['description'].toString(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _muted,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              const Icon(
                Icons.category_outlined,
                size: 16,
                color: Color(0xFF858894),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  question['topic'].toString(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                isSolved ? 'Completed' : 'Contest question',
                style: TextStyle(
                  color: isSolved ? const Color(0xFF15803D) : _primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                isSolved ? Icons.check_rounded : Icons.flag_outlined,
                size: 15,
                color: isSolved ? const Color(0xFF15803D) : _primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 45,
              color: Color(0xFF858894),
            ),
            const SizedBox(height: 13),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _muted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
