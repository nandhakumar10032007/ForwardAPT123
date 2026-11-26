
import '../answer_type.dart';

class AnswerTypeService {

  // Integer: -5 or 5
  static final RegExp _integerRegex = RegExp(
    r'^[+-]?\d+$',
  );

  // Percentage: 5% or 12.5%
  static final RegExp _percentageRegex = RegExp(
    r'^[+-]?\d+(?:\.\d+)?%$',
  );

  // Ratio: 2:3, 2:3:4, 2:3:4:5 or more terms
  static final RegExp _ratioRegex = RegExp(
    r'^[+-]?\d+(?:\.\d+)?(?:\s*:\s*[+-]?\d+(?:\.\d+)?)+$',
  );

  // Decimal: 15.5 or 15.50
  static final RegExp _decimalRegex = RegExp(
    r'^[+-]?\d+\.\d+$',
  );

  // Fraction: 3/4
  static final RegExp _fractionRegex = RegExp(
    r'^[+-]?\d+\s*/\s*[+-]?\d+$',
  );

 // Mixed fraction: 10-5/6
static final RegExp _mixedFractionRegex = RegExp(
  r'^[+-]?\d+-\s*\d+\s*/\s*[+-]?\d+$',
);

  // Exponential: 2^3
  static final RegExp _exponentialRegex = RegExp(
    r'^[+-]?\d+(?:\.\d+)?\s*\^\s*[+-]?\d+(?:\.\d+)?$',
  );

  // Square root: √5 or 3√5
  static final RegExp _squareRootRegex = RegExp(
    r'^(?:\d+(?:\.\d+)?\s*)?√\s*\d+(?:\.\d+)?$',
  );

  /// Detects the answer type automatically.
  ///
  /// Returns null if the answer does not match any supported format.
  static String? detect(String answer) {
    final value = answer.trim();

    if (value.isEmpty) return null;

    if (_percentageRegex.hasMatch(value)) {
      return AnswerType.percentage;
    }

    if (_ratioRegex.hasMatch(value)) {
      return AnswerType.ratio;
    }

    if (_mixedFractionRegex.hasMatch(value)) {
      if (_hasNonZeroDenominator(value)) {
        return AnswerType.mixedFraction;
      }
      return null;
    }

    if (_fractionRegex.hasMatch(value)) {
      if (_hasNonZeroDenominator(value)) {
        return AnswerType.fraction;
      }
      return null;
    }

    if (_decimalRegex.hasMatch(value)) {
      return AnswerType.decimal;
    }

    if (_integerRegex.hasMatch(value)) {
      return AnswerType.integer;
    }

    if (_exponentialRegex.hasMatch(value)) {
      return AnswerType.exponential;
    }

    if (_squareRootRegex.hasMatch(value)) {
      return AnswerType.squareRoot;
    }

    return null;
  }

  /// Checks whether a fraction denominator is non-zero.
  static bool _hasNonZeroDenominator(String value) {
    final parts = value.split('/');

    if (parts.length != 2) return false;

    final denominator = int.tryParse(parts[1].trim());

    return denominator != null && denominator != 0;
  }

  /// Validates an answer against its detected format.
  static bool isValid(String answer) {
    return detect(answer) != null;
  }

  /// Validates an answer against an expected answer type.
  static bool validate({
    required String answer,
    required String expectedType,
  }) {
    final detectedType = detect(answer);

    if (detectedType == null) return false;

    return detectedType.toLowerCase() ==
        expectedType.trim().toLowerCase();
  }

  /// Returns a helpful validation message.
  static String? validationError({
    required String answer,
    required String expectedType,
  }) {
    if (answer.trim().isEmpty) {
      return 'Correct answer is required.';
    }

    final detectedType = detect(answer);

    if (detectedType == null) {
      return 'Invalid answer format.';
    }

    if (detectedType.toLowerCase() !=
        expectedType.trim().toLowerCase()) {
      return 'Expected $expectedType but detected $detectedType.';
    }

    return null;
  }
}
