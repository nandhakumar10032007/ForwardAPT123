import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ContestLeaderboardService {
  ContestLeaderboardService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Future<void> generateIfNeeded(String contestId) async {
    final contest = _db.collection('Contest_Questions').doc(contestId);
    final contestSnap = await contest.get();
    if (!contestSnap.exists) throw Exception('Contest not found.');
    final end = contestSnap.data()?['End_Time'];
    if (end is! Timestamp) throw Exception('Contest End_Time is invalid.');
    if (DateTime.now().isBefore(end.toDate())) {
      throw Exception('Leaderboard is not available until the contest ends.');
    }

    final rankCollection = contest.collection('Rank');
    final metadataRef = rankCollection.doc('_metadata');
    final metadata = await metadataRef.get();
    if (metadata.data()?['Generation_Complete'] == true) return;

    final registered = await contest.collection('Registered').get();
    final participants = await Future.wait(registered.docs.map((doc) async {
      final registration = doc.data();
      final summarySnap = await doc.reference.collection('Result').doc('Summary').get();
      final summary = summarySnap.data() ?? <String, dynamic>{};
      final name = (registration['User_Name'] ?? registration['Username'] ?? 'Participant').toString().trim();
      final userId = (registration['User_ID'] ?? doc.id).toString().trim();
      final rawScore = summary['Final_Score'];
      final score = rawScore is num ? rawScore.toDouble() : double.tryParse('$rawScore') ?? 0.0;
      final rawTime = summary['Last_Submission_Time'];
      final lastTime = rawTime is Timestamp ? rawTime : Timestamp.fromMillisecondsSinceEpoch(0);
      return <String, dynamic>{
        'uid': doc.id,
        'Username': name.isEmpty ? 'Participant' : name,
        'Username_Search': (name.isEmpty ? 'participant' : name).toLowerCase(),
        'User_ID': userId.isEmpty ? doc.id : userId,
        'Score': score,
        'Last_Submission_Time': lastTime,
      };
    }));

    participants.sort((a, b) {
      final scoreOrder = (b['Score'] as double).compareTo(a['Score'] as double);
      if (scoreOrder != 0) return scoreOrder;
      final timeA = (a['Last_Submission_Time'] as Timestamp).millisecondsSinceEpoch;
      final timeB = (b['Last_Submission_Time'] as Timestamp).millisecondsSinceEpoch;
      final timeOrder = timeA.compareTo(timeB);
      if (timeOrder != 0) return timeOrder;
      return (a['User_ID'] as String).toLowerCase().compareTo((b['User_ID'] as String).toLowerCase());
    });

    // Firestore batches support at most 500 writes; use 450 for headroom.
    for (var start = 0; start < participants.length; start += 450) {
      final batch = _db.batch();
      final stop = (start + 450 < participants.length) ? start + 450 : participants.length;
      for (var i = start; i < stop; i++) {
        final p = participants[i];
        batch.set(rankCollection.doc(p['uid'] as String), {
          'Username': p['Username'],
          'Username_Search': p['Username_Search'],
          'User_ID': p['User_ID'],
          'Score': p['Score'],
          'Last_Submission_Time': p['Last_Submission_Time'],
          'Rank': i + 1,
        });
      }
      await batch.commit();
    }

    await metadataRef.set({
      'Generation_Complete': true,
      'Generated_At': FieldValue.serverTimestamp(),
      'Participant_Count': participants.length,
      'Contest_ID': contestId,
    });
  }
}

class ContestLeaderboardScreen extends StatefulWidget {
  final String contestId;
  const ContestLeaderboardScreen({super.key, required this.contestId});

  @override
  State<ContestLeaderboardScreen> createState() => _ContestLeaderboardScreenState();
}

class _ContestLeaderboardScreenState extends State<ContestLeaderboardScreen> {
  static const _bg = Color(0xFFF7F8FC);
  static const _text = Color(0xFF171923);
  static const _muted = Color(0xFF777A87);
  static const _purple = Color(0xFF4F46E5);
  static const _gold = Color(0xFFD69E2E);
  static const _green = Color(0xFF16A34A);

