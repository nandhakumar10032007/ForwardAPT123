import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Admin uploader for date-wise Daily Questions.
///
/// Excel columns (NO date column):
/// title, question, topic, difficulty, answerType, correctAnswer
///
/// The selected Year + Month + Starting Day determine each question's date.
/// Example: November 2026 + starting day 11:
/// Excel row 1 -> 2026-11-11
/// Excel row 2 -> 2026-11-12
///
/// Firestore:
/// dailyQuestions/{year}/months/{MM}/questions/{yyyy-MM-dd}
///
/// Counter:
/// questionCounters/Daily Question
///   Last_Question_no: number (kept for compatibility)
///   Current_Year: number (kept for compatibility)
///   Year_Sequences: { "2026": 2, "2027": 4 }
///
/// New questionNo examples: D2601, D2602, D2701...
class DailyQuestionUploadScreen extends StatefulWidget {
  const DailyQuestionUploadScreen({super.key});

  @override
  State<DailyQuestionUploadScreen> createState() =>
      _DailyQuestionUploadScreenState();
}

class _DailyQuestionUploadScreenState
    extends State<DailyQuestionUploadScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _yearController =
      TextEditingController(text: DateTime.now().year.toString());
  final TextEditingController _startingDayController =
      TextEditingController(text: '1');

  Uint8List? _excelBytes;
  String? _fileName;

  List<_DailyQuestionDraft> _questions = [];
  final List<String> _errors = [];

  int? _selectedMonth;
  bool _isReading = false;
  bool _isUploading = false;

  static const String _rootCollection = 'dailyQuestions';
  static const String _counterCollection = 'questionCounters';
  static const String _counterDocument = 'Daily Question';

  static const List<String> _months = [
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

  int get _year => int.tryParse(_yearController.text.trim()) ?? 0;
  int get _startingDay =>
      int.tryParse(_startingDayController.text.trim()) ?? 0;

  int get _daysInSelectedMonth {
    if (_year < 1 || _selectedMonth == null) return 0;
    return DateTime(_year, _selectedMonth! + 1, 0).day;
  }

  int get _lastAssignedDay => _startingDay + _questions.length - 1;

  bool get _hasValidSchedule =>
      _year >= 2000 &&
      _year <= 9999 &&
      _selectedMonth != null &&
      _startingDay >= 1 &&
      _startingDay <= _daysInSelectedMonth;

  bool get _isValid =>
      _hasValidSchedule &&
      _questions.isNotEmpty &&
      _errors.isEmpty &&
      _lastAssignedDay <= _daysInSelectedMonth;

  @override
  void dispose() {
    _yearController.dispose();
    _startingDayController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // EXCEL FILE PICKER
  // ---------------------------------------------------------------------------

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
      final bytes = file.bytes;

      if (bytes == null || bytes.isEmpty) {
        _showMessage(
          'Could not read the selected Excel file.',
          isError: true,
        );
        return;
      }

      setState(() {
        _excelBytes = bytes;
        _fileName = file.name;
        _questions.clear();
        _errors.clear();
      });

      await _parseExcel(bytes);
    } catch (e) {
      _showMessage('Excel selection failed: $e', isError: true);
    }
  }

  // ---------------------------------------------------------------------------
  // EXCEL PARSING
  // ---------------------------------------------------------------------------

  Future<void> _parseExcel(Uint8List bytes) async {
    if (!_hasValidSchedule) {
      _showMessage(
        'Enter a valid year, month and starting day first.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isReading = true;
      _questions.clear();
      _errors.clear();
    });

    try {
      final workbook = Excel.decodeBytes(bytes);

      if (workbook.tables.isEmpty) {
        throw const FormatException(
          'The Excel file does not contain a worksheet.',
        );
      }

      final sheet = workbook.tables[workbook.tables.keys.first];

      if (sheet == null || sheet.rows.isEmpty) {
        throw const FormatException('The first worksheet is empty.');
      }

      final headers = sheet.rows.first
          .map((cell) => _normalizeHeader(_cellText(cell)))
          .toList();

      const requiredHeaders = [
        'title',
        'question',
        'topic',
        'difficulty',
        'answertype',
        'correctanswer',
      ];

      for (final header in requiredHeaders) {
        if (!headers.contains(header)) {
          _errors.add('Missing Excel column: $header');
        }
      }

      // A date column is deliberately not accepted/required.
      if (headers.contains('date')) {
        _errors.add(
          'Remove the date column from Excel. Dates are assigned '
          'automatically from the selected starting day.',
        );
      }

      if (_errors.isNotEmpty) return;

      final columnIndexes = <String, int>{};

      for (var i = 0; i < headers.length; i++) {
        if (requiredHeaders.contains(headers[i])) {
          if (columnIndexes.containsKey(headers[i])) {
            _errors.add('Duplicate Excel column: ${headers[i]}');
          } else {
            columnIndexes[headers[i]] = i;
          }
        }
      }

      if (_errors.isNotEmpty) return;

      final parsedQuestions = <_DailyQuestionDraft>[];
      final seenQuestions = <String>{};

      for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
        final cells = sheet.rows[rowIndex];

        if (cells.every((cell) => _cellText(cell).trim().isEmpty)) {
          continue;
        }

        String valueOf(String column) {
          final index = columnIndexes[column]!;
          if (index >= cells.length) return '';
          return _cellText(cells[index]).trim();
        }

        final excelRow = rowIndex + 1;
        final title = valueOf('title');
        final question = valueOf('question');
        final topic = valueOf('topic');
        final difficulty = _canonicalDifficulty(valueOf('difficulty'));
        final answerType = _canonicalAnswerType(valueOf('answertype'));
        final correctAnswer = valueOf('correctanswer');

        if (title.isEmpty ||
            question.isEmpty ||
            topic.isEmpty ||
            correctAnswer.isEmpty) {
          _errors.add(
            'Excel row $excelRow: title, question, topic and '
            'correctAnswer must not be empty.',
          );
          continue;
        }

        if (!['Easy', 'Medium', 'Hard'].contains(difficulty)) {
          _errors.add(
            'Excel row $excelRow: difficulty must be Easy, Medium or Hard.',
          );
          continue;
        }

        if (![
          'Integer',
          'Decimal',
          'Fraction',
          'Percentage',
          'Radio',
        ].contains(answerType)) {
          _errors.add(
            'Excel row $excelRow: invalid answerType "$answerType".',
          );
          continue;
        }

        final normalizedQuestion = question
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        if (!seenQuestions.add(normalizedQuestion)) {
          _errors.add(
            'Excel row $excelRow: duplicate question text in this file.',
          );
          continue;
        }

        parsedQuestions.add(
          _DailyQuestionDraft(
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

      if (parsedQuestions.isEmpty && _errors.isEmpty) {
        _errors.add('No questions were found in the worksheet.');
      }

      final finalDay = _startingDay + parsedQuestions.length - 1;

      if (finalDay > _daysInSelectedMonth) {
        _errors.add(
          'This upload assigns dates $_startingDay to $finalDay, '
          'but ${_months[_selectedMonth! - 1]} $_year has only '
          '$_daysInSelectedMonth days. Reduce the question count '
          'or choose a later starting day.',
        );
      }

      if (!mounted) return;

      setState(() {
        _questions = parsedQuestions;
      });
    } catch (e) {
      _errors.add('Could not read the Excel file: $e');
    } finally {
      if (mounted) {
        setState(() => _isReading = false);
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
    case 'ratio':
      return 'Radio';

    default:
      return value.trim();
  }
}

  // ---------------------------------------------------------------------------
  // DATE AND QUESTION NUMBER HELPERS
  // ---------------------------------------------------------------------------

  DateTime _dateForQuestionIndex(int index) {
    return DateTime(_year, _selectedMonth!, _startingDay + index);
  }

  String _dateId(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _makeQuestionNo(int year, int sequence) {
    final yearCode = (year % 100).toString().padLeft(2, '0');
    final sequenceCode = sequence.toString().padLeft(2, '0');
    return 'D$yearCode$sequenceCode';
  }

  DateTime _indiaNow() {
    return DateTime.now().toUtc().add(
          const Duration(hours: 5, minutes: 30),
        );
  }

  // ---------------------------------------------------------------------------
  // CONFIRM UPLOAD
  // ---------------------------------------------------------------------------

  Future<void> _confirmUpload() async {
    if (!_isValid || _isUploading) {
      _showMessage(
        'Please correct all validation errors before uploading.',
        isError: true,
      );
      return;
    }

    final endDay = _startingDay + _questions.length - 1;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Daily Questions Upload'),
          content: Text(
            'Upload ${_questions.length} questions for '
            '${_months[_selectedMonth! - 1]} $_year?\n\n'
            'Assigned dates: $_startingDay to $endDay.\n\n'
            'Existing dates will be updated. New dates will be added. '
            'Dates outside this upload range will remain untouched.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Upload'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await _uploadQuestions();
    }
  }

  // ---------------------------------------------------------------------------
  // FIRESTORE TRANSACTION
  // ---------------------------------------------------------------------------

  Future<void> _uploadQuestions() async {
    if (!_isValid || _isUploading) return;

    setState(() => _isUploading = true);

    try {
      final year = _year;
      final month = _selectedMonth!;
      final yearId = year.toString();
      final monthId = month.toString().padLeft(2, '0');

      final yearRef = _firestore.collection(_rootCollection).doc(yearId);
      final monthRef = yearRef.collection('months').doc(monthId);
      final questionsCollection = monthRef.collection('questions');
      final counterRef = _firestore
          .collection(_counterCollection)
          .doc(_counterDocument);

      final assignedDates = List<DateTime>.generate(
        _questions.length,
        _dateForQuestionIndex,
      );

      final questionRefs = assignedDates
          .map((date) => questionsCollection.doc(_dateId(date)))
          .toList();

      var addedCount = 0;
      var updatedCount = 0;

      await _firestore.runTransaction<void>((transaction) async {
        // Firestore transaction rule: complete all reads before writes.
        final counterSnapshot = await transaction.get(counterRef);

        final existingSnapshots =
            <DocumentSnapshot<Map<String, dynamic>>>[];

        for (final questionRef in questionRefs) {
          existingSnapshots.add(await transaction.get(questionRef));
        }

        final counterData = counterSnapshot.data() ?? {};

        // Store independent sequences by year so uploading an older year
        // later cannot reset/duplicate another year's question numbers.
        final rawSequences = counterData['Year_Sequences'];
        final yearSequences = <String, dynamic>{};

        if (rawSequences is Map) {
          rawSequences.forEach((key, value) {
            yearSequences[key.toString()] = value;
          });
        }

        var lastNumber =
            (yearSequences[yearId] as num?)?.toInt() ?? 0;

        // Backward compatibility with the original single-year counter.
        final oldCounterYear =
            (counterData['Current_Year'] as num?)?.toInt();
        final oldLastNumber =
            (counterData['Last_Question_no'] as num?)?.toInt() ?? 0;

        if (!yearSequences.containsKey(yearId) &&
            oldCounterYear == year) {
          lastNumber = oldLastNumber;
        }

        final nowIndia = _indiaNow();
        final today = DateTime(
          nowIndia.year,
          nowIndia.month,
          nowIndia.day,
        );

        final mapsToWrite = <Map<String, dynamic>>[];
        var localAdded = 0;
        var localUpdated = 0;

        for (var i = 0; i < _questions.length; i++) {
          final draft = _questions[i];
          final date = assignedDates[i];
          final existing = existingSnapshots[i];

          late final String questionNo;

          if (existing.exists) {
            final oldData = existing.data() ?? {};
            final oldQuestionNo = oldData['questionNo'];

            if (oldQuestionNo is String && oldQuestionNo.isNotEmpty) {
              // Keep the ID stable when correcting/re-uploading a date.
              questionNo = oldQuestionNo;
            } else {
              lastNumber++;
              questionNo = _makeQuestionNo(year, lastNumber);
            }
            localUpdated++;
          } else {
            lastNumber++;
            questionNo = _makeQuestionNo(year, lastNumber);
            localAdded++;
          }

          // Store date as UTC midnight to represent a date-only value
          // consistently, independent of the admin device timezone.
          final dateTimestamp = Timestamp.fromDate(
            DateTime.utc(date.year, date.month, date.day),
          );

          final dateOnly = DateTime(date.year, date.month, date.day);
          final status = dateOnly.isAfter(today) ? 'Coming' : 'Completed';

          final oldData = existing.data() ?? {};

          mapsToWrite.add({
            'questionNo': questionNo,
            'title': draft.title,
            'question': draft.question,
            'topic': draft.topic,
            'difficulty': draft.difficulty,
            'answerType': draft.answerType,
            'correctAnswer': draft.correctAnswer,
            'date': dateTimestamp,
            'status': status,
            'createdAt': existing.exists
                ? (oldData['createdAt'] ?? FieldValue.serverTimestamp())
                : FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        // Update year-specific counter map and legacy counter fields.
        yearSequences[yearId] = lastNumber;

        transaction.set(
          yearRef,
          {
            'year': year,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        transaction.set(
          monthRef,
          {
            'month': month,
            'monthName': _months[month - 1],
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        for (var i = 0; i < questionRefs.length; i++) {
          transaction.set(
            questionRefs[i],
            mapsToWrite[i],
            SetOptions(merge: true),
          );
        }

        transaction.set(
          counterRef,
          {
            'Current_Year': year,
            'Last_Question_no': lastNumber,
            'Year_Sequences': yearSequences,
            'Updated_At': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        addedCount = localAdded;
        updatedCount = localUpdated;
      });

      if (!mounted) return;

      setState(() {
        _excelBytes = null;
        _fileName = null;
        _questions.clear();
        _errors.clear();
      });

      _showMessage(
        'Daily Questions saved successfully! '
        '$addedCount added, $updatedCount updated.',
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage('Daily Questions upload failed: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Question Upload'),
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
              _buildScheduleCard(),
              const SizedBox(height: 16),
              _buildExcelCard(),
              if (_isReading) ...[
                const SizedBox(height: 16),
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
              ],
              if (_excelBytes != null && !_isReading) ...[
                const SizedBox(height: 16),
                _buildValidationCard(),
                const SizedBox(height: 16),
                _buildQuestionPreview(),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _isValid && !_isUploading
                      ? _confirmUpload
                      : null,
                  icon: _isUploading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    _isUploading
                        ? 'Uploading Daily Questions...'
                        : 'Upload ${_questions.length} Daily Questions',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isUploading || _isReading
                      ? null
                      : _selectExcelFile,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Choose Another Excel File'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.calendar_month_rounded,
              size: 42,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Upload Daily Questions',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select a year, month and starting day. Dates are assigned '
              'automatically in Excel row order.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Automatic question numbers: D2601, D2602, D2603...',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Question Schedule',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _yearController,
              enabled: !_isUploading,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Year',
                hintText: 'Example: 2026',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_today),
              ),
              onChanged: (_) => _clearSelectedFile(),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              value: _selectedMonth,
              decoration: const InputDecoration(
                labelText: 'Month',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_month),
              ),
              items: List.generate(
                12,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text(_months[index]),
                ),
              ),
              onChanged: _isUploading
                  ? null
                  : (value) {
                      setState(() {
                        _selectedMonth = value;
                        _excelBytes = null;
                        _fileName = null;
                        _questions.clear();
                        _errors.clear();
                      });
                    },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _startingDayController,
              enabled: !_isUploading,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Starting Day',
                hintText: 'Example: 1 or 11',
                helperText:
                    'First Excel question is assigned to this day.',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.event),
              ),
              onChanged: (_) => _clearSelectedFile(),
            ),
            if (_selectedMonth != null && _year >= 2000) ...[
              const SizedBox(height: 10),
              Text(
                '${_months[_selectedMonth! - 1]} $_year has '
                '$_daysInSelectedMonth days.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _clearSelectedFile() {
    setState(() {
      _excelBytes = null;
      _fileName = null;
      _questions.clear();
      _errors.clear();
    });
  }

  Widget _buildExcelCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Daily Questions Excel File',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Required columns: title, question, topic, difficulty, '
              'answerType, correctAnswer',
            ),
            const SizedBox(height: 6),
            const Text(
              'Do not add a date column. The selected starting day '
              'assigns dates automatically.',
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
              onPressed: _isUploading ||
                      _isReading ||
                      !_hasValidSchedule
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

  Widget _buildValidationCard() {
    final valid = _errors.isEmpty && _questions.isNotEmpty;
    final endDay = _startingDay + _questions.length - 1;

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
            const SizedBox(height: 10),
            Text('Questions found: ${_questions.length}'),
            if (_questions.isNotEmpty)
              Text(
                'Assigned date range: '
                '${_dateId(DateTime(_year, _selectedMonth!, _startingDay))}'
                ' to '
                '${_dateId(DateTime(_year, _selectedMonth!, endDay))}',
              ),
            if (_errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._errors.map(
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
                'Existing dates will be updated with their original '
                'question numbers. New dates receive new question numbers. '
                'Dates outside this upload range will not be changed.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Question Preview',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ...List.generate(_questions.length, (index) {
          final question = _questions[index];
          final assignedDate = _dateForQuestionIndex(index);

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
                          'Question ${index + 1}  •  ${_dateId(assignedDate)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
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
                    style: const TextStyle(fontWeight: FontWeight.w500),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

  void _showMessage(String message, {bool isError = false}) {
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
}

class _DailyQuestionDraft {
  final int excelRow;
  final String title;
  final String question;
  final String topic;
  final String difficulty;
  final String answerType;
  final String correctAnswer;

  const _DailyQuestionDraft({
    required this.excelRow,
    required this.title,
    required this.question,
    required this.topic,
    required this.difficulty,
    required this.answerType,
    required this.correctAnswer,
  });
}
