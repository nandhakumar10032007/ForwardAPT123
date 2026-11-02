import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../screens/question_detailed_view_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController =
      TextEditingController();

  String _selectedDifficulty = 'All';
  String _selectedTopic = 'All';

  String _userName = 'Username';
  int _streak = 0;

  List<Map<String, dynamic>> _questions = [];

  bool _isLoadingQuestions = true;
  String? _questionLoadError;

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userStream;

  @override
  void initState() {
    super.initState();

    _listenToUser();
    _loadRandomUnsolvedQuestions();
  }

  // ============================================================
  // USER DETAILS
  // ============================================================

  void _listenToUser() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    _userStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots();

    _userStream!.listen((snapshot) {
      if (!mounted || !snapshot.exists) return;

      final data = snapshot.data();

      final name = data?['userName']?.toString().trim();

      final streakValue = data?['streak'];

      int streak = 0;

      if (streakValue is int) {
        streak = streakValue;
      } else if (streakValue is num) {
        streak = streakValue.toInt();
      } else {
        streak = int.tryParse(
              streakValue?.toString() ?? '',
            ) ??
            0;
      }

      setState(() {
        _userName =
            name != null && name.isNotEmpty ? name : 'Username';

        _streak = streak;
      });
    });
  }

  // ============================================================
  // LOAD RANDOM UNSOLVED QUESTIONS
  // ============================================================

  Future<void> _loadRandomUnsolvedQuestions() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() {
        _isLoadingQuestions = false;
        _questionLoadError =
            'Please log in to view questions.';
        _questions = [];
      });
      return;
    }

    setState(() {
      _isLoadingQuestions = true;
      _questionLoadError = null;
    });

    try {
      final firestore = FirebaseFirestore.instance;

      // Fetch questions and this user's solved-question records.
      final results = await Future.wait([
        firestore.collection('commonQuestions').get(),
        firestore
            .collection('users')
            .doc(user.uid)
            .collection('solvedQuestions')
            .get(),
      ]);

      final questionSnapshot =
          results[0] as QuerySnapshot<Map<String, dynamic>>;

      final solvedSnapshot =
          results[1] as QuerySnapshot<Map<String, dynamic>>;

      // The solved record document ID should match the question
      // document ID, for example: question_1.
      final Set<String> solvedQuestionIds = solvedSnapshot.docs
          .map((doc) => doc.id)
          .toSet();

      // Keep only questions that this user has not solved.
      final unsolvedDocuments = questionSnapshot.docs.where((doc) {
        return !solvedQuestionIds.contains(doc.id);
      }).toList();

      // Randomize the remaining questions.
      unsolvedDocuments.shuffle(Random());

      // Choose up to 10 random questions.
      final selectedDocuments = unsolvedDocuments.take(10).toList();

      final List<Map<String, dynamic>> loadedQuestions =
          selectedDocuments.map((doc) {
        final data = doc.data();

        return <String, dynamic>{
          'documentId': doc.id,
          'number': data['questionNo'] ?? '',
          'title': data['title'] ?? 'Untitled Question',
          'description': data['question'] ?? '',
          'topic': data['topic'] ?? 'General',
          'difficulty': data['difficulty'] ?? 'Easy',
          'answerType': data['answerType'] ?? '',
        };
      }).toList();

      if (!mounted) return;

      setState(() {
        _questions = loadedQuestions;
        _isLoadingQuestions = false;
        _questionLoadError = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoadingQuestions = false;
        _questionLoadError =
            'Could not load questions. Please try again.';
      });

      debugPrint('Error loading questions: $error');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // FILTER QUESTIONS
  // ============================================================

  List<Map<String, dynamic>> get _filteredQuestions {
    final search = _searchController.text.trim().toLowerCase();

    return _questions.where((question) {
      final title =
          (question['title'] ?? '').toString().toLowerCase();

      final description =
          (question['description'] ?? '').toString().toLowerCase();

      final topic =
          (question['topic'] ?? '').toString().toLowerCase();

      final number = (question['number'] ?? '').toString();

      final matchesSearch = search.isEmpty ||
          title.contains(search) ||
          description.contains(search) ||
          topic.contains(search) ||
          number.contains(search);

      final matchesDifficulty =
          _selectedDifficulty == 'All' ||
              question['difficulty'] == _selectedDifficulty;

      final matchesTopic =
          _selectedTopic == 'All' ||
              question['topic'] == _selectedTopic;

      return matchesSearch && matchesDifficulty && matchesTopic;
    }).toList();
  }

  List<String> get _availableTopics {
    final topics = _questions
        .map((question) => question['topic'].toString())
        .toSet()
        .toList()
      ..sort();

    return ['All', ...topics];
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildGreeting()),
            SliverToBoxAdapter(child: _buildSearchBar()),
            SliverToBoxAdapter(child: _buildQuestionsTitle()),
            _buildQuestionList(),
            const SliverToBoxAdapter(
              child: SizedBox(height: 30),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Color(0xFFE7E8EE),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                'F',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'ForwardAPT',
              style: TextStyle(
                color: Color(0xFF171923),
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          GestureDetector(
            onTap: _showStreakDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5E8),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  const Text('🔥'),
                  const SizedBox(width: 5),
                  Text(
                    '$_streak',
                    style: const TextStyle(
                      color: Color(0xFFB45309),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _showProfileMenu,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFF0EEFF),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFDCD8FF),
                ),
              ),
              child: const Icon(
                Icons.person_rounded,
                color: Color(0xFF4F46E5),
                size: 25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // GREETING
  // ============================================================

  Widget _buildGreeting() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hello, $_userName 👋',
            style: const TextStyle(
              color: Color(0xFF171923),
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ready to sharpen your aptitude skills today?',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SEARCH BAR AND FILTER BUTTON
  // ============================================================

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: const Color(0xFFE0E1E7),
                ),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search questions...',
                  hintStyle: const TextStyle(
                    color: Color(0xFF9A9DA8),
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF777A87),
                    size: 27,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 19,
                          ),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 17,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _showFilterSheet,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.tune_rounded,
                color: Colors.white,
                size: 25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // QUESTIONS TITLE
  // ============================================================

  Widget _buildQuestionsTitle() {
    final hasFilter =
        _selectedDifficulty != 'All' || _selectedTopic != 'All';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 20, 14),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Questions',
              style: TextStyle(
                color: Color(0xFF171923),
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (!_isLoadingQuestions && _questionLoadError == null)
            Text(
              '${_filteredQuestions.length} shown',
              style: const TextStyle(
                color: Color(0xFF858894),
                fontSize: 12,
              ),
            ),
          if (hasFilter)
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedDifficulty = 'All';
                  _selectedTopic = 'All';
                });
              },
              child: const Text('Clear filters'),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // QUESTION LIST
  // ============================================================

  Widget _buildQuestionList() {
    if (_isLoadingQuestions) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(45),
          child: Center(
            child: CircularProgressIndicator(
              color: Color(0xFF4F46E5),
            ),
          ),
        ),
      );
    }

    if (_questionLoadError != null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 44,
                  color: Color(0xFF858894),
                ),
                const SizedBox(height: 12),
                Text(
                  _questionLoadError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF353743),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: _loadRandomUnsolvedQuestions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final questions = _filteredQuestions;

    if (questions.isEmpty) {
      return SliverToBoxAdapter(
        child: _buildEmptyState(),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _buildQuestionCard(questions[index]),
            );
          },
          childCount: questions.length,
        ),
      ),
    );
  }

  // ============================================================
  // QUESTION CARD
  // ============================================================

 Widget _buildQuestionCard(Map<String, dynamic> question) {
  final difficulty = question['difficulty'].toString();

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

  return GestureDetector(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => QuestionDetailedViewScreen(
            questionId: question['documentId'].toString(),
            questionNo: int.tryParse(
                  question['number'].toString(),
                ) ??
                0,
            title: question['title'].toString(),
            question: question['description'].toString(),
            topic: question['topic'].toString(),
            difficulty: question['difficulty'].toString(),
            answerType: question['answerType'].toString(),
          ),
        ),
      );
    },
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE5E6EB),
        ),
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
                  color: const Color(0xFFEDEBFF),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  'Q${question['number']}',
                  style: const TextStyle(
                    color: Color(0xFF4F46E5),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: difficultyBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  difficulty,
                  style: TextStyle(
                    color: difficultyColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Text(
            question['title'].toString(),
            style: const TextStyle(
              color: Color(0xFF171923),
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
              color: Color(0xFF777A87),
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
                    color: Color(0xFF777A87),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const Text(
                'Solve',
                style: TextStyle(
                  color: Color(0xFF4F46E5),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(width: 6),

              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: Color(0xFF4F46E5),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

  // ============================================================
  // EMPTY STATE
  // ============================================================

  Widget _buildEmptyState() {
    final message = _questions.isEmpty
        ? 'You have no unsolved questions available right now.'
        : 'Try another search or change your filters.';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 40,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFE5E6EB),
          ),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Color(0xFFB0B3BE),
            ),
            const SizedBox(height: 14),
            const Text(
              'No questions found',
              style: TextStyle(
                color: Color(0xFF252733),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF858894),
                fontSize: 13,
              ),
            ),
            if (_questions.isEmpty) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _loadRandomUnsolvedQuestions,
                child: const Text('Load Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // FILTER SHEET
  // ============================================================

  void _showFilterSheet() {
    String tempDifficulty = _selectedDifficulty;
    String tempTopic = _selectedTopic;

    final topics = _availableTopics;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(context).viewInsets.bottom + 25,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filter Questions',
                      style: TextStyle(
                        color: Color(0xFF171923),
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Difficulty',
                      style: TextStyle(
                        color: Color(0xFF353743),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['All', 'Easy', 'Medium', 'Hard']
                          .map(
                            (difficulty) => _filterChip(
                              label: difficulty,
                              selected:
                                  tempDifficulty == difficulty,
                              onTap: () {
                                setSheetState(() {
                                  tempDifficulty = difficulty;
                                });
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Topic',
                      style: TextStyle(
                        color: Color(0xFF353743),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F8FC),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: const Color(0xFFE3E4EA),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: topics.contains(tempTopic)
                              ? tempTopic
                              : 'All',
                          isExpanded: true,
                          items: topics.map((topic) {
                            return DropdownMenuItem<String>(
                              value: topic,
                              child: Text(
                                topic == 'All' ? 'All Topics' : topic,
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setSheetState(() {
                                tempTopic = value;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _selectedDifficulty = tempDifficulty;
                            _selectedTopic = tempTopic;
                          });

                          Navigator.pop(sheetContext);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Apply Filters',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // FILTER CHIP
  // ============================================================

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF4F46E5)
              : const Color(0xFFF4F4F7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : const Color(0xFF656875),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SMALL TAG
  // ============================================================

  Widget _smallTag(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: const Color(0xFF777A87),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF666975),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STREAK DIALOG
  // ============================================================

  void _showStreakDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Text(
                '🔥',
                style: TextStyle(fontSize: 25),
              ),
              const SizedBox(width: 8),
              Text(
                '$_streak Day Streak',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          content: Text(
            _streak == 0
                ? 'Start solving questions today to build your streak! Keep moving forward 🚀'
                : 'You have solved questions for $_streak days in a row. Keep your streak alive!',
            style: const TextStyle(
              color: Color(0xFF686B77),
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Keep Going',
                style: TextStyle(
                  color: Color(0xFF4F46E5),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // PROFILE MENU
  // ============================================================

  void _showProfileMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(26),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 34,
                  backgroundColor: Color(0xFFEDEBFF),
                  child: Icon(
                    Icons.person_rounded,
                    size: 36,
                    color: Color(0xFF4F46E5),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _userName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF171923),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Keep learning and moving forward 🚀',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF777A87),
                  ),
                ),
                const SizedBox(height: 20),
                _profileOption(
                  sheetContext,
                  Icons.person_outline_rounded,
                  'View Profile',
                ),
                _profileOption(
                  sheetContext,
                  Icons.settings_outlined,
                  'Settings',
                ),
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: Colors.red,
                  ),
                  title: const Text('Log Out'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await FirebaseAuth.instance.signOut();

                    if (!mounted) return;

                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/login',
                      (route) => false,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // PROFILE OPTION
  // ============================================================

  Widget _profileOption(
    BuildContext sheetContext,
    IconData icon,
    String title,
  ) {
    return ListTile(
      onTap: () {
        Navigator.pop(sheetContext);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title will be connected next 🚀'),
          ),
        );
      },
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFF0EFFF),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(
          icon,
          color: const Color(0xFF4F46E5),
          size: 21,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF292B35),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF9A9DA8),
      ),
    );
  }
}