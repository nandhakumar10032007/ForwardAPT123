import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';



enum AnswerSubmissionStatus {

  invalidFormat,

  correct,

  incorrect,

  questionNotFound,

  notLoggedIn,

  error,

}



class AnswerSubmissionResult {

  final AnswerSubmissionStatus status;

  final String message;



  AnswerSubmissionResult({

    required this.status,

    required this.message,

  });

}



class AnswerSubmissionService {

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;



  final FirebaseAuth _auth = FirebaseAuth.instance;



  // =====================================================

  // MAIN ANSWER SUBMISSION FUNCTION

  // =====================================================



  Future<AnswerSubmissionResult> submitAnswer({

    required String questionId,

    required String topic,

    required String submittedAnswer,

  }) async {

    try {

      // 1. Check logged-in user.

      final user = _auth.currentUser;



      if (user == null) {

        return AnswerSubmissionResult(

          status: AnswerSubmissionStatus.notLoggedIn,

          message: 'Please log in first.',

        );

      }



      final answer = submittedAnswer.trim();



      if (answer.isEmpty) {

        return AnswerSubmissionResult(

          status: AnswerSubmissionStatus.invalidFormat,

          message:

              'Invalid answer. Please enter the answer in the correct format.',

        );

      }



      // 2. Validate topic and fetch the question from the new

      // Common_questions/{topic}/questions/{questionId} structure.

      final normalizedTopic = topic.trim();



      if (normalizedTopic.isEmpty) {

        return AnswerSubmissionResult(

          status: AnswerSubmissionStatus.questionNotFound,

          message: 'Question topic is missing.',

        );

      }



      final questionRef = _firestore

          .collection('Common_questions')

          .doc(normalizedTopic)

          .collection('questions')

          .doc(questionId);



      final questionSnapshot = await questionRef.get();



      if (!questionSnapshot.exists) {

        return AnswerSubmissionResult(

          status: AnswerSubmissionStatus.questionNotFound,

          message: 'Question not found.',

        );

      }



      final questionData = questionSnapshot.data()!;



      final String rawAnswerType =
          (questionData['answerType'] ?? '').toString();
      final String answerType = _normalizeAnswerType(rawAnswerType);



      final String correctAnswer =

          (questionData['correctAnswer'] ?? '')

              .toString()

              .trim();



      final int questionNo = int.tryParse(
            (questionData['questionNo'] ?? '0').toString(),
          ) ??
          0;



      if (answerType.isEmpty || correctAnswer.isEmpty) {

        return AnswerSubmissionResult(

          status: AnswerSubmissionStatus.error,

          message: 'Question answer information is missing.',

        );

      }



      // 3. Validate answer format FIRST.

      if (!isValidFormat(answer, answerType)) {

        return AnswerSubmissionResult(

          status: AnswerSubmissionStatus.invalidFormat,

          message:

              'Invalid answer. Please enter the answer in the correct format.',

        );

      }



      // 4. Check whether the answer is mathematically correct.

      final bool isCorrect = isCorrectAnswer(

        answer,

        correctAnswer,

        answerType,

      );



      
      debugPrint('========== COMMON QUESTION ANSWER DEBUG ==========');
      debugPrint('Question path: ${questionRef.path}');
      debugPrint('Question ID: $questionId');
      debugPrint('Topic: [$normalizedTopic]');
      debugPrint('Submitted answer: [$answer]');
      debugPrint('Correct answer: [$correctAnswer]');
      debugPrint('Raw answer type: [$rawAnswerType]');
      debugPrint('Normalized answer type: [$answerType]');
      debugPrint('Format valid: ${isValidFormat(answer, answerType)}');
      debugPrint('Comparison result: $isCorrect');
      debugPrint('==================================================');

      if (!isCorrect) {

        return AnswerSubmissionResult(

          status: AnswerSubmissionStatus.incorrect,

          message: 'Incorrect answer. Try again!',

        );

      }



      // 5. Prepare Firestore references.

      final userRef = _firestore.collection('users').doc(user.uid);



      // User-side solved record:

      // users/{userId}/solved/{topic}/questions/{questionId}

      final userSolvedRef = userRef

          .collection('solved')

          .doc(normalizedTopic)

          .collection('questions')

          .doc(questionId);



      // Question-side solved record:

      // Common_questions/{topic}/questions/{questionId}/solved/{userId}

      final questionSolvedRef =

          questionRef.collection('solved').doc(user.uid);



      // 6. Get current IST date (UTC + 05:30).

      final DateTime istNow = DateTime.now()

          .toUtc()

          .add(const Duration(hours: 5, minutes: 30));



      final String today =

          '${istNow.year.toString().padLeft(4, '0')}-'

          '${istNow.month.toString().padLeft(2, '0')}-'

          '${istNow.day.toString().padLeft(2, '0')}';



      final DateTime todayDate = DateTime.utc(

        istNow.year,

        istNow.month,

        istNow.day,

      );



      // 7. Use a transaction to prevent duplicate updates.

      final bool wasFirstSubmission =

          await _firestore.runTransaction<bool>((transaction) async {

        // Read all required documents before writing.

        final userSnapshot = await transaction.get(userRef);



        final solvedSnapshot =

            await transaction.get(userSolvedRef);



        final questionSolvedSnapshot =

            await transaction.get(questionSolvedRef);



        if (!userSnapshot.exists) {

          throw Exception('User profile not found.');

        }



        // IMPORTANT:

        // If already solved, do not update anything.

        // The correct-answer popup will still be shown.

        if (solvedSnapshot.exists ||

            questionSolvedSnapshot.exists) {

          return false;

        }



        final userData = userSnapshot.data()!;



        final String userName =

            (userData['userName'] ?? 'Student').toString();



        // 8. Calculate problem solved count.

        final int oldProblemCount =

            (userData['problemSolvedCount'] as num?)?.toInt() ?? 0;



        final int newProblemCount = oldProblemCount + 1;



        // 9. Calculate streak.

        final int oldStreak =

            (userData['streak'] as num?)?.toInt() ?? 0;



        final String? lastActiveDate =

            userData['lastActiveDate']?.toString();



        int newStreak;



        if (lastActiveDate == today) {

          // Already solved at least one question today.

          // Streak must not increase again.

          newStreak = oldStreak;

        } else if (lastActiveDate != null &&

            lastActiveDate.isNotEmpty) {

          final DateTime? previousDate =

              DateTime.tryParse(lastActiveDate);



          if (previousDate != null) {

            final DateTime previousDay = DateTime.utc(

              previousDate.year,

              previousDate.month,

              previousDate.day,

            );



            final int difference =

                todayDate.difference(previousDay).inDays;



            if (difference == 1) {

              // Last active yesterday: continue streak.

              newStreak = oldStreak + 1;

            } else {

              // Missed one or more days: start a new streak.

              newStreak = 1;

            }

          } else {

            // Invalid previous date.

            newStreak = 1;

          }

        } else {

          // First-ever successful submission.

          newStreak = 1;

        }



        // 10. Update user document.

        transaction.update(userRef, {

          'problemSolvedCount': newProblemCount,

          'streak': newStreak,

          'lastSubmissionAt': FieldValue.serverTimestamp(),

          'lastActiveDate': today,

        });



        // 11. Save solved question under the user's topic-wise path.

        transaction.set(userSolvedRef, {

          'questionId': questionId,

          'solvedAt': FieldValue.serverTimestamp(),

          'questionNo': questionNo,

        });



        // 12. Save student details under the question's solved subcollection.

        transaction.set(questionSolvedRef, {

          'userId': user.uid,

          'userName': userName,

          'solvedAt': FieldValue.serverTimestamp(),

        });



        return true;

      });



      // 13. Always return CORRECT for a mathematically

      // correct answer, even if the user solved it before.

      //

      // If already solved, the transaction makes no writes.

      return AnswerSubmissionResult(

        status: AnswerSubmissionStatus.correct,

        message: wasFirstSubmission

            ? 'Correct answer!'

            : 'Correct answer! You have already solved this question.',

      );

    } catch (e, stackTrace) {
      debugPrint('Answer submission failed: $e');
      debugPrintStack(stackTrace: stackTrace);

      return AnswerSubmissionResult(

        status: AnswerSubmissionStatus.error,

        message: 'Something went wrong. Please try again.',

      );

    }

  }



