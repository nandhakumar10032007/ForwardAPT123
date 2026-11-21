import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum DailyAnswerStatus {
  invalidFormat,
  correct,
  incorrect,
  alreadySolved,
  questionNotFound,
  notLoggedIn,
  futureQuestion,
  error,
}

class DailyAnswerResult {
  final DailyAnswerStatus status;
  final String message;
  final bool streakUpdated;

  const DailyAnswerResult({
    required this.status,
    required this.message,
    this.streakUpdated = false,
  });
}

class DailyQuestionSubmissionService {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const double _epsilon = 0.0000001;

  // ============================================================
  // DAILY QUESTIONS PAGE-OPEN STREAK SYNCHRONIZATION
  // ============================================================

  /// Call this when the Daily Questions page opens.
  ///
  /// This synchronizes only Daily Questions streak data:
  /// - users/{uid}.currentStreak
  /// - users/{uid}.lastSolvedDate (read only)
  /// - users/{uid}/DailyQuestionSolved status values
  ///
  /// It does not read or modify Common Questions streak fields such as
  /// `streak`, `lastActiveDate`, or `problemSolvedCount`.
  ///
  /// If the last on-time solve was before yesterday, the Daily Questions
  /// streak has expired. All current_streak records become broken_streak
  /// and currentStreak is reset to 0.
  Future<void> syncStreakOnDailyQuestionsOpen() async {
    final user = _auth.currentUser;

    if (user == null) return;

    await _syncExpiredStreakForUser(user.uid);
  }

  Future<void> _syncExpiredStreakForUser(String uid) async {
    final userRef = _firestore.collection('users').doc(uid);

    // Read the user's streak information first.
    final userSnapshot = await userRef.get();

    if (!userSnapshot.exists) return;

    final userData = userSnapshot.data() ?? <String, dynamic>{};
    final int currentStreak =
        (userData['currentStreak'] as num?)?.toInt() ?? 0;
    final String lastSolvedDate =
        (userData['lastSolvedDate'] ?? '').toString();

    if (currentStreak <= 0 || lastSolvedDate.isEmpty) return;

    final DateTime istNow = _nowInIst();
    final DateTime todayDate =
        DateTime.utc(istNow.year, istNow.month, istNow.day);
    final DateTime? parsedLastDate = DateTime.tryParse(lastSolvedDate);
    final DateTime? lastDate = parsedLastDate == null
        ? null
        : DateTime.utc(
            parsedLastDate.year,
            parsedLastDate.month,
            parsedLastDate.day,
          );

    // A streak is still alive if the user solved yesterday or today.
    // It expires only when at least one full day was missed.
    final bool streakExpired = lastDate == null ||
        todayDate.difference(lastDate).inDays > 1;

    if (!streakExpired) return;

    final solvedCollection =
        userRef.collection('DailyQuestionSolved');

    final activeRecords = await solvedCollection
        .where('status', isEqualTo: 'current_streak')
        .get();

    // Firestore batches support at most 500 writes. Use smaller batches
    // so this remains safe even for a long-running streak.
    for (int start = 0; start < activeRecords.docs.length; start += 450) {
      final batch = _firestore.batch();
      final end = (start + 450 < activeRecords.docs.length)
          ? start + 450
          : activeRecords.docs.length;

      for (int i = start; i < end; i++) {
        batch.update(activeRecords.docs[i].reference, {
          'status': 'broken_streak',
        });
      }

      await batch.commit();
    }

    // Update the user document last. If an earlier batch fails, the
    // next login can safely retry; already-updated records are not queried.
    await userRef.set({
      'currentStreak': 0,
    }, SetOptions(merge: true));
  }

  // ============================================================
  // MAIN SUBMISSION FUNCTION
  // ============================================================