  final _service = ContestLeaderboardService();
  final _search = TextEditingController();
  DateTime? _endTime;
  Duration _remaining = Duration.zero;
  Timer? _timer;
  bool _loading = true;
  bool _generating = false;
  String? _error;
  String _query = '';

  DocumentReference<Map<String, dynamic>> get _contestRef =>
      FirebaseFirestore.instance.collection('Contest_Questions').doc(widget.contestId);
  CollectionReference<Map<String, dynamic>> get _rankRef => _contestRef.collection('Rank');
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
      final snap = await _contestRef.get();
      if (!mounted) return;
      final value = snap.data()?['End_Time'];
      if (!snap.exists || value is! Timestamp) {
        setState(() { _loading = false; _error = 'Contest or End_Time not found.'; });
        return;
      }
      _endTime = value.toDate();
      setState(() {
        _loading = false;
        _remaining = _endTime!.difference(DateTime.now());
      });
      _startTimer();
      _generateIfEnded();
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Unable to load contest details.'; });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _endTime == null) return;
      final left = _endTime!.difference(DateTime.now());
      setState(() => _remaining = left.isNegative ? Duration.zero : left);
      if (left <= Duration.zero) {
        _timer?.cancel();
        _generateIfEnded();
      }
    });
  }

  Future<void> _generateIfEnded() async {
    if (_endTime == null || DateTime.now().isBefore(_endTime!) || _generating) return;
    _generating = true;
    try {
      await _service.generateIfNeeded(widget.contestId);
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      _generating = false;
    }
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Widget _countdown() {
    final parts = [
      [_remaining.inDays.toString(), 'Days'],
      [_two(_remaining.inHours.remainder(24)), 'Hours'],
      [_two(_remaining.inMinutes.remainder(60)), 'Minutes'],
      [_two(_remaining.inSeconds.remainder(60)), 'Seconds'],
    ];
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE7E8EE))),
      child: Column(children: [
        const Icon(Icons.emoji_events_rounded, color: _gold, size: 44),
        const SizedBox(height: 12),
        const Text('Leaderboard Appears In', style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        Row(children: parts.map((p) => Expanded(child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4), padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
          decoration: BoxDecoration(color: const Color(0xFFEDEBFF), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [Text(p[0], style: const TextStyle(color: _purple, fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(p[1], style: const TextStyle(color: _muted, fontSize: 10))]),
        ))).toList()),
        const SizedBox(height: 18),
        const Text('The leaderboard will be available when the contest ends.', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 14)),
      ]),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedParticipants(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final list = docs.where((d) => d.id != '_metadata').toList();
    list.sort((a, b) => ((a.data()['Rank'] as num?)?.toInt() ?? 999999).compareTo((b.data()['Rank'] as num?)?.toInt() ?? 999999));
    return list;
  }

  Widget _participantTile(Map<String, dynamic> data) {
    final rank = (data['Rank'] as num?)?.toInt() ?? 0;
    final name = (data['Username'] ?? 'Participant').toString();
    final userId = (data['User_ID'] ?? '').toString();
    final score = (data['Score'] as num?)?.toDouble() ?? 0.0;
    final color = rank == 1 ? _gold : rank == 2 ? const Color(0xFF8A929E) : rank == 3 ? const Color(0xFFB77945) : _purple;
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE7E8EE))),
      child: Row(children: [
        Container(width: 42, height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: color.withOpacity(.12), shape: BoxShape.circle), child: Text('#$rank', style: TextStyle(color: color, fontWeight: FontWeight.w900))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _text, fontWeight: FontWeight.w800, fontSize: 15)), if (userId.isNotEmpty) Text(userId, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 11))])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(score.toStringAsFixed(2), style: const TextStyle(color: _purple, fontWeight: FontWeight.w900, fontSize: 17)), const Text('Score', style: TextStyle(color: _muted, fontSize: 11))]),
      ]),
    );
  }

  Widget _yourRank(List<QueryDocumentSnapshot<Map<String, dynamic>>> participants) {
    QueryDocumentSnapshot<Map<String, dynamic>>? mine;
    for (final doc in participants) { if (doc.id == _uid) { mine = doc; break; } }
    if (mine == null) return const SizedBox.shrink();
    final data = mine.data();
    final rank = (data['Rank'] as num?)?.toInt() ?? 0;
    final score = (data['Score'] as num?)?.toDouble() ?? 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFE8F7EE), borderRadius: BorderRadius.circular(17), border: Border.all(color: _green)),
      child: Row(children: [
        const Icon(Icons.person_pin_circle, color: _green, size: 30), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('YOUR RANK', style: TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text((data['Username'] ?? 'You').toString(), style: const TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w800)), Text('Score: ${score.toStringAsFixed(2)}', style: const TextStyle(color: _muted, fontSize: 13))])),
        Text('#$rank', style: const TextStyle(color: _green, fontSize: 27, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _searchResults() {
    final q = _query;
    final stream = _rankRef.where('Username_Search', isGreaterThanOrEqualTo: q).where('Username_Search', isLessThanOrEqualTo: '$q\uf8ff').limit(20).snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) return const Text('Search is unavailable right now.', style: TextStyle(color: _muted));
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(color: _purple)));
        final results = _sortedParticipants(snap.data!.docs);
        if (results.isEmpty) return const Padding(padding: EdgeInsets.all(12), child: Text('No participant found.', style: TextStyle(color: _muted)));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Text('SEARCH RESULTS', style: TextStyle(color: _text, fontWeight: FontWeight.w800)), const SizedBox(height: 8), ...results.map((d) => _participantTile(d.data()))]);
      },
    );
  }

  Widget _leaderboard(List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs) {
    final participants = _sortedParticipants(allDocs);
    final topTen = participants.take(10).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Leaderboard 🏆', textAlign: TextAlign.center, style: TextStyle(color: _text, fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text('Top 10 contest performers', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 14)),
        const SizedBox(height: 20),
        _yourRank(participants),
        TextField(
          controller: _search, onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          decoration: InputDecoration(hintText: 'Search participant by username', prefixIcon: const Icon(Icons.search, color: _muted), suffixIcon: _query.isEmpty ? null : IconButton(onPressed: () { _search.clear(); setState(() => _query = ''); }, icon: const Icon(Icons.close)), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFE7E8EE))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFE7E8EE))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: _purple))),
        ),
        if (_query.isNotEmpty) ...[const SizedBox(height: 12), _searchResults()],
        const SizedBox(height: 22),
        const Text('TOP 10', style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        if (topTen.isEmpty) const Text('No leaderboard entries found.', style: TextStyle(color: _muted)) else ...topTen.map((d) => _participantTile(d.data())),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: _bg, body: Center(child: CircularProgressIndicator(color: _purple)));
    if (_endTime == null) return Scaffold(backgroundColor: _bg, body: Center(child: Text(_error ?? 'Contest information unavailable.', style: const TextStyle(color: _muted))));
    if (DateTime.now().isBefore(_endTime!)) {
      return Scaffold(backgroundColor: _bg, body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(18), child: Column(children: [const SizedBox(height: 30), _countdown()]))));
    }
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _rankRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('Unable to load leaderboard: ${snap.error}', textAlign: TextAlign.center, style: const TextStyle(color: _muted))));
          final docs = snap.data?.docs ?? [];
          final entries = _sortedParticipants(docs);
          if (entries.isNotEmpty) return _leaderboard(docs);
          if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _muted)), const SizedBox(height: 12), ElevatedButton(onPressed: () { setState(() => _error = null); _generateIfEnded(); }, child: const Text('Try Again'))])));
          return const Center(child: CircularProgressIndicator(color: _purple));
        },
      )),
    );
  }
}
