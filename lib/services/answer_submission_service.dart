import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // =====================================================
  // MAIN ANSWER SUBMISSION FUNCTION
  // =====================================================

  Future<AnswerSubmissionResult> submitAnswer({
    required String questionId,
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

      // 2. Fetch question from Firestore.

      final questionRef = _firestore
          .collection('commonQuestions')
          .doc(questionId);

      final questionSnapshot = await questionRef.get();

      if (!questionSnapshot.exists) {
        return AnswerSubmissionResult(
          status: AnswerSubmissionStatus.questionNotFound,
          message: 'Question not found.',
        );
      }

      final questionData = questionSnapshot.data()!;

      final String answerType =
          (questionData['answerType'] ?? '')
              .toString()
              .trim()
              .toLowerCase();

      final String correctAnswer =
          (questionData['correctAnswer'] ?? '')
              .toString()
              .trim();

      final int questionNo =
          int.tryParse(
                questionData['questionNo'].toString(),
              ) ??
              0;

      if (answerType.isEmpty || correctAnswer.isEmpty) {
        return AnswerSubmissionResult(
          status: AnswerSubmissionStatus.error,
          message: 'Question answer information is missing.',
        );
      }

      // 3. Check answer format FIRST.

      if (!isValidFormat(answer, answerType)) {
        return AnswerSubmissionResult(
          status: AnswerSubmissionStatus.invalidFormat,
          message:
              'Invalid answer. Please enter the answer in the correct format.',
        );
      }

      // 4. Check whether the answer is correct.

      final bool isCorrect = isCorrectAnswer(
        answer,
        correctAnswer,
        answerType,
      );

      if (!isCorrect) {
        return AnswerSubmissionResult(
          status: AnswerSubmissionStatus.incorrect,
          message: 'Incorrect answer. Try again!',
        );
      }

      // 5. Get student's username.

      final userSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userSnapshot.exists) {
        return AnswerSubmissionResult(
          status: AnswerSubmissionStatus.error,
          message: 'User profile not found.',
        );
      }

      final userData = userSnapshot.data()!;

      final String userName =
          (userData['userName'] ?? 'Student').toString();

      // 6. Prepare both Firestore document references.

      // Under users/{uid}/solvedQuestions/{questionId}

      final userSolvedRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('solvedQuestions')
          .doc(questionId);

      // Under commonQuestions/{questionId}/solvedBy/{uid}

      final questionSolvedRef = questionRef
          .collection('solvedBy')
          .doc(user.uid);

      // 7. Save both records using a batch.

      final batch = _firestore.batch();

      batch.set(
        userSolvedRef,
        {
          'questionId': questionId,
          'questionNo': questionNo,
          'solvedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      batch.set(
        questionSolvedRef,
        {
          'userId': user.uid,
          'userName': userName,
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      // 8. Return success.

      return AnswerSubmissionResult(
        status: AnswerSubmissionStatus.correct,
        message: 'Correct answer!',
      );
    } catch (e) {
      return AnswerSubmissionResult(
        status: AnswerSubmissionStatus.error,
        message: 'Something went wrong. Please try again.',
      );
    }
  }

  // =====================================================
  // ANSWER FORMAT VALIDATION
  // =====================================================

  bool isValidFormat(
    String answer,
    String answerType,
  ) {
    final value = answer.trim();

    switch (answerType) {
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

  // =====================================================
  // EXPONENT FORMAT
  // =====================================================

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
    switch (answerType) {
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

    final numerator =
        double.tryParse(parts[0].trim());

    final denominator =
        double.tryParse(parts[1].trim());

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

    if (first == null || second == null) {
      return false;
    }

    return (first - second).abs() < 0.0000001;
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
    final first = _answerAsNumber(a) ??
        _mixedFractionValue(a);

    final second = _answerAsNumber(b) ??
        _mixedFractionValue(b);

    if (first == null || second == null) {
      return false;
    }

    return (first - second).abs() < 0.0000001;
  }

  // =====================================================
  // RATIO COMPARISON
  // =====================================================

  List<int>? _ratioParts(String value) {
    final match = RegExp(
      r'^(\d+)\s*:\s*(\d+)$',
    ).firstMatch(value.trim());

    if (match == null) return null;

    final first = int.tryParse(match.group(1)!);
    final second = int.tryParse(match.group(2)!);

    if (first == null || second == null) {
      return null;
    }

    return [first, second];
  }

  bool _compareRatios(String a, String b) {
    final first = _ratioParts(a);
    final second = _ratioParts(b);

    if (first == null || second == null) {
      return false;
    }

    // Cross multiplication checks equivalent ratios.

    return first[0] * second[1] ==
        first[1] * second[0];
  }

  // =====================================================
  // EXPONENT COMPARISON
  // =====================================================

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
    final first = _exponentValue(a) ??
        double.tryParse(a.trim());

    final second = _exponentValue(b) ??
        double.tryParse(b.trim());

    if (first == null || second == null) {
      return false;
    }

    return (first - second).abs() < 0.0000001;
  }
}