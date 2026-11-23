import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Generates the original contest leaderboard exactly once.
///
/// Generation is initiated only by an admin opening the leaderboard after
/// End_Time. All rank documents and the completion metadata are committed in
/// one Firestore batch, so the generation is all-or-nothing.
class ContestLeaderboardService {
  ContestLeaderboardService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<void> generateIfNeeded(String contestId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw Exception('Please sign in to continue.');
    }

    final contestRef = _db.collection('Contest_Questions').doc(contestId);
    final contestSnap = await contestRef.get();

    if (!contestSnap.exists) {
      throw Exception('Contest not found.');
    }

    final endTime = contestSnap.data()?['End_Time'];
    if (endTime is! Timestamp) {
      throw Exception('Contest End_Time is invalid.');
    }

    // UI-side check only. Firestore rules must independently enforce End_Time
    // using request.time.
    if (DateTime.now().isBefore(endTime.toDate())) {
      throw Exception('Leaderboard is not available until the contest ends.');
    }

    final rankCollection = contestRef.collection('Rank');
    final metadataRef = rankCollection.doc('_metadata');

    final existingRankDocs = await rankCollection.get();
    final existingMetadata = existingRankDocs.docs
        .where((doc) => doc.id == '_metadata')
        .toList();

    if (existingMetadata.isNotEmpty &&
        existingMetadata.first.data()['Generation_Complete'] == true) {
      return;
    }

    // Rank documents are immutable. If an older/failed implementation left
    // partial rank documents without metadata, do not overwrite them.
    final existingParticipantRanks =
        existingRankDocs.docs.where((doc) => doc.id != '_metadata').toList();

    if (existingParticipantRanks.isNotEmpty) {
      throw Exception(
        'Some rank documents already exist, but generation is incomplete. '
        'To protect the original results, an admin must inspect and clear '
        'the incomplete Rank collection before generating again.',
      );
    }

    final registeredSnapshot =
        await contestRef.collection('Registered').get();

    final participants = <Map<String, dynamic>>[];

    for (final registrationDoc in registeredSnapshot.docs) {
      final registration = registrationDoc.data();

      final summarySnap = await registrationDoc.reference
          .collection('Result')
          .doc('Summary')
          .get();

      if (!summarySnap.exists) {
        throw Exception(
          'Summary is missing for participant ${registrationDoc.id}. '
          'No ranks were created. Check the participant Result/Summary data.',
        );
      }

      final summary = summarySnap.data() ?? <String, dynamic>{};
      final rawScore = summary['Final_Score'];
      final rawLastSubmission = summary['Last_Submission_Time'];

      if (rawScore is! num) {
        throw Exception(
          'Final_Score is missing or invalid for participant '
          '${registrationDoc.id}. No ranks were created.',
        );
      }

      if (rawLastSubmission is! Timestamp) {
        throw Exception(
          'Last_Submission_Time is missing or invalid for participant '
          '${registrationDoc.id}. No ranks were created.',
        );
      }

      final rawName =
          registration['User_Name'] ?? registration['Username'] ?? 'Participant';
      final name = rawName.toString().trim();
      final displayName = name.isEmpty ? 'Participant' : name;

      // The Registered document ID is the authoritative Firebase UID and
      // must match the Rank document ID.
      final participantUid = registrationDoc.id;

      participants.add({
        'uid': participantUid,
        'Username': displayName,
        'Username_Search': displayName.toLowerCase(),
        'User_ID': participantUid,
        'Score': rawScore.toDouble(),
        'Last_Submission_Time': rawLastSubmission,
      });
    }

    participants.sort((a, b) {
      final scoreOrder =
          (b['Score'] as double).compareTo(a['Score'] as double);
      if (scoreOrder != 0) return scoreOrder;

      final timeA =
          (a['Last_Submission_Time'] as Timestamp).millisecondsSinceEpoch;
      final timeB =
          (b['Last_Submission_Time'] as Timestamp).millisecondsSinceEpoch;
      final timeOrder = timeA.compareTo(timeB);
      if (timeOrder != 0) return timeOrder;

      return (a['User_ID'] as String)
          .toLowerCase()
          .compareTo((b['User_ID'] as String).toLowerCase());
    });

    // Firestore permits at most 500 writes in a batch. One atomic batch is
    // intentionally used so ranks and metadata either all exist or none do.
    // This implementation supports up to 499 registered participants.
    if (participants.length > 499) {
      throw Exception(
        'This contest has ${participants.length} participants. '
        'The one-time atomic leaderboard generation supports up to 499. '
        'A paginated immutable-generation design is required for larger contests.',
      );
    }

    final batch = _db.batch();

    for (var index = 0; index < participants.length; index++) {
      final participant = participants[index];
      final participantUid = participant['uid'] as String;

      batch.set(rankCollection.doc(participantUid), {
        'Username': participant['Username'],
        'Username_Search': participant['Username_Search'],
        'User_ID': participant['User_ID'],
        'Score': participant['Score'],
        'Last_Submission_Time': participant['Last_Submission_Time'],
        'Rank': index + 1,
      });
    }

