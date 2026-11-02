import 'package:cloud_firestore/cloud_firestore.dart';

class QuestionModel {
  final int questionNo;
  final String title;
  final String question;
  final String topic;
  final String difficulty;
  final String answerType;
  final String correctAnswer;
  final DateTime? createdAt;

  const QuestionModel({
    required this.questionNo,
    required this.title,
    required this.question,
    required this.topic,
    required this.difficulty,
    required this.answerType,
    required this.correctAnswer,
    this.createdAt,
  });

  /// Convert the question into a map for Firestore.
  Map<String, dynamic> toMap() {
    return {
      'questionNo': questionNo,
      'title': title,
      'question': question,
      'topic': topic,
      'difficulty': difficulty,
      'answerType': answerType,
      'correctAnswer': correctAnswer,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
    };
  }

  /// Create a QuestionModel from Firestore data.
  factory QuestionModel.fromMap(Map<String, dynamic> map) {
    final timestamp = map['createdAt'];

    return QuestionModel(
      questionNo: (map['questionNo'] as num?)?.toInt() ?? 0,
      title: map['title'] as String? ?? '',
      question: map['question'] as String? ?? '',
      topic: map['topic'] as String? ?? '',
      difficulty: map['difficulty'] as String? ?? '',
      answerType: map['answerType'] as String? ?? '',
      correctAnswer: map['correctAnswer'] as String? ?? '',
      createdAt: timestamp is Timestamp
          ? timestamp.toDate()
          : timestamp is DateTime
              ? timestamp
              : null,
    );
  }

  /// Create a copy with selected fields changed.
  QuestionModel copyWith({
    int? questionNo,
    String? title,
    String? question,
    String? topic,
    String? difficulty,
    String? answerType,
    String? correctAnswer,
    DateTime? createdAt,
  }) {
    return QuestionModel(
      questionNo: questionNo ?? this.questionNo,
      title: title ?? this.title,
      question: question ?? this.question,
      topic: topic ?? this.topic,
      difficulty: difficulty ?? this.difficulty,
      answerType: answerType ?? this.answerType,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
