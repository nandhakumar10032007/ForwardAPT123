
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;

import '../answer_type.dart';
import 'answer_type_service.dart';

enum ContestSubmissionStatus {
  invalidFormat,
  correct,
  incorrect,
  alreadySolved,
  questionNotFound,
  notRegistered,
  notLoggedIn,
  contestNotStarted,
  contestEnded,
  error,
}

class ContestSubmissionResult {
  final ContestSubmissionStatus status;
  final String message;
  final double awardedMark;
  final double penaltyMark;
  final int penaltyCount;
  final double? finalScore;

  const ContestSubmissionResult({
    required this.status,
    required this.message,
    this.awardedMark = 0,
    this.penaltyMark = 0,
    this.penaltyCount = 0,
    this.finalScore,
  });
}

class ContestSubmitService {
  ContestSubmitService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  // =========================================================
  // MAIN SUBMISSION FUNCTION
  // =========================================================

  Future<ContestSubmissionResult> submitAnswer({
    required String contestId,
    required String questionId,
    required String submittedAnswer,
  }) async {
    try {
      // 1. Authentication check.
      final user = _auth.currentUser;

      if (user == null) {
        return const ContestSubmissionResult(
          status: ContestSubmissionStatus.notLoggedIn,
          message: 'Please log in first.',
        );
      }

      // 2. Empty answer check.
      final answer = submittedAnswer.trim();

      if (answer.isEmpty) {
        return const ContestSubmissionResult(
          status: ContestSubmissionStatus.invalidFormat,
          message: 'Please enter your answer.',
        );
      }

      if (contestId.trim().isEmpty || questionId.trim().isEmpty) {
        return const ContestSubmissionResult(
          status: ContestSubmissionStatus.error,
          message: 'Contest or question information is missing.',
        );
      }

      // 3. Prepare Firestore references.
      final contestRef =
          _firestore.collection('Contest_Questions').doc(contestId);

      final questionRef =
          contestRef.collection('Questions').doc(questionId);

      final registrationRef =
          contestRef.collection('Registered').doc(user.uid);

      final resultRef =
          registrationRef.collection('Result').doc(questionId);

      final summaryRef =
          registrationRef.collection('Result').doc('Summary');

      final profileResultRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('Contest_Result')
          .doc(contestId);

      // 4. Fetch contest and question.
      final contestSnapshot = await contestRef.get();
      final questionSnapshot = await questionRef.get();

      if (!contestSnapshot.exists || !questionSnapshot.exists) {
        return const ContestSubmissionResult(
          status: ContestSubmissionStatus.questionNotFound,
          message: 'Contest or question not found.',
        );
      }

      final contestData = contestSnapshot.data()!;
      final questionData = questionSnapshot.data()!;

      // 5. Check contest timing.
      final startTime = contestData['Start_Time'];
      final endTime = contestData['End_Time'];

      if (startTime is! Timestamp || endTime is! Timestamp) {
        return const ContestSubmissionResult(
          status: ContestSubmissionStatus.error,
          message: 'Contest timing information is invalid.',
        );
      }

      final now = DateTime.now();

      if (now.isBefore(startTime.toDate())) {
        return const ContestSubmissionResult(
          status: ContestSubmissionStatus.contestNotStarted,
          message: 'Contest has not started yet.',
        );
      }

      if (!now.isBefore(endTime.toDate())) {
        return const ContestSubmissionResult(
          status: ContestSubmissionStatus.contestEnded,
          message: 'Contest has ended. Submissions are closed.',
        );
      }

      // 6. Check answer information.
      final answerType = (questionData['answerType'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      final correctAnswer =
          (questionData['correctAnswer'] ?? '').toString().trim();

      final difficulty = (questionData['difficulty'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      if (answerType.isEmpty ||
          correctAnswer.isEmpty ||
          !['easy', 'medium', 'hard'].contains(difficulty)) {
        return const ContestSubmissionResult(
          status: ContestSubmissionStatus.error,
          message: 'Question answer information is missing or invalid.',
        );
      }

      // 7. Validate answer format.
      if (!isValidFormat(answer, answerType)) {
        return const ContestSubmissionResult(
          status: ContestSubmissionStatus.invalidFormat,
          message: 'Invalid answer format. Please check your answer.',
        );
      }

      // 8. Compare mathematical answer.
      final isCorrect =
          isCorrectAnswer(answer, correctAnswer, answerType);

      // 9. Difficulty-based scoring.
      final awardedMark = switch (difficulty) {
        'easy' => 1.5,
        'medium' => 2.5,
        'hard' => 3.0,
        _ => 0.0,
      };

      final penaltyMark = difficulty == 'hard' ? 0.50 : 0.25;

      // 10. Run Firestore transaction.
      return await _firestore.runTransaction<ContestSubmissionResult>(
        (transaction) async {
          // All transaction reads must happen before writes.

          final contestCheck = await transaction.get(contestRef);
          final registrationSnapshot =
              await transaction.get(registrationRef);
          final questionCheck = await transaction.get(questionRef);
          final resultSnapshot = await transaction.get(resultRef);
          final summarySnapshot = await transaction.get(summaryRef);
          final profileSnapshot =
              await transaction.get(profileResultRef);

          if (!contestCheck.exists || !questionCheck.exists) {
            return const ContestSubmissionResult(
              status: ContestSubmissionStatus.questionNotFound,
              message: 'Contest or question not found.',
            );
          }

          if (!registrationSnapshot.exists) {
            return const ContestSubmissionResult(
              status: ContestSubmissionStatus.notRegistered,
              message: 'You are not registered for this contest.',
            );
          }

          if (!resultSnapshot.exists || !summarySnapshot.exists) {
            return const ContestSubmissionResult(
              status: ContestSubmissionStatus.error,
              message: 'Contest result records are missing.',
            );
          }

          // Recheck deadline inside the transaction.
          final latestContestData = contestCheck.data()!;
          final latestStart = latestContestData['Start_Time'];
          final latestEnd = latestContestData['End_Time'];

          if (latestStart is! Timestamp || latestEnd is! Timestamp) {
            return const ContestSubmissionResult(
              status: ContestSubmissionStatus.error,
              message: 'Contest timing information is invalid.',
            );
          }

          final transactionNow = DateTime.now();

          if (transactionNow.isBefore(latestStart.toDate())) {
            return const ContestSubmissionResult(
              status: ContestSubmissionStatus.contestNotStarted,
              message: 'Contest has not started yet.',
            );
          }

          if (!transactionNow.isBefore(latestEnd.toDate())) {
            return const ContestSubmissionResult(
              status: ContestSubmissionStatus.contestEnded,
              message: 'Contest has ended. Submissions are closed.',
            );
          }

          final resultData = resultSnapshot.data()!;
          final summaryData = summarySnapshot.data()!;

          // 11. Prevent submissions after solving.
          final currentStatus =
              (resultData['Status'] ?? 'Unsolved').toString();

          final currentPenaltyCount =
              (resultData['Penalty_Count'] as num?)?.toInt() ?? 0;

          if (currentStatus.toLowerCase() == 'solved') {
            return ContestSubmissionResult(
              status: ContestSubmissionStatus.alreadySolved,
              message: 'You have already solved this question.',
              penaltyCount: currentPenaltyCount,
            );
          }

          // 12. Wrong answer: apply penalty for every attempt
          // and update both Final_Score documents in this transaction.
          if (!isCorrect) {
            final newPenaltyCount = currentPenaltyCount + 1;
            final penaltyField = _penaltyField(difficulty);

            final oldPenaltyTotal =
                (summaryData[penaltyField] as num?)?.toDouble() ?? 0.0;
            final newPenaltyTotal = oldPenaltyTotal + penaltyMark;

            final easyMarks =
                (summaryData['Easy_Total_Mark'] as num?)?.toDouble() ?? 0.0;
            final mediumMarks =
                (summaryData['Medium_Total_Mark'] as num?)?.toDouble() ?? 0.0;
            final hardMarks =
                (summaryData['Hard_Total_Mark'] as num?)?.toDouble() ?? 0.0;

            final easyPenalty =
                (summaryData['Easy_Total_Penalty_Mark'] as num?)?.toDouble() ?? 0.0;
            final mediumPenalty =
                (summaryData['Medium_Total_Penalty_Mark'] as num?)?.toDouble() ?? 0.0;
            final hardPenalty =
                (summaryData['Hard_Total_Penalty_Mark'] as num?)?.toDouble() ?? 0.0;

            final newEasyPenalty =
                penaltyField == 'Easy_Total_Penalty_Mark'
                    ? newPenaltyTotal
                    : easyPenalty;
            final newMediumPenalty =
                penaltyField == 'Medium_Total_Penalty_Mark'
                    ? newPenaltyTotal
                    : mediumPenalty;
            final newHardPenalty =
                penaltyField == 'Hard_Total_Penalty_Mark'
                    ? newPenaltyTotal
                    : hardPenalty;

            final bonus =
                (summaryData['Bonus_Point'] as num?)?.toDouble() ?? 0.0;

            final newFinalScore = easyMarks +
                mediumMarks +
                hardMarks -
                newEasyPenalty -
                newMediumPenalty -
                newHardPenalty +
                bonus;

            final profileData = profileSnapshot.data() ?? {};
            final profileSolved = List<String>.from(
              profileData['Solved_Questions'] ?? [],
            );

            transaction.update(resultRef, {
              'Penalty_Count': newPenaltyCount,
            });

            transaction.update(summaryRef, {
              penaltyField: newPenaltyTotal,
              'Final_Score': newFinalScore,
              'Last_Submission_Time': FieldValue.serverTimestamp(),
            });

            // Keep the profile-level result synchronized even on wrong answers.
            transaction.set(
              profileResultRef,
              {
                'Contest_ID': contestId,
                'Solved_Questions': profileSolved,
                'Final_Score': newFinalScore,
              },
              SetOptions(merge: true),
            );

            return ContestSubmissionResult(
              status: ContestSubmissionStatus.incorrect,
              message: 'Incorrect answer. Try again!',
              penaltyMark: penaltyMark,
              penaltyCount: newPenaltyCount,
              finalScore: newFinalScore,
            );
          }

          // 13. Correct answer: award marks only once.
          final marksField = _marksField(difficulty);

          final oldMarks =
              (summaryData[marksField] as num?)?.toDouble() ?? 0.0;

          final solvedQuestions =
              List<String>.from(summaryData['Solved_Questions'] ?? []);

          if (!solvedQuestions.contains(questionId)) {
            solvedQuestions.add(questionId);
          }

          // 14. Hard bonus eligibility.
          // Read all three Hard result documents before writing.
          bool awardBonus = false;

          if (difficulty == 'hard') {
            final hardIds = ['H01', 'H02', 'H03'];

            final hardSnapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};

            for (final hardId in hardIds) {
              final hardRef =
                  registrationRef.collection('Result').doc(hardId);

              hardSnapshots[hardId] =
                  await transaction.get(hardRef);
            }

            bool allHardSolvedWithoutWrong = true;

            for (final hardId in hardIds) {
              final hardData = hardSnapshots[hardId]?.data();

              final isCurrentQuestion = hardId == questionId;

              final solved = isCurrentQuestion ||
                  (hardData?['Status'] ?? '').toString().toLowerCase() ==
                      'solved';

              final wrongCount = isCurrentQuestion
                  ? currentPenaltyCount
                  : (hardData?['Penalty_Count'] as num?)?.toInt() ?? 0;

              if (!solved || wrongCount != 0) {
                allHardSolvedWithoutWrong = false;
                break;
              }
            }

            final existingBonus =
                (summaryData['Bonus_Point'] as num?)?.toDouble() ?? 0.0;

            awardBonus =
                allHardSolvedWithoutWrong && existingBonus < 1.0;
          }

          final oldBonus =
              (summaryData['Bonus_Point'] as num?)?.toDouble() ?? 0.0;

          // 15. Calculate the new running Final_Score.
          final easyMarks =
              (summaryData['Easy_Total_Mark'] as num?)?.toDouble() ?? 0.0;
          final mediumMarks =
              (summaryData['Medium_Total_Mark'] as num?)?.toDouble() ?? 0.0;
          final hardMarks =
              (summaryData['Hard_Total_Mark'] as num?)?.toDouble() ?? 0.0;

          final easyPenalty =
              (summaryData['Easy_Total_Penalty_Mark'] as num?)?.toDouble() ?? 0.0;
          final mediumPenalty =
              (summaryData['Medium_Total_Penalty_Mark'] as num?)?.toDouble() ?? 0.0;
          final hardPenalty =
              (summaryData['Hard_Total_Penalty_Mark'] as num?)?.toDouble() ?? 0.0;

          final newEasyMarks =
              marksField == 'Easy_Total_Mark' ? oldMarks + awardedMark : easyMarks;
          final newMediumMarks =
              marksField == 'Medium_Total_Mark' ? oldMarks + awardedMark : mediumMarks;
          final newHardMarks =
              marksField == 'Hard_Total_Mark' ? oldMarks + awardedMark : hardMarks;

          final newBonus = awardBonus ? 1.0 : oldBonus;

          final newFinalScore = newEasyMarks +
              newMediumMarks +
              newHardMarks -
              easyPenalty -
              mediumPenalty -
              hardPenalty +
              newBonus;

          // 16. Update individual question result.
          transaction.update(resultRef, {
            'Status': 'Solved',
            'Solved_At': FieldValue.serverTimestamp(),
          });

          // 17. Update contest Summary.
          transaction.update(summaryRef, {
            marksField: oldMarks + awardedMark,
            'Bonus_Point': newBonus,
            'Solved_Questions': solvedQuestions,
            'Final_Score': newFinalScore,
            'Last_Submission_Time': FieldValue.serverTimestamp(),
          });

          // 18. Update profile-level Contest_Result.
          final profileData = profileSnapshot.data() ?? {};
          final profileSolved = List<String>.from(
            profileData['Solved_Questions'] ?? [],
          );

          if (!profileSolved.contains(questionId)) {
            profileSolved.add(questionId);
          }

          transaction.set(
            profileResultRef,
            {
              'Contest_ID': contestId,
              'Solved_Questions': profileSolved,
              'Final_Score': newFinalScore,
            },
            SetOptions(merge: true),
          );

          return ContestSubmissionResult(
            status: ContestSubmissionStatus.correct,
            message: awardBonus
                ? 'Correct answer! Hard bonus unlocked!'
                : 'Correct answer!',
            awardedMark: awardedMark,
            penaltyCount: currentPenaltyCount,
            finalScore: newFinalScore,
          );
        },
      );
    } catch (e) {
      return const ContestSubmissionResult(
        status: ContestSubmissionStatus.error,
        message: 'Something went wrong. Please try again.',
      );
    }
  }

  // =========================================================
  // SUMMARY FIELD HELPERS
  // =========================================================

  String _marksField(String difficulty) {
    switch (difficulty) {
      case 'easy':
        return 'Easy_Total_Mark';
      case 'medium':
        return 'Medium_Total_Mark';
      case 'hard':
        return 'Hard_Total_Mark';
      default:
        throw ArgumentError('Unknown difficulty');
    }
  }

  String _penaltyField(String difficulty) {
    switch (difficulty) {
      case 'easy':
        return 'Easy_Total_Penalty_Mark';
      case 'medium':
        return 'Medium_Total_Penalty_Mark';
      case 'hard':
        return 'Hard_Total_Penalty_Mark';
      default:
        throw ArgumentError('Unknown difficulty');
    }
  }

  // =========================================================
  // ANSWER FORMAT VALIDATION
  // =========================================================

  /// Normalize values saved in Firestore to the central AnswerType values.
  /// This also accepts older aliases used by previous question uploads.
  String _normalizeAnswerType(String rawType) {
    final compact = rawType
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_-]+'), '');

    switch (compact) {
      case 'integer':
        return AnswerType.integer;
      case 'percentage':
      case 'percent':
        return AnswerType.percentage;
      case 'ratio':
      case 'radio':
        return AnswerType.ratio;
      case 'decimal':
        return AnswerType.decimal;
      case 'fraction':
        return AnswerType.fraction;
      case 'mixedfraction':
        return AnswerType.mixedFraction;
      case 'exponential':
      case 'exponent':
        return AnswerType.exponential;
      case 'squareroot':
      case 'root':
        return AnswerType.squareRoot;
      default:
        return '';
    }
  }

  /// Uses the shared AnswerTypeService so contest and other question flows
  /// follow the same accepted answer formats.
  bool isValidFormat(String answer, String answerType) {
    final normalizedType = _normalizeAnswerType(answerType);
    if (normalizedType.isEmpty) return false;

    return AnswerTypeService.validate(
      answer: answer,
      expectedType: normalizedType,
    );
  }

  // =========================================================
  // MATHEMATICAL ANSWER COMPARISON
  // =========================================================

  bool isCorrectAnswer(
    String submitted,
    String correct,
    String answerType,
  ) {
    final type = _normalizeAnswerType(answerType);

    switch (type) {
      case AnswerType.integer:
      case AnswerType.decimal:
        return _compareNumbers(submitted, correct);

      case AnswerType.percentage:
        return _compareNumbers(
          submitted.replaceAll('%', ''),
          correct.replaceAll('%', ''),
        );

      case AnswerType.fraction:
        return _compareFractions(submitted, correct);

      case AnswerType.mixedFraction:
        return _compareMixedFractions(submitted, correct);

      case AnswerType.ratio:
        return _compareRatios(submitted, correct);

      case AnswerType.exponential:
        return _compareExponents(submitted, correct);

      case AnswerType.squareRoot:
        return _compareSquareRoots(submitted, correct);

      default:
        return false;
    }
  }

  bool _compareNumbers(String a, String b) {
    final first = double.tryParse(a.trim());
    final second = double.tryParse(b.trim());

    if (first == null ||
        second == null ||
        !first.isFinite ||
        !second.isFinite) {
      return false;
    }

    return (first - second).abs() < 0.0000001;
  }

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

  bool _compareFractions(String a, String b) {
    final first = _fractionValue(a);
    final second = _fractionValue(b);

    if (first == null || second == null) return false;

    return (first - second).abs() < 0.0000001;
  }

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

    if (trimmed.contains('/')) {
      return _fractionValue(trimmed) ?? _mixedFractionValue(trimmed);
    }

    return double.tryParse(trimmed);
  }

  bool _compareMixedFractions(String a, String b) {
    final first = _answerAsNumber(a);
    final second = _answerAsNumber(b);

    if (first == null || second == null) return false;

    return (first - second).abs() < 0.0000001;
  }

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

  double? _exponentValue(String value) {
    final parts = value.split('^');

    if (parts.length != 2) return null;

    final base = double.tryParse(parts[0].trim());
    final exponent = int.tryParse(parts[1].trim());

    if (base == null ||
        exponent == null ||
        (base == 0 && exponent < 0)) {
      return null;
    }

    return _integerPower(base, exponent);
  }

  double _integerPower(double base, int exponent) {
    if (exponent == 0) return 1;

    double result = 1;

    for (int i = 0; i < exponent.abs(); i++) {
      result *= base;

      if (!result.isFinite) return double.nan;
    }

    return exponent < 0 ? 1 / result : result;
  }

  double? _squareRootValue(String value) {
    final match = RegExp(
      r'^(?:(\d+(?:\.\d+)?)\s*)?√\s*(\d+(?:\.\d+)?)$',
    ).firstMatch(value.trim());
    if (match == null) return null;

    final coefficient = double.tryParse(match.group(1) ?? '1');
    final radicand = double.tryParse(match.group(2)!);
    if (coefficient == null || radicand == null || radicand < 0) {
      return null;
    }

    final result = coefficient * math.sqrt(radicand);
    return result.isFinite ? result : null;
  }

  bool _compareSquareRoots(String a, String b) {
    final first = _squareRootValue(a);
    final second = _squareRootValue(b);
    if (first == null || second == null) return false;
    return (first - second).abs() < 0.0000001;
  }

  bool _compareExponents(String a, String b) {
    final first = _exponentValue(a) ?? double.tryParse(a.trim());
    final second = _exponentValue(b) ?? double.tryParse(b.trim());

    if (first == null ||
        second == null ||
        !first.isFinite ||
        !second.isFinite) {
      return false;
    }

    return (first - second).abs() < 0.0000001;
  }
}
