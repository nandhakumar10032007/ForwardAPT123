
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/question_model.dart';

class QuestionService {
  QuestionService({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Firestore collection names for each question category.
  static const String commonQuestions = 'commonQuestions';
  static const String contestQuestions = 'contestQuestions';
  static const String testQuestions = 'testQuestions';

  /// Returns the Firestore collection reference for a category.
  CollectionReference<Map<String, dynamic>> _collectionFor(
    String category,
  ) {
    switch (category.toLowerCase()) {
      case 'common':
        return _firestore.collection(commonQuestions);

      case 'contest':
        return _firestore.collection(contestQuestions);

      case 'test':
        return _firestore.collection(testQuestions);

      default:
        throw ArgumentError(
          'Unknown question category: $category. '
          'Use common, contest, or test.',
        );
    }
  }

  /// Generates a consistent document ID from the global question number.
  String documentIdFor(int questionNo) {
    if (questionNo < 1) {
      throw ArgumentError.value(
        questionNo,
        'questionNo',
        'Question number must be greater than zero.',
      );
    }

    return 'question_$questionNo';
  }

  /// Saves one question using its globally assigned question number.
  ///
  /// This method does not assign a question number.
  /// The global counter service handles numbering separately.
  Future<void> addQuestion({
    required String category,
    required QuestionModel question,
  }) async {
    if (question.questionNo < 1) {
      throw ArgumentError(
        'The question must have a valid global question number.',
      );
    }

    final collection = _collectionFor(category);
    final documentId = documentIdFor(question.questionNo);
    final documentRef = collection.doc(documentId);

    await _firestore.runTransaction((transaction) async {
      final existingDocument = await transaction.get(documentRef);

      if (existingDocument.exists) {
        throw StateError(
          'Question number ${question.questionNo} already exists '
          'in the $category collection.',
        );
      }

      transaction.set(documentRef, question.toMap());
    });
  }

  /// Saves multiple questions in a single atomic batch.
  ///
  /// Firestore batches allow at most 500 write operations.
  /// This method uses one extra write for each question only,
  /// so the supplied list must contain at most 500 questions.
  ///
  /// The global counter should be reserved separately before calling
  /// this method. For reliable counter-and-question atomicity,
  /// use a coordinated upload transaction for small imports.
  Future<void> addQuestions({
    required String category,
    required List<QuestionModel> questions,
  }) async {
    if (questions.isEmpty) {
      return;
    }

    if (questions.length > 500) {
      throw ArgumentError(
        'A single Firestore batch cannot contain more than 500 writes. '
        'Split larger uploads into smaller batches.',
      );
    }

    final collection = _collectionFor(category);
    final batch = _firestore.batch();

    final seenNumbers = <int>{};

    for (final question in questions) {
      if (question.questionNo < 1) {
        throw ArgumentError(
          'Question numbers must be greater than zero.',
        );
      }

      if (!seenNumbers.add(question.questionNo)) {
        throw ArgumentError(
          'Duplicate question number: ${question.questionNo}.',
        );
      }

      final documentRef =
          collection.doc(documentIdFor(question.questionNo));

      batch.set(documentRef, question.toMap());
    }

    await batch.commit();
  }

  /// Retrieves one question by its global question number.
  Future<QuestionModel?> getQuestionByNumber({
    required String category,
    required int questionNo,
  }) async {
    final documentRef = _collectionFor(category).doc(
      documentIdFor(questionNo),
    );

    final snapshot = await documentRef.get();

    if (!snapshot.exists) {
      return null;
    }

    return QuestionModel.fromMap(snapshot.data()!);
  }

  /// Retrieves all questions in a category, ordered by question number.
  Future<List<QuestionModel>> getQuestions({
    required String category,
  }) async {
    final snapshot = await _collectionFor(category)
        .orderBy('questionNo')
        .get();

    return snapshot.docs
        .map((document) => QuestionModel.fromMap(document.data()))
        .toList();
  }

  /// Streams questions so the UI can update when Firestore changes.
  Stream<List<QuestionModel>> watchQuestions({
    required String category,
  }) {
    return _collectionFor(category)
        .orderBy('questionNo')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (document) =>
                    QuestionModel.fromMap(document.data()),
              )
              .toList(),
        );
  }

  /// Deletes a question by its global question number.
  ///
  /// Deleting a question does not decrease or reset the global counter.
  Future<void> deleteQuestion({
    required String category,
    required int questionNo,
  }) async {
    await _collectionFor(category)
        .doc(documentIdFor(questionNo))
        .delete();
  }

  /// Counts the questions currently stored in a category.
  Future<int> getQuestionCount({
    required String category,
  }) async {
    final snapshot = await _collectionFor(category).count().get();

    return snapshot.count ?? 0;
  }
}
