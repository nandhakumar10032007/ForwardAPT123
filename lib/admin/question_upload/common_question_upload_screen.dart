
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/question_model.dart';
import '../../services/question_import_service.dart';

class CommonQuestionUploadScreen extends StatefulWidget {
  const CommonQuestionUploadScreen({super.key});

  @override
  State<CommonQuestionUploadScreen> createState() =>
      _CommonQuestionUploadScreenState();
}

class _CommonQuestionUploadScreenState
    extends State<CommonQuestionUploadScreen> {
  final QuestionImportService _importService =
      QuestionImportService();

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  Uint8List? _excelBytes;
  String? _fileName;

  QuestionImportResult? _preview;

  bool _isLoading = false;
  bool _isUploading = false;

  static const String _category = 'common';
  static const String _collectionName = 'commonQuestions';

  int get _acceptedCount => _preview?.acceptedCount ?? 0;

  Future<void> _selectExcelFile() async {
    try {
      final result = await FilePicker.pickFiles(
       type: FileType.custom,
       allowedExtensions: const ['xlsx'],
       withData: true,
       allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;
      final bytes = file.bytes;

      if (bytes == null || bytes.isEmpty) {
        _showMessage(
          'Could not read the selected file. Please try again.',
          isError: true,
        );
        return;
      }

      setState(() {
        _excelBytes = bytes;
        _fileName = file.name;
        _preview = null;
      });

      await _generatePreview();
    } catch (e) {
      _showMessage(
        'Could not select the Excel file: $e',
        isError: true,
      );
    }
  }

  Future<void> _generatePreview() async {
    final bytes = _excelBytes;

    if (bytes == null) {
      _showMessage(
        'Please select an Excel file first.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _preview = null;
    });

    try {
      final result = await _importService.previewExcel(
        bytes: bytes,
        category: _category,
      );

      if (!mounted) return;

      setState(() {
        _preview = result;
      });

      if (result.rows.isEmpty) {
        _showMessage(
          'No questions were found in the worksheet.',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'Could not prepare the preview: $e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _confirmUpload() async {
    final preview = _preview;

    if (preview == null || preview.acceptedQuestions.isEmpty) {
      _showMessage(
        'There are no accepted questions to upload.',
        isError: true,
      );
      return;
    }

    if (preview.acceptedQuestions.length > 499) {
      _showMessage(
        'Please upload no more than 499 questions at a time.',
        isError: true,
      );
      return;
    }

    final shouldUpload = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Upload'),
          content: Text(
            'Ready to upload ${preview.acceptedCount} common questions?\n\n'
            'Duplicates: ${preview.duplicateCount}\n'
            'Rejected rows: ${preview.rejectedCount}\n\n'
            'Only accepted questions will be uploaded.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Upload'),
            ),
          ],
        );
      },
    );

    if (shouldUpload != true || !mounted) {
      return;
    }

    await _uploadQuestions();
  }

  /// Saves the questions and advances the global counter atomically.
  ///
  /// The question documents and counter update are committed together.
  /// If the transaction fails, neither the counter nor these documents
  /// are changed.
  ///
  /// The transaction is limited to 499 questions because it also writes
  /// the global counter document.
  Future<void> _uploadQuestions() async {
    final preview = _preview;

    if (preview == null) return;

    final drafts = preview.acceptedQuestions;

    if (drafts.isEmpty) return;

    if (drafts.length > 499) {
      _showMessage(
        'Please upload no more than 499 questions at a time.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      // Recheck the file against current Firestore data immediately
      // before uploading. This also refreshes the preview statuses.
      final bytes = _excelBytes;

      if (bytes == null) {
        throw StateError('The selected Excel file is no longer available.');
      }

      final refreshedPreview = await _importService.previewExcel(
        bytes: bytes,
        category: _category,
      );

      if (!mounted) return;

      setState(() {
        _preview = refreshedPreview;
      });

      final refreshedDrafts = refreshedPreview.acceptedQuestions;

      if (refreshedDrafts.isEmpty) {
        _showMessage(
          'No questions remain to upload. Please check the preview.',
          isError: true,
        );
        return;
      }

      if (refreshedDrafts.length > 499) {
        _showMessage(
          'Please upload no more than 499 questions at a time.',
          isError: true,
        );
        return;
      }

      final counterRef =
          _firestore.collection('questionCounters').doc('global');

      final collectionRef =
          _firestore.collection(_collectionName);

      await _firestore.runTransaction<void>((transaction) async {
        final counterSnapshot = await transaction.get(counterRef);

        final counterData = counterSnapshot.data();
        final storedValue = counterData?['lastQuestionNo'];

        final lastQuestionNo =
            storedValue is num ? storedValue.toInt() : 0;

        final newLastQuestionNo =
            lastQuestionNo + refreshedDrafts.length;

        final questionRefs = <DocumentReference<Map<String, dynamic>>>[];

        final questionsToSave = <QuestionModel>[];

        for (var index = 0;
            index < refreshedDrafts.length;
            index++) {
          final draft = refreshedDrafts[index];
          final questionNo = lastQuestionNo + index + 1;

          final documentRef =
              collectionRef.doc('question_$questionNo');

          questionRefs.add(documentRef);

          questionsToSave.add(
            QuestionModel(
              questionNo: questionNo,
              title: draft.title,
              question: draft.question,
              topic: draft.topic,
              difficulty: draft.difficulty,
              answerType: draft.answerType,
              correctAnswer: draft.correctAnswer,
            ),
          );
        }

        // Check that none of the generated document IDs already exists.
        // All reads must happen before transaction writes.
        for (final documentRef in questionRefs) {
          final existing =
              await transaction.get(documentRef);

          if (existing.exists) {
            throw StateError(
              'A question document already exists at '
              '${documentRef.path}. Please check the global counter.',
            );
          }
        }

        // Reserve the numbers and save all questions in the same
        // transaction, so the counter cannot advance independently.
        transaction.set(
          counterRef,
          {
            'lastQuestionNo': newLastQuestionNo,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        for (var index = 0;
            index < questionsToSave.length;
            index++) {
          transaction.set(
            questionRefs[index],
            questionsToSave[index].toMap(),
          );
        }
      });

      if (!mounted) return;

      final uploadedCount = refreshedDrafts.length;

      setState(() {
        _excelBytes = null;
        _fileName = null;
        _preview = null;
      });

      _showMessage(
        'Successfully uploaded $uploadedCount common questions!',
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'Upload failed: $e',
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
              : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Accepted':
        return Colors.green;

      case 'Duplicate':
        return Colors.orange.shade800;

      case 'Rejected':
        return Colors.red;

      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'Accepted':
        return Icons.check_circle_outline;

      case 'Duplicate':
        return Icons.content_copy;

      case 'Rejected':
        return Icons.error_outline;

      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Common Question Upload'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeaderCard(),

              const SizedBox(height: 20),

              _buildFilePickerCard(),

              const SizedBox(height: 16),

              if (_isLoading)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Reading and validating Excel file...'),
                      ],
                    ),
                  ),
                ),

              if (preview != null && !_isLoading) ...[
                _buildSummaryCards(preview),

                const SizedBox(height: 20),

                _buildPreviewHeading(),

                const SizedBox(height: 10),

                ...preview.rows.map(_buildPreviewRow),

                const SizedBox(height: 24),

                FilledButton.icon(
                  onPressed:
                      _isUploading ? null : _confirmUpload,
                  icon: _isUploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    _isUploading
                        ? 'Uploading Questions...'
                        : 'Upload $_acceptedCount Accepted Questions',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: _isUploading || _isLoading
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
              Icons.library_add_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Upload Common Questions',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Import aptitude questions from an Excel .xlsx file. '
              'Review the validation results before saving them.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePickerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Excel File',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Required columns: title, question, topic, difficulty, '
              'answerType, correctAnswer',
            ),

            const SizedBox(height: 16),

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
              onPressed:
                  _isLoading || _isUploading
                      ? null
                      : _selectExcelFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Select Excel File'),
            ),

            const SizedBox(height: 8),

            OutlinedButton.icon(
              onPressed: _excelBytes == null ||
                      _isLoading ||
                      _isUploading
                  ? null
                  : _generatePreview,
              icon: const Icon(Icons.preview_outlined),
              label: const Text('Generate Preview Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(QuestionImportResult preview) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                title: 'Accepted',
                count: preview.acceptedCount,
                color: Colors.green,
                icon: Icons.check_circle_outline,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _summaryCard(
                title: 'Duplicates',
                count: preview.duplicateCount,
                color: Colors.orange.shade800,
                icon: Icons.content_copy,
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        _summaryCard(
          title: 'Rejected',
          count: preview.rejectedCount,
          color: Colors.red,
          icon: Icons.error_outline,
          fullWidth: true,
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
    bool fullWidth = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 13),
                  ),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewHeading() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Question Preview',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'Review the status and message for each Excel row.',
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(QuestionImportRow row) {
    final statusColor = _statusColor(row.status);

    final draft = row.question;

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
                    'Excel Row ${row.excelRow}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _statusIcon(row.status),
                        color: statusColor,
                        size: 16,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        row.status,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (draft != null) ...[
              const SizedBox(height: 12),

              Text(
                draft.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 6),

              Text(draft.question),

              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _detailChip(draft.topic),
                  _detailChip(draft.difficulty),
                  _detailChip(draft.answerType),
                ],
              ),

              const SizedBox(height: 8),

              Text(
                'Correct answer: ${draft.correctAnswer}',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            const SizedBox(height: 8),

            Text(
              row.message,
              style: TextStyle(
                color: statusColor,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailChip(String text) {
    return Chip(
      label: Text(text),
      visualDensity: VisualDensity.compact,
    );
  }
}
