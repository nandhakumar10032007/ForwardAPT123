
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';

/// A question parsed from Excel before it receives a global question number.
class ImportedQuestionDraft {
  final int excelRow;
  final String title;
  final String question;
  final String topic;
  final String difficulty;
  final String answerType;
  final String correctAnswer;

  const ImportedQuestionDraft({
    required this.excelRow,
    required this.title,
    required this.question,
    required this.topic,
    required this.difficulty,
    required this.answerType,
    required this.correctAnswer,
  });
}

/// Describes one row and its validation result.
class QuestionImportRow {
  final int excelRow;
  final ImportedQuestionDraft? question;
  final String status;
  final String message;

  const QuestionImportRow({
    required this.excelRow,
    required this.question,
    required this.status,
    required this.message,
  });

  bool get isAccepted => status == 'Accepted';

  bool get isRejected => status == 'Rejected';

  bool get isDuplicate => status == 'Duplicate';
}

/// Contains the complete preview result for an Excel import.
class QuestionImportResult {
  final List<QuestionImportRow> rows;
  final String category;

  const QuestionImportResult({
    required this.rows,
    required this.category,
  });

  List<ImportedQuestionDraft> get acceptedQuestions {
    return rows
        .where((row) => row.isAccepted)
        .map((row) => row.question!)
        .toList();
  }

  int get acceptedCount =>
      rows.where((row) => row.isAccepted).length;

  int get rejectedCount =>
      rows.where((row) => row.isRejected).length;

  int get duplicateCount =>
      rows.where((row) => row.isDuplicate).length;
}