    // Commit metadata in the same batch as rank documents. If any write is
    // rejected, Firestore commits neither the ranks nor the metadata.
    batch.set(metadataRef, {
      'Generation_Complete': true,
      'Generated_At': FieldValue.serverTimestamp(),
      'Participant_Count': participants.length,
      'Contest_ID': contestId,
    });

    await batch.commit();
  }
}

class ContestLeaderboardScreen extends StatefulWidget {
  final String contestId;

  /// Practice mode can only view an already-generated leaderboard.
  /// It never triggers rank generation or modifies Rank documents.
  final bool isPracticeMode;

  const ContestLeaderboardScreen({
    super.key,
    required this.contestId,
    this.isPracticeMode = false,
  });

  @override
  State<ContestLeaderboardScreen> createState() =>
      _ContestLeaderboardScreenState();
}

class _ContestLeaderboardScreenState
    extends State<ContestLeaderboardScreen> {
  static const _bg = Color(0xFFF7F8FC);
  static const _text = Color(0xFF171923);
  static const _muted = Color(0xFF777A87);
  static const _purple = Color(0xFF4F46E5);
  static const _gold = Color(0xFFD69E2E);
  static const _green = Color(0xFF16A34A);

  final ContestLeaderboardService _service = ContestLeaderboardService();
  final TextEditingController _search = TextEditingController();

  DateTime? _endTime;
  Duration _remaining = Duration.zero;
  Timer? _timer;

  bool _loading = true;
  bool _generating = false;
  String? _error;
  String _query = '';

  DocumentReference<Map<String, dynamic>> get _contestRef =>
      FirebaseFirestore.instance
          .collection('Contest_Questions')
          .doc(widget.contestId);

  CollectionReference<Map<String, dynamic>> get _rankRef =>
      _contestRef.collection('Rank');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadContest();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadContest() async {
    try {
      final contestSnap = await _contestRef.get();

      if (!mounted) return;

      final value = contestSnap.data()?['End_Time'];
      if (!contestSnap.exists || value is! Timestamp) {
        setState(() {
          _loading = false;
          _error = 'Contest or End_Time not found.';
        });
        return;
      }

      _endTime = value.toDate();

      setState(() {
        _loading = false;
        _remaining = _endTime!.difference(DateTime.now());
      });

      _startTimer();

      // Any signed-in user can trigger one-time generation after the contest.
      // Practice mode remains strictly read-only.
      if (!_isBeforeEnd && !widget.isPracticeMode) {
        await _generateIfEnded();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load contest details: $e';
      });
    }
  }

  bool get _isBeforeEnd =>
      _endTime != null && DateTime.now().isBefore(_endTime!);

  void _startTimer() {
    _timer?.cancel();

    if (!_isBeforeEnd) return;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _endTime == null) return;

      final left = _endTime!.difference(DateTime.now());
      setState(() {
        _remaining = left.isNegative ? Duration.zero : left;
      });

      if (left <= Duration.zero) {
        _timer?.cancel();
        if (!widget.isPracticeMode) {
          _generateIfEnded();
        }
      }
    });
  }

  Future<void> _generateIfEnded() async {
    // Historical practice views are strictly read-only.
    if (widget.isPracticeMode) return;
    if (_uid == null) return;
    if (_endTime == null || _isBeforeEnd || _generating) return;

    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      await _service.generateIfNeeded(widget.contestId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _generating = false;
        });
      }
    }
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  Widget _countdown() {
    final parts = [
      [_remaining.inDays.toString(), 'Days'],
      [_two(_remaining.inHours.remainder(24)), 'Hours'],
      [_two(_remaining.inMinutes.remainder(60)), 'Minutes'],
      [_two(_remaining.inSeconds.remainder(60)), 'Seconds'],
    ];

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7E8EE)),
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events_rounded, color: _gold, size: 44),
          const SizedBox(height: 12),
          const Text(
            'Leaderboard Appears In',
            style: TextStyle(
              color: _text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: parts
                .map(
                  (part) => Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(
                        vertical: 13,
                        horizontal: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDEBFF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            part[0],
                            style: const TextStyle(
                              color: _purple,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            part[1],
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          const Text(
            'The leaderboard will be available when the contest ends.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedParticipants(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final list = docs.where((doc) => doc.id != '_metadata').toList();

    list.sort(
      (a, b) => ((a.data()['Rank'] as num?)?.toInt() ?? 999999).compareTo(
        (b.data()['Rank'] as num?)?.toInt() ?? 999999,
      ),
    );

    return list;
  }

  Widget _participantTile(Map<String, dynamic> data) {
    final rank = (data['Rank'] as num?)?.toInt() ?? 0;
    final name = (data['Username'] ?? 'Participant').toString();
    final rawCompletionTime = data['Last_Submission_Time'];
    final completionTime = rawCompletionTime is Timestamp
        ? rawCompletionTime.toDate()
        : null;
    final completionTimeText = completionTime == null
        ? 'Completion time unavailable'
        : 'Completed: ${_two(completionTime.hour)}:${_two(completionTime.minute)}:${_two(completionTime.second)}';
    final score = (data['Score'] as num?)?.toDouble() ?? 0.0;

    final color = rank == 1
        ? _gold
        : rank == 2
            ? const Color(0xFF8A929E)
            : rank == 3
                ? const Color(0xFFB77945)
                : _purple;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE7E8EE)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '#$rank',
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  completionTimeText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                score.toStringAsFixed(2),
                style: const TextStyle(
                  color: _purple,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const Text(
                'Score',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _yourRank(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> participants,
  ) {
    QueryDocumentSnapshot<Map<String, dynamic>>? mine;

    for (final doc in participants) {
      if (doc.id == _uid) {
        mine = doc;
        break;
      }
    }

    if (mine == null) return const SizedBox.shrink();

    final data = mine.data();
    final rank = (data['Rank'] as num?)?.toInt() ?? 0;
    final score = (data['Score'] as num?)?.toDouble() ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F7EE),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: _green),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_pin_circle, color: _green, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'YOUR RANK',
                  style: TextStyle(
                    color: _green,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (data['Username'] ?? 'You').toString(),
                  style: const TextStyle(
                    color: _text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Score: ${score.toStringAsFixed(2)}',
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
              ],
            ),
          ),
          Text(
            '#$rank',
            style: const TextStyle(
              color: _green,
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchResults() {
    final query = _query;

    final stream = _rankRef
        .where('Username_Search', isGreaterThanOrEqualTo: query)
        .where(
          'Username_Search',
          isLessThanOrEqualTo: '$query\uf8ff',
        )
        .limit(20)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
            'Search is unavailable right now.',
            style: TextStyle(color: _muted),
          );
        }

        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: CircularProgressIndicator(color: _purple),
            ),
          );
        }

        final results = _sortedParticipants(snapshot.data!.docs);

        if (results.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'No participant found.',
              style: TextStyle(color: _muted),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'SEARCH RESULTS',
              style: TextStyle(color: _text, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...results.map((doc) => _participantTile(doc.data())),
          ],
        );
      },
    );
  }

  Widget _leaderboard(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
  ) {
    final participants = _sortedParticipants(allDocs);
    final topTen = participants.take(10).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Leaderboard 🏆',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _text,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (widget.isPracticeMode) ...[
            const SizedBox(height: 8),
            const Text(
              'PRACTICE MODE • ORIGINAL RANKS',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _purple,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
              ),
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            'Top 10 contest performers',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 14),
          ),
          const SizedBox(height: 20),
          _yourRank(participants),
          TextField(
            controller: _search,
            onChanged: (value) {
              setState(() => _query = value.trim().toLowerCase());
            },
            decoration: InputDecoration(
              hintText: 'Search participant by username',
              prefixIcon: const Icon(Icons.search, color: _muted),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: Color(0xFFE7E8EE)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: Color(0xFFE7E8EE)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: _purple),
              ),
            ),
          ),
          if (_query.isNotEmpty) ...[
            const SizedBox(height: 12),
            _searchResults(),
          ],
          const SizedBox(height: 22),
          const Text(
            'TOP 10',
            style: TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (topTen.isEmpty)
            const Text(
              'No leaderboard entries found.',
              style: TextStyle(color: _muted),
            )
          else
            ...topTen.map((doc) => _participantTile(doc.data())),
        ],
      ),
    );
  }

  Widget _emptyLeaderboardMessage() {
    final message = widget.isPracticeMode
        ? 'Original leaderboard is not available yet.'
        : (_generating
            ? 'Generating the original leaderboard from participant summaries...'
            : 'The leaderboard has not been generated yet. You can try generating it now.');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.emoji_events_outlined,
              size: 48,
              color: Color(0xFFB8B9C4),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (widget.isPracticeMode) ...[
              const SizedBox(height: 7),
              const Text(
                'Practice mode only displays ranks that were already generated. It will not create or change the leaderboard.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 13, height: 1.45),
              ),
            ],
            if (_generating) ...[
              const SizedBox(height: 18),
              const CircularProgressIndicator(color: _purple),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
            if (!widget.isPracticeMode &&
                _uid != null &&
                !_generating &&
                !_isBeforeEnd) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _generateIfEnded,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Generate Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: CircularProgressIndicator(color: _purple),
        ),
      );
    }

    if (_endTime == null) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              _error ?? 'Contest information unavailable.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted),
            ),
          ),
        ),
      );
    }

    if (_isBeforeEnd) {
      return Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                const SizedBox(height: 30),
                _countdown(),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _rankRef.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Unable to load leaderboard: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _muted),
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: _purple),
              );
            }

            final docs = snapshot.data?.docs ?? [];
            final entries = _sortedParticipants(docs);

            if (entries.isNotEmpty) {
              return _leaderboard(docs);
            }

            return _emptyLeaderboardMessage();
          },
        ),
      ),
    );
  }
}
