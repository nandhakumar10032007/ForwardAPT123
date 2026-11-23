
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../Topics.dart';
import '../../services/answer_type_service.dart';

class ContestQuestionUploadScreen extends StatefulWidget {
  const ContestQuestionUploadScreen({super.key});

  @override
  State<ContestQuestionUploadScreen> createState() =>
      _ContestQuestionUploadScreenState();
}

class _ContestQuestionUploadScreenState
    extends State<ContestQuestionUploadScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Uint8List? _excelBytes;
  String? _fileName;

  List<_ContestQuestionDraft> _questions = [];
  List<String> _topics = [];
  List<String> _validationErrors = [];

  bool _isReading = false;
  bool _isUploading = false;

  static const String _contestCollection = 'Contest_Questions';
  static const String _counterCollection = 'questionCounters';
  static const String _counterDocument = 'Contest';

  static const Duration _indiaOffset = Duration(hours: 5, minutes: 30);

  int get _easyCount =>
      _questions.where((q) => q.difficulty == 'Easy').length;

  int get _mediumCount =>
      _questions.where((q) => q.difficulty == 'Medium').length;

  int get _hardCount =>
      _questions.where((q) => q.difficulty == 'Hard').length;

  bool get _isValid =>
      _questions.length == 13 &&
      _easyCount == 5 &&
      _mediumCount == 5 &&
      _hardCount == 3 &&
      _validationErrors.isEmpty &&
      _topics.isNotEmpty;

  // ============================================================
  // TOPIC SELECTION
  // ============================================================

  void _toggleTopic(String topic, bool selected) {
    if (_isUploading) return;

    setState(() {
      if (selected) {
        if (!_topics.contains(topic)) _topics.add(topic);
      } else {
        _topics.remove(topic);
      }
      _questions.clear();
      _validationErrors.clear();
    });

    if (_excelBytes != null) {
      _parseExcel(_excelBytes!);
    }
  }

  // ============================================================
  // EXCEL FILE PICKER
  // ============================================================

  Future<void> _selectExcelFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;

      if (file.bytes == null || file.bytes!.isEmpty) {
        _showMessage(
          'Could not read the selected Excel file.',
          isError: true,
        );
        return;
      }

      setState(() {
        _excelBytes = file.bytes;
        _fileName = file.name;
        _questions.clear();
        _validationErrors.clear();
      });

      await _parseExcel(file.bytes!);
    } catch (e) {
      _showMessage(
        'Excel selection failed: $e',
        isError: true,
      );
    }
  }

  // ============================================================
  // EXCEL PARSING AND VALIDATION
  // ============================================================

  Future<void> _parseExcel(Uint8List bytes) async {
    if (!mounted) return;

    setState(() {
      _isReading = true;
      _questions.clear();
      _validationErrors.clear();
    });

    try {
      if (_topics.isEmpty) {
        _validationErrors.add(
          'Select the contest topics before validating the Excel file.',
        );
        return;
      }

      final workbook = Excel.decodeBytes(bytes);

      if (workbook.tables.isEmpty) {
        throw const FormatException(
          'The Excel file does not contain a worksheet.',
        );
      }

      final sheet = workbook.tables[workbook.tables.keys.first];

      if (sheet == null || sheet.rows.isEmpty) {
        throw const FormatException(
          'The first worksheet is empty.',
        );
      }

      final headers = sheet.rows.first.map((cell) {
        return _normalizeHeader(_cellText(cell));
      }).toList();

      // answerType is intentionally optional for older Excel templates.
      // The app now detects it automatically from correctAnswer.
      const requiredHeaders = [
        'title',
        'question',
        'topic',
        'difficulty',
        'correctanswer',
      ];

      for (final header in requiredHeaders) {
        if (!headers.contains(header)) {
          _validationErrors.add(
            'Missing Excel column: $header',
          );
        }
      }

      if (_validationErrors.isNotEmpty) return;

      final columnIndexes = <String, int>{};

      for (var i = 0; i < headers.length; i++) {
        if (requiredHeaders.contains(headers[i])) {
          if (columnIndexes.containsKey(headers[i])) {
            _validationErrors.add(
              'Duplicate Excel column: ${headers[i]}',
            );
          } else {
            columnIndexes[headers[i]] = i;
          }
        }
      }

      if (_validationErrors.isNotEmpty) return;

      final parsedQuestions = <_ContestQuestionDraft>[];
      final seenQuestions = <String>{};
      final allowedTopics = _topics
          .map((topic) => topic.toLowerCase())
          .toSet();

      for (var rowIndex = 1;
          rowIndex < sheet.rows.length;
          rowIndex++) {
        final cells = sheet.rows[rowIndex];

        if (cells.every(
          (cell) => _cellText(cell).trim().isEmpty,
        )) {
          continue;
        }

        String valueOf(String column) {
          final index = columnIndexes[column]!;

          if (index >= cells.length) return '';

          return _cellText(cells[index]).trim();
        }

        final title = valueOf('title');
        final question = valueOf('question');
        final topicFromExcel = valueOf('topic');
        final topic = _topics.firstWhere(
          (selectedTopic) =>
              selectedTopic.toLowerCase() == topicFromExcel.toLowerCase(),
          orElse: () => topicFromExcel,
        );
        final difficulty = _canonicalDifficulty(
          valueOf('difficulty'),
        );
        final correctAnswer = valueOf('correctanswer');
        final answerType = AnswerTypeService.detect(correctAnswer);

        final excelRow = rowIndex + 1;

        if (title.isEmpty ||
            question.isEmpty ||
            topic.isEmpty ||
            correctAnswer.isEmpty) {
          _validationErrors.add(
            'Excel row $excelRow: Title, question, topic, difficulty, and correctAnswer are required.',
          );
          continue;
        }

        if (!allowedTopics.contains(topic.toLowerCase())) {
          _validationErrors.add(
            'Excel row $excelRow: Topic "$topic" is not in the '
            'selected contest topics.',
          );
          continue;
        }

        if (!['Easy', 'Medium', 'Hard'].contains(difficulty)) {
          _validationErrors.add(
            'Excel row $excelRow: Difficulty must be Easy, Medium, or Hard.',
          );
          continue;
        }

        if (answerType == null) {
          _validationErrors.add(
            'Excel row $excelRow: Could not detect the answer type from '
            '"$correctAnswer". Use a supported format such as 25, 12.5, '
            '3/4, 25%, 2:3, 2^3, or √5.',
          );
          continue;
        }

        final answerError = AnswerTypeService.validationError(
          answer: correctAnswer,
          expectedType: answerType,
        );
        if (answerError != null) {
          _validationErrors.add(
            'Excel row $excelRow: $answerError',
          );
          continue;
        }

        final questionKey = question
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ');

        if (!seenQuestions.add(questionKey)) {
          _validationErrors.add(
            'Excel row $excelRow: Duplicate question in this file.',
          );
          continue;
        }

        parsedQuestions.add(
          _ContestQuestionDraft(
            excelRow: excelRow,
            title: title,
            question: question,
            topic: topic,
            difficulty: difficulty,
            answerType: answerType,
            correctAnswer: correctAnswer,
          ),
        );
      }

      if (parsedQuestions.length != 13) {
        _validationErrors.add(
          'Exactly 13 valid questions are required. '
          'Found ${parsedQuestions.length}.',
        );
      }

      final easy = parsedQuestions
          .where((q) => q.difficulty == 'Easy')
          .length;

      final medium = parsedQuestions
          .where((q) => q.difficulty == 'Medium')
          .length;

      final hard = parsedQuestions
          .where((q) => q.difficulty == 'Hard')
          .length;

      if (easy != 5) {
        _validationErrors.add(
          'Easy questions must be exactly 5. Found $easy.',
        );
      }

      if (medium != 5) {
        _validationErrors.add(
          'Medium questions must be exactly 5. Found $medium.',
        );
      }

      if (hard != 3) {
        _validationErrors.add(
          'Hard questions must be exactly 3. Found $hard.',
        );
      }

      if (!mounted) return;

      setState(() {
        _questions = parsedQuestions;
      });
    } catch (e) {
      _validationErrors.add(
        'Could not read the Excel file: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isReading = false;
        });
      }
    }
  }

  String _normalizeHeader(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_-]+'), '');
  }

  String _cellText(Data? cell) {
    if (cell == null || cell.value == null) return '';
    return cell.value.toString();
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


  // ============================================================
  // CONTEST SCHEDULING - INDIA TIME
  // ============================================================

  DateTime _indiaNow() {
    return DateTime.now().toUtc().add(_indiaOffset);
  }

  DateTime _nextSaturdayAt630(DateTime indiaNow) {
    final daysUntilSaturday =
        (DateTime.saturday - indiaNow.weekday + 7) % 7;

    var scheduledDate = DateTime(
      indiaNow.year,
      indiaNow.month,
      indiaNow.day,
    ).add(Duration(days: daysUntilSaturday));

    var startTime = DateTime(
      scheduledDate.year,
      scheduledDate.month,
      scheduledDate.day,
      18,
      30,
    );

    // If it is Saturday at or after 6:30 PM,
    // schedule the following Saturday.
    if (!startTime.isAfter(indiaNow)) {
      scheduledDate = scheduledDate.add(
        const Duration(days: 7),
      );

      startTime = DateTime(
        scheduledDate.year,
        scheduledDate.month,
        scheduledDate.day,
        18,
        30,
      );
    }

    return scheduledDate;
  }

  DateTime _getScheduledDate(
    Map<String, dynamic>? counterData,
  ) {
    final nowIndia = _indiaNow();
    final nextSaturday = _nextSaturdayAt630(nowIndia);

    final lastDateValue = counterData?['Last_Contest_Date'];

    if (lastDateValue is Timestamp) {
      final lastIndia = lastDateValue
          .toDate()
          .toUtc()
          .add(_indiaOffset);

      final nextAfterLast = DateTime(
        lastIndia.year,
        lastIndia.month,
        lastIndia.day,
      ).add(const Duration(days: 7));

      // Keep weekly dates sequential when contests
      // are uploaded in advance. If an old date has
      // passed, use the next available Saturday.
      if (nextAfterLast.isAfter(nextSaturday)) {
        return nextAfterLast;
      }
    }

    return nextSaturday;
  }

  DateTime _indiaDateToUtc(DateTime indiaDate) {
    return DateTime.utc(
      indiaDate.year,
      indiaDate.month,
      indiaDate.day,
    ).subtract(_indiaOffset);
  }

  DateTime _indiaDateTimeToUtc(
    DateTime indiaDate,
    int hour,
    int minute,
  ) {
    return DateTime.utc(
      indiaDate.year,
      indiaDate.month,
      indiaDate.day,
      hour,
      minute,
    ).subtract(_indiaOffset);
  }

  // ============================================================
  // COUNTER HELPERS
  // ============================================================

  int _readCounter(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  // ============================================================
  // CONFIRM UPLOAD
  // ============================================================

  Future<void> _confirmUpload() async {
    if (!_isValid) {
      _showMessage(
        'Please correct all validation errors before uploading.',
        isError: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Create Weekly Contest?'),
          content: const Text(
            'This will create a new Contest ID, schedule it '
            'for Saturday at 6:30 PM IST, and upload all 13 questions.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              child: const Text('Create Contest'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await _uploadContest();
    }
  }

  // ============================================================
  // CREATE CONTEST AND QUESTIONS ATOMICALLY
  // ============================================================

  Future<void> _uploadContest() async {
    if (!_isValid || _isUploading) return;

    setState(() {
      _isUploading = true;
    });

    try {
      final counterRef = _firestore
          .collection(_counterCollection)
          .doc(_counterDocument);

      final contestsRef =
          _firestore.collection(_contestCollection);

      String? createdContestId;
      DateTime? createdContestDate;

      await _firestore.runTransaction<void>(
        (transaction) async {
          // All reads must happen before writes.
          final counterSnapshot =
              await transaction.get(counterRef);

          final counterData = counterSnapshot.data();

          final scheduledDate =
              _getScheduledDate(counterData);

          final contestYear = scheduledDate.year;
          final storedYear = _readCounter(
            counterData?['Current_Year'],
          );

          final lastDateValue =
              counterData?['Last_Contest_Date'];

          final inferredYear = lastDateValue is Timestamp
              ? lastDateValue.toDate().year
              : contestYear;

          final effectiveStoredYear =
              storedYear == 0 ? inferredYear : storedYear;

          // Contest sequence resets each year.
          // Question counters never reset.
          var contestNumber = effectiveStoredYear == contestYear
              ? _readCounter(counterData?['Contest_no'])
              : 0;

          if (contestNumber >= 52) {
            throw StateError(
              'The yearly contest limit of 52 has been reached.',
            );
          }

          contestNumber++;

          final contestId =
              '${(contestYear % 100).toString().padLeft(2, '0')}'
              '${contestNumber.toString().padLeft(2, '0')}';

          final contestRef = contestsRef.doc(contestId);

          final existingContest =
              await transaction.get(contestRef);

          if (existingContest.exists) {
            throw StateError(
              'Contest $contestId already exists. '
              'Please check the Contest counter.',
            );
          }

          var easyNumber =
              _readCounter(counterData?['Easy_Last_no']);
          var mediumNumber =
              _readCounter(counterData?['Medium_Last_no']);
          var hardNumber =
              _readCounter(counterData?['Hard_Last_no']);

          final questionRefs =
              <DocumentReference<Map<String, dynamic>>>[];

          final questionMaps = <Map<String, dynamic>>[];

          final questionIds = <String>[];

          for (final draft in _questions) {
  late String questionId;

  switch (draft.difficulty) {
    case 'Easy':
      easyNumber++;
      questionId = 'E${easyNumber.toString().padLeft(2, '0')}';
      break;

    case 'Medium':
      mediumNumber++;
      questionId = 'M${mediumNumber.toString().padLeft(2, '0')}';
      break;

    case 'Hard':
      hardNumber++;
      questionId = 'H${hardNumber.toString().padLeft(2, '0')}';
      break;

    default:
      throw StateError('Invalid question difficulty.');
  }
            final questionRef = contestRef
                .collection('Questions')
                .doc(questionId);

            questionRefs.add(questionRef);
            questionIds.add(questionId);

           final questionData = <String, dynamic>{
  'questionNo': questionId,
  'title': draft.title,
  'question': draft.question,
  'topic': draft.topic,
  'difficulty': draft.difficulty,
  'answerType': draft.answerType,
  'correctAnswer': draft.correctAnswer,
  'createdAt': FieldValue.serverTimestamp(),
};

questionMaps.add(questionData);
          }

          // Check that all generated question IDs are unused.
          for (final questionRef in questionRefs) {
            final existingQuestion =
                await transaction.get(questionRef);

            if (existingQuestion.exists) {
              throw StateError(
                'Question ${questionRef.id} already exists. '
                'Please verify the question counters.',
              );
            }
          }

          final startUtc = _indiaDateTimeToUtc(
            scheduledDate,
            18,
            30,
          );

          final endUtc = _indiaDateTimeToUtc(
            scheduledDate,
            19,
            0,
          );

          final contestDateUtc =
              _indiaDateToUtc(scheduledDate);

          // Create the contest parent document.
          transaction.set(contestRef, {
            'Contest_ID': contestId,
            'Topics': List<String>.from(_topics),
            'Contest_Date':
                Timestamp.fromDate(contestDateUtc),
            'Start_Time': Timestamp.fromDate(startUtc),
            'End_Time': Timestamp.fromDate(endUtc),
            'Status': 'Upcoming',
            'Duration_Minutes': 30,
            'Question_Count': 13,
            'Easy_Count': 5,
            'Medium_Count': 5,
            'Hard_Count': 3,
            'Created_At': FieldValue.serverTimestamp(),
          });

          // Create the 13 question documents.
          for (var i = 0; i < questionRefs.length; i++) {
            transaction.set(
              questionRefs[i],
              questionMaps[i],
            );
          }

          // Update yearly contest counter and lifetime
          // difficulty counters in the same transaction.
          transaction.set(
            counterRef,
            {
              'Contest_no': contestNumber.toString(),
              'Current_Year': contestYear,
              'Last_Contest_Date':
                  Timestamp.fromDate(contestDateUtc),
              'Easy_Last_no': easyNumber.toString(),
              'Medium_Last_no': mediumNumber.toString(),
              'Hard_Last_no': hardNumber.toString(),
              'Updated_At': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );

          createdContestId = contestId;
          createdContestDate = scheduledDate;
        },
      );

      if (!mounted) return;

      final dateText = _formatDate(createdContestDate!);

      setState(() {
        _excelBytes = null;
        _fileName = null;
        _questions.clear();
        _topics.clear();
        _validationErrors.clear();
      });

      _showMessage(
        'Contest $createdContestId created successfully! '
        'Scheduled for $dateText at 6:30 PM IST.',
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'Contest upload failed: $e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  // ============================================================
  // DATE FORMAT
  // ============================================================

  String _formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return '${weekdays[date.weekday - 1]}, '
        '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? Theme.of(context).colorScheme.error
              : const Color(0xFF15803D),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ============================================================
  // MAIN UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contest Question Upload'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeaderCard(),
              const SizedBox(height: 18),
              _buildTopicsCard(),
              const SizedBox(height: 16),
              _buildExcelCard(),
              const SizedBox(height: 16),

              if (_isReading)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 14),
                        Text('Reading and validating Excel...'),
                      ],
                    ),
                  ),
                ),

              if (_excelBytes != null && !_isReading) ...[
                _buildQuestionSummary(),
                const SizedBox(height: 16),
                _buildValidationCard(),
                const SizedBox(height: 16),
                _buildQuestionPreview(),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed:
                      _isValid && !_isUploading
                          ? _confirmUpload
                          : null,
                  icon: _isUploading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    _isUploading
                        ? 'Creating Contest...'
                        : 'Create Weekly Contest',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // HEADER CARD
  // ============================================================

  Widget _buildHeaderCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.emoji_events_rounded,
              size: 42,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Create Weekly Contest',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter the contest topics and upload one Excel '
              'file containing 13 questions. The Contest ID '
              'and Saturday schedule will be generated automatically.',
            ),
            const SizedBox(height: 14),
            const Row(
              children: [
                Icon(Icons.calendar_month_outlined, size: 19),
                SizedBox(width: 8),
                Text(
                  'Every Saturday',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(width: 18),
                Icon(Icons.access_time, size: 19),
                SizedBox(width: 8),
                Text(
                  '6:30 PM – 7:00 PM IST',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TOPICS CARD
  // ============================================================

  Widget _buildTopicsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Contest Topics',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose one or more topics from the master topic list. '
              'Each Excel question must use one of the selected topics.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: Topics.all.map((topic) {
                final selected = _topics.contains(topic);
                return FilterChip(
                  label: Text(topic),
                  selected: selected,
                  onSelected: _isUploading
                      ? null
                      : (value) => _toggleTopic(topic, value),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Text(
              '${_topics.length} topic${_topics.length == 1 ? '' : 's'} selected',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_topics.isEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Select at least one topic before validating the Excel file.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // EXCEL CARD
  // ============================================================

  Widget _buildExcelCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Contest Excel File',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Required columns: title, question, topic, difficulty, '
              'correctAnswer. The answerType is detected automatically. '
              'An old answerType column may remain in your Excel file; it is ignored.',
            ),
            const SizedBox(height: 14),
            if (_fileName != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _fileName!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _isUploading || _isReading
                  ? null
                  : _selectExcelFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Select Excel File'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _excelBytes == null ||
                      _isUploading ||
                      _isReading
                  ? null
                  : () => _parseExcel(_excelBytes!),
              icon: const Icon(Icons.refresh),
              label: const Text('Validate Excel Again'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // QUESTION SUMMARY
  // ============================================================

  Widget _buildQuestionSummary() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Question Distribution',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _countCard(
                    'Easy',
                    _easyCount,
                    5,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _countCard(
                    'Medium',
                    _mediumCount,
                    5,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _countCard(
                    'Hard',
                    _hardCount,
                    3,
                    Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Total: ${_questions.length} / 13 questions',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countCard(
    String title,
    int count,
    int required,
    Color color,
  ) {
    final correct = count == required;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 12,
        horizontal: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$count / $required',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: correct ? Colors.green : color,
            ),
          ),
          Icon(
            correct ? Icons.check_circle : Icons.info_outline,
            color: correct ? Colors.green : color,
            size: 17,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // VALIDATION CARD
  // ============================================================

  Widget _buildValidationCard() {
    final valid = _isValid;

    return Card(
      color: valid
          ? Colors.green.withValues(alpha: 0.06)
          : Colors.red.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  valid ? Icons.check_circle : Icons.error_outline,
                  color: valid ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    valid
                        ? 'Excel validation successful'
                        : 'Validation needs attention',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: valid ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            if (_validationErrors.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._validationErrors.map(
                (error) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(
                        child: Text(
                          error,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (valid) ...[
              const SizedBox(height: 8),
              const Text(
                'All 13 questions and their difficulty distribution '
                'are valid. Ready to create the contest.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // QUESTION PREVIEW
  // ============================================================

  Widget _buildQuestionPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Question Preview',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        ..._questions.map((question) {
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Excel Row ${question.excelRow}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _difficultyChip(question.difficulty),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    question.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(question.question),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 5,
                    children: [
                      Chip(label: Text(question.topic)),
                      Chip(label: Text(question.answerType)),
                    ],
                  ),
                  Text(
                    'Correct answer: ${question.correctAnswer}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _difficultyChip(String difficulty) {
    final color = switch (difficulty) {
      'Easy' => Colors.green,
      'Medium' => Colors.orange,
      'Hard' => Colors.red,
      _ => Colors.grey,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        difficulty,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ============================================================
// CONTEST QUESTION DRAFT
// ============================================================

class _ContestQuestionDraft {
  final int excelRow;
  final String title;
  final String question;
  final String topic;
  final String difficulty;
  final String answerType;
  final String correctAnswer;

  const _ContestQuestionDraft({
    required this.excelRow,
    required this.title,
    required this.question,
    required this.topic,
    required this.difficulty,
    required this.answerType,
    required this.correctAnswer,
  });
}
