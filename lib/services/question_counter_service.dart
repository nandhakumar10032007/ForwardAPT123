import 'package:cloud_firestore/cloud_firestore.dart';

class QuestionCounterService {
  QuestionCounterService({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// The single global counter shared by every question category.
  DocumentReference<Map<String, dynamic>> get _counterRef =>
      _firestore.collection('questionCounters').doc('global');

  /// Returns the last assigned global question number.
  ///
  /// If the counter document does not exist yet, the initial value is 0.
  Future<int> getLastQuestionNo() async {
    final snapshot = await _counterRef.get();

    if (!snapshot.exists) {
      return 0;
    }

    final data = snapshot.data();
    final value = data?['lastQuestionNo'];

    if (value is num) {
      return value.toInt();
    }

    return 0;
  }

  /// Reserves a consecutive range of global question numbers.
  ///
  /// Example:
  /// If the last number is 100 and count is 5,
  /// the returned numbers will be [101, 102, 103, 104, 105].
  ///
  /// The transaction prevents two simultaneous uploads from
  /// reserving overlapping ranges.
  Future<List<int>> reserveQuestionNumbers(int count) async {
    if (count < 1) {
      throw ArgumentError.value(
        count,
        'count',
        'Count must be at least 1.',
      );
    }

    return _firestore.runTransaction<List<int>>((transaction) async {
      final snapshot = await transaction.get(_counterRef);

      final data = snapshot.data();
      final currentValue = data?['lastQuestionNo'];

      final lastQuestionNo =
          currentValue is num ? currentValue.toInt() : 0;

      final newLastQuestionNo = lastQuestionNo + count;

      transaction.set(
        _counterRef,
        {
          'lastQuestionNo': newLastQuestionNo,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return List<int>.generate(
        count,
        (index) => lastQuestionNo + index + 1,
      );
    });
  }
}