  // =====================================================

  // ANSWER FORMAT VALIDATION

  // =====================================================



  String _normalizeAnswerType(String rawType) {
    final compact = rawType
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_-]+'), '');

    switch (compact) {
      case 'integer':
        return 'integer';
      case 'decimal':
        return 'decimal';
      case 'percentage':
      case 'percent':
        return 'percentage';
      case 'ratio':
        return 'ratio';
      case 'fraction':
        return 'fraction';
      case 'mixedfraction':
      case 'mixednumber':
      case 'numberfraction':
        return 'mixed fraction';
      case 'exponent':
      case 'exponential':
        return 'exponent';
      default:
        return rawType.trim().toLowerCase();
    }
  }

  bool isValidFormat(

    String answer,

    String answerType,

  ) {

    final value = answer.trim();



    switch (_normalizeAnswerType(answerType)) {

      // INTEGER

      case 'integer':

        return RegExp(

          r'^[+-]?\d+$',

        ).hasMatch(value);



      // DECIMAL

      case 'decimal':

        return RegExp(

          r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)$',

        ).hasMatch(value);



      // PERCENTAGE

      case 'percentage':

        return RegExp(

          r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)\s*%?$',

        ).hasMatch(value);



      // FRACTION

      case 'fraction':

        return _isValidFraction(value);



      // MIXED FRACTION

      case 'mixed fraction':

      case 'mixed_fraction':

        return _isValidMixedFraction(value);



      // RATIO

      case 'ratio':

        return _isValidRatio(value);



      // EXPONENT

      case 'exponent':

        return _isValidExponent(value);



      default:

        return false;

    }

  }



  // =====================================================

  // FRACTION FORMAT

  // =====================================================



  bool _isValidFraction(String value) {

    final match = RegExp(

      r'^([+-]?\d+)\s*/\s*(\d+)$',

    ).firstMatch(value);



    if (match == null) return false;



    final denominator = int.tryParse(match.group(2)!);



    return denominator != null && denominator != 0;

  }



  // =====================================================

  // MIXED FRACTION FORMAT

  // =====================================================



  bool _isValidMixedFraction(String value) {

    final match = RegExp(

      r'^(\d+)\s+(\d+)\s*/\s*(\d+)$',

    ).firstMatch(value);



    if (match == null) return false;



    final whole = int.tryParse(match.group(1)!);

    final numerator = int.tryParse(match.group(2)!);

    final denominator = int.tryParse(match.group(3)!);



    return whole != null &&

        numerator != null &&

        denominator != null &&

        denominator != 0 &&

        numerator < denominator;

  }



  // =====================================================

  // RATIO FORMAT

  // =====================================================



  bool _isValidRatio(String value) {
    final trimmed = value.trim();

    // Supports 2 or more terms: 2:3, 2:3:4, 2:3:4:5, 1.5:2:3.
    final isMatching = RegExp(
      r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:\s*:\s*[+-]?(?:\d+(?:\.\d+)?|\.\d+))+$',
    ).hasMatch(trimmed);

    if (!isMatching) return false;

    final values = trimmed
        .split(':')
        .map((part) => double.tryParse(part.trim()))
        .toList();

    return values.every((number) => number != null) &&
        values.any((number) => number != 0);
  }

  bool _isValidExponent(String value) {

    return RegExp(

      r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)\s*\^\s*[+-]?\d+$',

    ).hasMatch(value);

  }



  // =====================================================

  // CORRECT ANSWER CHECKING

  // =====================================================



  bool isCorrectAnswer(

    String submitted,

    String correct,

    String answerType,

  ) {

    switch (_normalizeAnswerType(answerType)) {

      case 'integer':
        final submittedInteger = BigInt.tryParse(submitted.trim());
        final correctInteger = BigInt.tryParse(correct.trim());

        return submittedInteger != null &&
            correctInteger != null &&
            submittedInteger == correctInteger;

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

      case 'mixed_fraction':

        return _compareMixedFractions(submitted, correct);



      case 'ratio':

        return _compareRatios(submitted, correct);



      case 'exponent':

        return _compareExponents(submitted, correct);



      default:

        return false;

    }

  }



  // =====================================================

  // INTEGER AND DECIMAL COMPARISON

  // =====================================================



  bool _compareNumbers(String a, String b) {

    final first = double.tryParse(a.trim());

    final second = double.tryParse(b.trim());



    if (first == null || second == null) {

      return false;

    }



    return (first - second).abs() < 0.0000001;

  }



  // =====================================================

  // FRACTION COMPARISON

  // =====================================================



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



  bool _compareFractions(String submitted, String correct) {
    final submittedMatch = RegExp(
      r'^([+-]?\d+)\s*/\s*(\d+)$',
    ).firstMatch(submitted.trim());
    final correctMatch = RegExp(
      r'^([+-]?\d+)\s*/\s*(\d+)$',
    ).firstMatch(correct.trim());

    if (submittedMatch == null || correctMatch == null) return false;

    final submittedNumerator = BigInt.tryParse(submittedMatch.group(1)!);
    final submittedDenominator = BigInt.tryParse(submittedMatch.group(2)!);
    final correctNumerator = BigInt.tryParse(correctMatch.group(1)!);
    final correctDenominator = BigInt.tryParse(correctMatch.group(2)!);

    if (submittedNumerator == null ||
        submittedDenominator == null ||
        correctNumerator == null ||
        correctDenominator == null ||
        submittedDenominator == BigInt.zero ||
        correctDenominator == BigInt.zero) {
      return false;
    }

    // Student's fraction must already be in simplest form.
    if (_greatestCommonDivisor(
          submittedNumerator.abs(),
          submittedDenominator,
        ) !=
        BigInt.one) {
      return false;
    }

    // Exact comparison with the stored correct answer.
    return submittedNumerator * correctDenominator ==
        correctNumerator * submittedDenominator;
  }



  // =====================================================

  // MIXED FRACTION COMPARISON

  // =====================================================



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

      return _fractionValue(trimmed);

    }



    return double.tryParse(trimmed);

  }



  bool _compareMixedFractions(String a, String b) {

    final first = _answerAsNumber(a) ?? _mixedFractionValue(a);



    final second = _answerAsNumber(b) ?? _mixedFractionValue(b);



    if (first == null || second == null) {

      return false;

    }



    return (first - second).abs() < 0.0000001;

  }



  // =====================================================

  // RATIO COMPARISON

  // =====================================================



  // Converts decimal ratio terms into exact integers using a shared scale.
  // Example: 1.5:2 becomes [15, 20], equivalent to 3:4.
  List<BigInt>? _ratioIntegerParts(String value) {
    final parts = value.trim().split(':');
    if (parts.length < 2) return null;

    var maxDecimalPlaces = 0;

    for (final rawPart in parts) {
      final part = rawPart.trim();
      final match = RegExp(r'^([+-]?)(\d*)(?:\.(\d+))?$')
          .firstMatch(part);
      if (match == null) return null;

      final whole = match.group(2) ?? '';
      final fraction = match.group(3) ?? '';
      if (whole.isEmpty && fraction.isEmpty) return null;
      if (fraction.length > maxDecimalPlaces) {
        maxDecimalPlaces = fraction.length;
      }
    }

    final scale = BigInt.from(10).pow(maxDecimalPlaces);
    final values = <BigInt>[];

    for (final rawPart in parts) {
      final part = rawPart.trim();
      final negative = part.startsWith('-');
      final unsigned = (part.startsWith('-') || part.startsWith('+'))
          ? part.substring(1)
          : part;
      final components = unsigned.split('.');
      final whole = components[0].isEmpty ? '0' : components[0];
      final fraction = components.length > 1 ? components[1] : '';
      final paddedFraction = fraction.padRight(maxDecimalPlaces, '0');

      final wholeValue = BigInt.tryParse(whole);
      final fractionValue = BigInt.tryParse(
        paddedFraction.isEmpty ? '0' : paddedFraction,
      );
      if (wholeValue == null || fractionValue == null) return null;

      var number = wholeValue * scale + fractionValue;
      if (negative) number = -number;
      values.add(number);
    }

    if (values.every((number) => number == BigInt.zero)) return null;
    return values;
  }

  BigInt _greatestCommonDivisor(BigInt a, BigInt b) {
    var first = a.abs();
    var second = b.abs();
    while (second != BigInt.zero) {
      final remainder = first % second;
      first = second;
      second = remainder;
    }
    return first;
  }

  BigInt _greatestCommonDivisorOfList(List<BigInt> values) {
    var result = BigInt.zero;
    for (final value in values) {
      result = _greatestCommonDivisor(result, value);
    }
    return result;
  }

  bool _compareRatios(String submitted, String correct) {
    final first = _ratioIntegerParts(submitted);
    final second = _ratioIntegerParts(correct);

    if (first == null ||
        second == null ||
        first.length != second.length) {
      return false;
    }

    // Student's ratio must already be in simplest form.
    if (_greatestCommonDivisorOfList(first) != BigInt.one) {
      return false;
    }

    // Compare every pair to support ratios with 3 or more terms.
    for (var i = 0; i < first.length; i++) {
      for (var j = i + 1; j < first.length; j++) {
        if (first[i] * second[j] != first[j] * second[i]) {
          return false;
        }
      }
    }
    return true;
  }

  double? _exponentValue(String value) {

    final parts = value.split('^');



    if (parts.length != 2) return null;



    final base = double.tryParse(parts[0].trim());

    final exponent = int.tryParse(parts[1].trim());



    if (base == null || exponent == null) {

      return null;

    }



    if (base == 0 && exponent < 0) {

      return null;

    }



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

    final first = _exponentValue(a) ?? double.tryParse(a.trim());



    final second = _exponentValue(b) ?? double.tryParse(b.trim());



    if (first == null || second == null) {

      return false;
    }
    return (first - second).abs() < 0.0000001;
  }

} 