  Future<DailyAnswerResult> submitAnswer({
    required DateTime questionDate,
    required String submittedAnswer,
  }) async {
    try {
      // 1. Check logged-in user.
      final user = _auth.currentUser;

      if (user == null) {
        return const DailyAnswerResult(
          status: DailyAnswerStatus.notLoggedIn,
          message: 'Please log in first.',
        );
      }

      final answer = submittedAnswer.trim();

      if (answer.isEmpty) {
        return const DailyAnswerResult(
          status: DailyAnswerStatus.invalidFormat,
          message: 'Please enter your answer.',
        );
      }

      // 2. Get current Indian Standard Time.
      final DateTime istNow = _nowInIst();

      final String today = _dateId(istNow);

      final DateTime selectedDate = DateTime(
        questionDate.year,
        questionDate.month,
        questionDate.day,
      );

      final String selectedDateId = _dateId(selectedDate);

      // If today's question is being submitted, first expire any stale
      // streak. Login should already do this, but this is a safe fallback.
      if (selectedDateId == today) {
        await _syncExpiredStreakForUser(user.uid);
      }

      // 3. Never allow future questions.
      if (selectedDateId.compareTo(today) > 0) {
        return const DailyAnswerResult(
          status: DailyAnswerStatus.futureQuestion,
          message: 'Future questions cannot be solved.',
        );
      }

      // 4. Build the Daily Question Firestore reference.
      //
      // dailyQuestions
      //   /2026
      //     /months
      //       /11
      //         /questions
      //           /2026-11-19

      final String year = selectedDate.year.toString();

      final String month =
          selectedDate.month.toString().padLeft(2, '0');

      final questionRef = _firestore
          .collection('dailyQuestions')
          .doc(year)
          .collection('months')
          .doc(month)
          .collection('questions')
          .doc(selectedDateId);

      final questionSnapshot = await questionRef.get();

      if (!questionSnapshot.exists) {
        return const DailyAnswerResult(
          status: DailyAnswerStatus.questionNotFound,
          message: 'Daily question not found.',
        );
      }

      final questionData = questionSnapshot.data()!;

      // 5. Read answer information.
      final String answerType =
          (questionData['answerType'] ?? '')
              .toString()
              .trim()
              .toLowerCase();

      final String correctAnswer =
          (questionData['correctAnswer'] ?? '')
              .toString()
              .trim();

      final String questionNo =
          (questionData['questionNo'] ?? '').toString();

      if (answerType.isEmpty || correctAnswer.isEmpty) {
        return const DailyAnswerResult(
          status: DailyAnswerStatus.error,
          message: 'Question answer information is missing.',
        );
      }

      // 6. Validate answer format.
      if (!isValidFormat(answer, answerType)) {
        return const DailyAnswerResult(
          status: DailyAnswerStatus.invalidFormat,
          message: 'Invalid answer format. Please try again.',
        );
      }

      // 7. Check mathematical correctness.
      final bool isCorrect = isCorrectAnswer(
        answer,
        correctAnswer,
        answerType,
      );

      if (!isCorrect) {
        return const DailyAnswerResult(
          status: DailyAnswerStatus.incorrect,
          message: 'Incorrect answer. Try again!',
        );
      }

      // ========================================================
      // 8. FIRESTORE REFERENCES
      // ========================================================

      final userRef =
          _firestore.collection('users').doc(user.uid);

      // Required collection structure:
      //
      // users/{uid}/DailyQuestionSolved/{questionID}

      final solvedRef = userRef
          .collection('DailyQuestionSolved')
          .doc(questionRef.id);

      // ========================================================
      // 9. FIRESTORE TRANSACTION
      // ========================================================

      final transactionResult =
          await _firestore.runTransaction<Map<String, dynamic>>(
        (transaction) async {
          // Read all required documents before writing.
          final userSnapshot = await transaction.get(userRef);
          final solvedSnapshot = await transaction.get(solvedRef);

          // Prevent duplicate solved records.
          if (solvedSnapshot.exists) {
            return {
              'alreadySolved': true,
              'streakUpdated': false,
            };
          }

          final userData =
              userSnapshot.data() ?? <String, dynamic>{};

          final int oldStreak =
              (userData['currentStreak'] as num?)?.toInt() ?? 0;

          final int oldHighestStreak =
              (userData['highestStreak'] as num?)?.toInt() ?? 0;

          final String lastSolvedDate =
              (userData['lastSolvedDate'] ?? '').toString();

          int newStreak = oldStreak;
          int newHighestStreak = oldHighestStreak;
          bool streakUpdated = false;

          // A retrospective question never changes streak fields.
          final bool isTodayQuestion = selectedDateId == today;

          String solvedStatus = 'previous_question_solved';

          if (isTodayQuestion) {
            solvedStatus = 'current_streak';

            if (lastSolvedDate == today) {
              // Today's streak was already counted.
              newStreak = oldStreak;
            } else if (lastSolvedDate.isNotEmpty &&
                _isYesterday(lastSolvedDate, today)) {
              // The previous day's question was solved on time.
              newStreak = oldStreak + 1;
              streakUpdated = true;
            } else {
              // First streak, or a previous streak has expired.
              newStreak = 1;
              streakUpdated = true;

              // Expired streak records are changed to broken_streak by
              // _syncExpiredStreakForUser() before this transaction starts.
              // Do not run a collection query inside this transaction.
            }

            if (newStreak > newHighestStreak) {
              newHighestStreak = newStreak;
            }

            // set(..., merge: true) also creates the user document
            // if it does not exist yet.
            transaction.set(
              userRef,
              {
                'currentStreak': newStreak,
                'lastSolvedDate': today,
                'highestStreak': newHighestStreak,
              },
              SetOptions(merge: true),
            );
          }

          // Save every correct answer. The status tells the calendar
          // how this solved date should be displayed.
          transaction.set(solvedRef, {
            'date': selectedDateId,
            'solvedAt': FieldValue.serverTimestamp(),
            'questionNo': questionNo,
            'questionID': questionRef.id,
            'status': solvedStatus,
          });

          return {
            'alreadySolved': false,
            'streakUpdated': streakUpdated,
          };
        },
      );

      // ========================================================
      // 13. RETURN RESULT
      // ========================================================

      if (transactionResult['alreadySolved'] == true) {
        return const DailyAnswerResult(
          status: DailyAnswerStatus.alreadySolved,
          message: 'Correct answer! You have already solved this question.',
        );
      }

      return DailyAnswerResult(
        status: DailyAnswerStatus.correct,
        message: 'Correct answer!',
        streakUpdated:
            transactionResult['streakUpdated'] == true,
      );
    } catch (e) {
      return const DailyAnswerResult(
        status: DailyAnswerStatus.error,
        message: 'Something went wrong. Please try again.',
      );
    }
  }

