
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ContestResult extends StatelessWidget {
  final String contestId;

  const ContestResult({
    super.key,
    required this.contestId,
  });

  // ForwardAPT theme
  static const Color _background = Color(0xFFF7F8FC);
  static const Color _text = Color(0xFF171923);
  static const Color _muted = Color(0xFF777A87);
  static const Color _border = Color(0xFFE7E8EE);
  static const Color _primary = Color(0xFF4F46E5);

  // Result colors
  static const Color _marksColor = Color(0xFF38BDF8);
  static const Color _penaltyColor = Color(0xFFEF4444);
  static const Color _bonusColor = Color(0xFFD69E2E);
  static const Color _scoreColor = Color(0xFF16A34A);

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String _format(dynamic value) {
    return _number(value).toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: _background,
        body: Center(
          child: Text(
            'Please login to view your contest result.',
            style: TextStyle(color: _text),
          ),
        ),
      );
    }

    final summaryReference = FirebaseFirestore.instance
        .collection('Contest_Questions')
        .doc(contestId)
        .collection('Registered')
        .doc(user.uid)
        .collection('Result')
        .doc('Summary');

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: summaryReference.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: _primary,
                ),
              );
            }

            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Unable to load contest results.',
                  style: TextStyle(color: _muted),
                ),
              );
            }

            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(
                child: Text(
                  'Your contest result is not available yet.',
                  style: TextStyle(color: _muted),
                ),
              );
            }

            final data = snapshot.data!.data() ?? {};

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // HEADER
                  const Text(
                    'Your Contest Results 🏆',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _text,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    'Your performance breakdown',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _muted,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 26),

                  // ROW 1: MARKS
                  _buildMarksSection(data),

                  const SizedBox(height: 20),

                  // ROW 2: PENALTY BREAKDOWN
                  _buildPenaltySection(data),

                  const SizedBox(height: 20),

                  // ROW 3: BONUS MARK
                  _buildBonusSection(data),

                  const SizedBox(height: 20),

                  // ROW 4: YOUR SCORE
                  _buildScoreSection(data),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ROW 1 - MARKS
  Widget _buildMarksSection(Map<String, dynamic> data) {
    return _sectionCard(
      child: _threeColumnRow(
        firstTitle: 'Easy',
        firstValue: _format(data['Easy_Total_Mark']),
        secondTitle: 'Medium',
        secondValue: _format(data['Medium_Total_Mark']),
        thirdTitle: 'Hard',
        thirdValue: _format(data['Hard_Total_Mark']),
        valueColor: _marksColor,
        subtitle: 'Marks',
      ),
    );
  }

  // ROW 2 - PENALTY BREAKDOWN
  Widget _buildPenaltySection(Map<String, dynamic> data) {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Penalty Breakdown',
            style: TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 25),

          _threeColumnRow(
            firstTitle: 'Easy',
            firstValue:
                _format(data['Easy_Total_Penalty_Mark']),
            secondTitle: 'Medium',
            secondValue:
                _format(data['Medium_Total_Penalty_Mark']),
            thirdTitle: 'Hard',
            thirdValue:
                _format(data['Hard_Total_Penalty_Mark']),
            valueColor: _penaltyColor,
            subtitle: 'Penalty',
          ),
        ],
      ),
    );
  }

  // ROW 3 - BONUS MARK
  Widget _buildBonusSection(Map<String, dynamic> data) {
    return _sectionCard(
      child: Column(
        children: [
          const Text(
            'Bonus Mark',
            style: TextStyle(
              color: _bonusColor,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            '+${_format(data['Bonus_Point'])}',
            style: const TextStyle(
              color: _bonusColor,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  // ROW 4 - YOUR SCORE
  Widget _buildScoreSection(Map<String, dynamic> data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: 20,
        horizontal: 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F7EE),
        border: Border.all(
          color: _scoreColor,
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Text(
            'YOUR SCORE',
            style: TextStyle(
              color: _scoreColor,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            _format(data['Final_Score']),
            style: const TextStyle(
              color: _scoreColor,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 5),

          const Text(
            'Final contest score',
            style: TextStyle(
              color: _muted,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  // Common white section card.
  Widget _sectionCard({
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 22,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  // Three-column layout.
  Widget _threeColumnRow({
    required String firstTitle,
    required String firstValue,
    required String secondTitle,
    required String secondValue,
    required String thirdTitle,
    required String thirdValue,
    required Color valueColor,
    required String subtitle,
  }) {
    return Row(
      children: [
        Expanded(
          child: _resultItem(
            title: firstTitle,
            value: firstValue,
            valueColor: valueColor,
            subtitle: subtitle,
          ),
        ),

        Expanded(
          child: _resultItem(
            title: secondTitle,
            value: secondValue,
            valueColor: valueColor,
            subtitle: subtitle,
          ),
        ),

        Expanded(
          child: _resultItem(
            title: thirdTitle,
            value: thirdValue,
            valueColor: valueColor,
            subtitle: subtitle,
          ),
        ),
      ],
    );
  }

  // Individual result item.
  Widget _resultItem({
    required String title,
    required String value,
    required Color valueColor,
    required String subtitle,
  }) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: subtitle == 'Marks'
                ? _marksColor
                : _muted,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 10),

        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: valueColor,
            fontSize: 23,
            fontWeight: FontWeight.w900,
          ),
        ),

        const SizedBox(height: 5),

        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _muted,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}