class QuestionImportService {
  QuestionImportService({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const Map<String, String> _collections = {
    'common': 'commonQuestions',
    'contest': 'contestQuestions',
    'test': 'testQuestions',
  };

  static const Set<String> _requiredHeaders = {
    'title',
    'question',
    'topic',
    'difficulty',
    'answertype',
    'correctanswer',
  };

  static const Set<String> _allowedDifficulties = {
    'easy',
    'medium',
    'hard',
  };

  static const Set<String> _allowedAnswerTypes = {
    'integer',
    'decimal',
    'fraction',
    'percentage',
    'radio',
  };

  /// Reads an Excel .xlsx file and prepares a preview.
  ///
  /// Expected columns:
  /// title, question, topic, difficulty, answerType, correctAnswer
  ///
  /// Question numbers and createdAt are assigned later.
  Future<QuestionImportResult> previewExcel({
    required Uint8List bytes,
    required String category,
  }) async {
    final normalizedCategory = category.trim().toLowerCase();

    final collectionName = _collections[normalizedCategory];

    if (collectionName == null) {
      throw ArgumentError(
        'Invalid category. Use common, contest, or test.',
      );
    }

    if (bytes.isEmpty) {
      throw const FormatException('The selected Excel file is empty.');
    }

    final Excel workbook;

    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (_) {
      throw const FormatException(
        'Could not read this file. Please select a valid .xlsx file.',
      );
    }

    if (workbook.tables.isEmpty) {
      throw const FormatException(
        'The Excel file does not contain a worksheet.',
      );
    }

    final sheetName = workbook.tables.keys.first;
    final sheet = workbook.tables[sheetName];

    if (sheet == null || sheet.rows.isEmpty) {
      throw const FormatException(
        'The first worksheet is empty.',
      );
    }

    final headerRow = sheet.rows.first;

    final headers = headerRow.map((cell) {
      return _normalizeHeader(_cellText(cell));
    }).toList();

    final missingHeaders = _requiredHeaders
        .where((header) => !headers.contains(header))
        .toList();

    if (missingHeaders.isNotEmpty) {
      throw FormatException(
        'Missing required Excel columns: '
        '${missingHeaders.join(', ')}. '
        'Please check the first row of your worksheet.',
      );
    }

    final columnIndexes = <String, int>{};

    for (var index = 0; index < headers.length; index++) {
      final header = headers[index];

      if (_requiredHeaders.contains(header)) {
        if (columnIndexes.containsKey(header)) {
          throw FormatException(
            'The column "$header" appears more than once.',
          );
        }

        columnIndexes[header] = index;
      }
    }

    // Load existing question text from the selected category.
    final existingSnapshot = await _firestore
        .collection(collectionName)
        .get();

    final existingQuestionKeys = <String>{};

    for (final document in existingSnapshot.docs) {
      final data = document.data();
      final existingText = data['question'];

      if (existingText is String && existingText.trim().isNotEmpty) {
        existingQuestionKeys.add(_normalizeQuestion(existingText));
      }
    }

    final seenInFile = <String>{};
    final results = <QuestionImportRow>[];

    // Row 1 contains headers, so Excel data starts at row 2.
    for (var index = 1; index < sheet.rows.length; index++) {
      final cells = sheet.rows[index];
      final excelRowNumber = index + 1;

      if (_isEmptyRow(cells)) {
        continue;
      }

      String valueOf(String header) {
        final columnIndex = columnIndexes[header]!;

        if (columnIndex >= cells.length) {
          return '';
        }

        return _cellText(cells[columnIndex]).trim();
      }

      final title = valueOf('title');
      final questionText = valueOf('question');
      final topic = valueOf('topic');
      final difficulty = valueOf('difficulty');
      final answerType = valueOf('answertype');
      final correctAnswer = valueOf('correctanswer');

      final validationError = _validateQuestion(
        title: title,
        question: questionText,
        topic: topic,
        difficulty: difficulty,
        answerType: answerType,
        correctAnswer: correctAnswer,
      );

      if (validationError != null) {
        results.add(
          QuestionImportRow(
            excelRow: excelRowNumber,
            question: null,
            status: 'Rejected',
            message: validationError,
          ),
        );

        continue;
      }

      final questionKey = _normalizeQuestion(questionText);

      if (existingQuestionKeys.contains(questionKey)) {
        results.add(
          QuestionImportRow(
            excelRow: excelRowNumber,
            question: null,
            status: 'Duplicate',
            message: 'This question already exists in '
                '$normalizedCategory questions.',
          ),
        );

        continue;
      }

      if (!seenInFile.add(questionKey)) {
        results.add(
          QuestionImportRow(
            excelRow: excelRowNumber,
            question: null,
            status: 'Duplicate',
            message: 'This question appears more than once '
                'in the selected Excel file.',
          ),
        );

        continue;
      }

      final draft = ImportedQuestionDraft(
        excelRow: excelRowNumber,
        title: title,
        question: questionText,
        topic: topic,
        difficulty: _canonicalDifficulty(difficulty),
        answerType: _canonicalAnswerType(answerType),
        correctAnswer: correctAnswer,
      );

      results.add(
        QuestionImportRow(
          excelRow: excelRowNumber,
          question: draft,
          status: 'Accepted',
          message: 'Ready to upload.',
        ),
      );
    }

    return QuestionImportResult(
      rows: results,
      category: normalizedCategory,
    );
  }

  String? _validateQuestion({
    required String title,
    required String question,
    required String topic,
    required String difficulty,
    required String answerType,
    required String correctAnswer,
  }) {
    if (title.isEmpty) {
      return 'Title is required.';
    }

    if (question.isEmpty) {
      return 'Question text is required.';
    }

    if (topic.isEmpty) {
      return 'Topic is required.';
    }

    if (difficulty.isEmpty) {
      return 'Difficulty is required.';
    }

    if (!_allowedDifficulties.contains(difficulty.toLowerCase())) {
      return 'Difficulty must be Easy, Medium, or Hard.';
    }

    if (answerType.isEmpty) {
      return 'Answer type is required.';
    }

    if (!_allowedAnswerTypes.contains(answerType.toLowerCase())) {
      return 'Answer type must be Integer, Decimal, Fraction, '
          'Percentage, or Radio.';
    }

    if (correctAnswer.isEmpty) {
      return 'Correct answer is required.';
    }

    return null;
  }

  String _normalizeHeader(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_-]+'), '');
  }

  /// Normalizes question text for duplicate detection.
  ///
  /// Ignores case and repeated whitespace, but preserves punctuation.
  String _normalizeQuestion(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String _canonicalDifficulty(String value) {
    switch (value.trim().toLowerCase()) {
      case 'easy':
        return 'Easy';
      case 'medium':
        return 'Medium';
      case 'hard':
        return 'Hard';
      default:
        return value.trim();
    }
  }

  String _canonicalAnswerType(String value) {
    switch (value.trim().toLowerCase()) {
      case 'integer':
        return 'Integer';
      case 'decimal':
        return 'Decimal';
      case 'fraction':
        return 'Fraction';
      case 'percentage':
        return 'Percentage';
      case 'radio':
        return 'Radio';
      default:
        return value.trim();
    }
  }

  String _cellText(Data? cell) {
    if (cell == null || cell.value == null) {
      return '';
    }

    return cell.value.toString();
  }

  bool _isEmptyRow(List<Data?> cells) {
    return cells.every((cell) => _cellText(cell).trim().isEmpty);
  }
}