  // ============================================================
  // DATE HELPERS
  // ============================================================

  DateTime _nowInIst() {
    return DateTime.now()
        .toUtc()
        .add(const Duration(hours: 5, minutes: 30));
  }

  String _dateId(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  bool _isYesterday(String previous, String today) {
    final previousDate = DateTime.tryParse(previous);
    final todayDate = DateTime.tryParse(today);

    if (previousDate == null || todayDate == null) {
      return false;
    }

    return todayDate.difference(previousDate).inDays == 1;
  }

  // ============================================================
  // ANSWER FORMAT VALIDATION
  // ============================================================

  bool isValidFormat(String answer, String answerType) {
    final value = answer.trim();
    final type = _normaliseType(answerType);

    switch (type) {
      case 'integer':
        return RegExp(r'^[+-]?\d+$').hasMatch(value);

      case 'decimal':
        return RegExp(
          r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)$',
        ).hasMatch(value);

      case 'percentage':
        return RegExp(
          r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)\s*%?$',
        ).hasMatch(value);

      case 'fraction':
        return _isValidFraction(value);

      case 'mixed fraction':
        return _isValidMixedFraction(value);

      case 'ratio':
        return _isValidRatio(value);

      case 'exponent':
        return _isValidExponent(value);

      default:
        return false;
    }
  }

  String _normaliseType(String type) {
    final value = type.trim().toLowerCase();

    // Your Excel questions may use Radio for ratio answers.
    if (value == 'radio' || value == 'ratio') {
      return 'ratio';
    }

    if (value == 'mixed_fraction') {
      return 'mixed fraction';
    }

    return value;
  }

  // ============================================================
  // FRACTION VALIDATION
  // ============================================================

  bool _isValidFraction(String value) {
    final match = RegExp(
      r'^([+-]?\d+)\s*/\s*(\d+)$',
    ).firstMatch(value);

    if (match == null) return false;

    final denominator = int.tryParse(match.group(2)!);

    return denominator != null && denominator != 0;
  }

  // ============================================================
  // MIXED FRACTION VALIDATION
  // ============================================================

  bool _isValidMixedFraction(String value) {
    final match = RegExp(
      r'^(\d+)\s+(\d+)\s*/\s*(\d+)$',
    ).firstMatch(value);

    if (match == null) return false;

    final numerator = int.tryParse(match.group(2)!);
    final denominator = int.tryParse(match.group(3)!);

    return numerator != null &&
        denominator != null &&
        denominator != 0 &&
        numerator < denominator;
  }

  // ============================================================
  // RATIO VALIDATION
  // ============================================================

  bool _isValidRatio(String value) {
    final match = RegExp(
      r'^(\d+)\s*:\s*(\d+)$',
    ).firstMatch(value);

    if (match == null) return false;

    final first = int.tryParse(match.group(1)!);
    final second = int.tryParse(match.group(2)!);

    return first != null &&
        second != null &&
        (first != 0 || second != 0);
  }

  // ============================================================
  // EXPONENT VALIDATION
  // ============================================================

  bool _isValidExponent(String value) {
    return RegExp(
      r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)\s*\^\s*[+-]?\d+$',
    ).hasMatch(value);
  }

  // ============================================================
  // CORRECT ANSWER COMPARISON
  // ============================================================

  bool isCorrectAnswer(
    String submitted,
    String correct,
    String answerType,
  ) {
    final type = _normaliseType(answerType);

    switch (type) {
      case 'integer':
      case 'decimal':
        return _compareNumbers(submitted, correct);

      case 'percentage':
        return _compareNumbers(
          submitted.replaceAll('%', ''),
          correct.replaceAll('%', ''),
        );

      case 'fraction':
        return _compareFractions(submitted, correct);

      case 'mixed fraction':
        return _compareFractionsOrMixed(submitted, correct);

      case 'ratio':
        return _compareRatios(submitted, correct);

      case 'exponent':
        return _compareExponents(submitted, correct);

      default:
        return false;
    }
  }

  // ============================================================
  // NUMBER COMPARISON
  // ============================================================

  bool _compareNumbers(String a, String b) {
    final first = double.tryParse(a.trim());
    final second = double.tryParse(b.trim());

    if (first == null || second == null) return false;

    return (first - second).abs() < _epsilon;
  }

  // ============================================================
  // FRACTION VALUE
  // ============================================================

  double? _fractionValue(String value) {
    final parts = value.split('/');

    if (parts.length != 2) return null;

    final numerator = double.tryParse(parts[0].trim());
    final denominator = double.tryParse(parts[1].trim());

    if (numerator == null ||
        denominator == null ||
        denominator == 0) {
      return null;
    }

    return numerator / denominator;
  }

  // ============================================================
  // MIXED FRACTION VALUE
  // ============================================================

  double? _mixedFractionValue(String value) {
    final match = RegExp(
      r'^(\d+)\s+(\d+)\s*/\s*(\d+)$',
    ).firstMatch(value.trim());

    if (match == null) return null;

    final whole = double.tryParse(match.group(1)!);
    final numerator = double.tryParse(match.group(2)!);
    final denominator = double.tryParse(match.group(3)!);

    if (whole == null ||
        numerator == null ||
        denominator == null ||
        denominator == 0) {
      return null;
    }

    return whole + numerator / denominator;
  }

  double? _answerAsNumber(String value) {
    final trimmed = value.trim();

    return _fractionValue(trimmed) ??
        _mixedFractionValue(trimmed) ??
        double.tryParse(trimmed);
  }

  bool _compareFractions(String a, String b) {
    final first = _fractionValue(a);
    final second = _fractionValue(b);

    if (first == null || second == null) return false;

    return (first - second).abs() < _epsilon;
  }

  bool _compareFractionsOrMixed(String a, String b) {
    final first = _answerAsNumber(a);
    final second = _answerAsNumber(b);

    if (first == null || second == null) return false;

    return (first - second).abs() < _epsilon;
  }

  // ============================================================
  // RATIO COMPARISON
  // ============================================================

  List<int>? _ratioParts(String value) {
    final match = RegExp(
      r'^(\d+)\s*:\s*(\d+)$',
    ).firstMatch(value.trim());

    if (match == null) return null;

    final first = int.tryParse(match.group(1)!);
    final second = int.tryParse(match.group(2)!);

    if (first == null || second == null) return null;

    return [first, second];
  }

  bool _compareRatios(String a, String b) {
    final first = _ratioParts(a);
    final second = _ratioParts(b);

    if (first == null || second == null) return false;

    return first[0] * second[1] ==
        first[1] * second[0];
  }

  // ============================================================
  // EXPONENT COMPARISON
  // ============================================================

  double? _exponentValue(String value) {
    final parts = value.split('^');

    if (parts.length != 2) return null;

    final base = double.tryParse(parts[0].trim());
    final exponent = int.tryParse(parts[1].trim());

    if (base == null || exponent == null) return null;

    if (base == 0 && exponent < 0) return null;

    return _integerPower(base, exponent);
  }

  double _integerPower(double base, int exponent) {
    if (exponent == 0) return 1;

    double result = 1;

    for (int i = 0; i < exponent.abs(); i++) {
      result *= base;
    }

    return exponent < 0 ? 1 / result : result;
  }

  bool _compareExponents(String a, String b) {
    final first =
        _exponentValue(a) ?? double.tryParse(a.trim());

    final second =
        _exponentValue(b) ?? double.tryParse(b.trim());

    if (first == null || second == null) return false;

    return (first - second).abs() < _epsilon;
  }
}
