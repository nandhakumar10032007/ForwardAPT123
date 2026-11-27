import 'package:flutter/material.dart';

class HomeFilterWidget extends StatelessWidget {
  final List<String> topics;
  final String selectedTopic;
  final String selectedDifficulty;
  final String selectedStatus;

  final ValueChanged<String> onTopicChanged;
  final ValueChanged<String> onDifficultyChanged;
  final ValueChanged<String> onStatusChanged;

  const HomeFilterWidget({
    super.key,
    required this.topics,
    required this.selectedTopic,
    required this.selectedDifficulty,
    required this.selectedStatus,
    required this.onTopicChanged,
    required this.onDifficultyChanged,
    required this.onStatusChanged,
  });

  static const Color _primary = Color(0xFF4F46E5);
  static const Color _background = Color(0xFFF7F8FC);
  static const Color _text = Color(0xFF171923);
  static const Color _muted = Color(0xFF777A87);

  static const List<String> difficulties = ['All', 'Easy', 'Medium', 'Hard'];
  static const List<String> statuses = ['Unsolved', 'Solved', 'Both'];

  List<String> get _topicOptions => [
        'All Topics',
        ...topics.where((topic) => topic != 'All Topics'),
      ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E6EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEBFF),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: _primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Text(
                  'Filter Questions',
                  style: TextStyle(
                    color: _text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'CUSTOMIZE',
                style: TextStyle(
                  color: _muted.withOpacity(0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _sectionTitle(Icons.category_outlined, 'Topic'),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: _background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E6EB)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _topicOptions.contains(selectedTopic)
                    ? selectedTopic
                    : 'All Topics',
                isExpanded: true,
                borderRadius: BorderRadius.circular(12),
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: _primary,
                ),
                style: const TextStyle(
                  color: _text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                items: _topicOptions.map((topic) {
                  return DropdownMenuItem<String>(
                    value: topic,
                    child: Text(
                      topic,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) onTopicChanged(value);
                },
              ),
            ),
          ),
          const SizedBox(height: 22),
          _sectionTitle(Icons.speed_rounded, 'Difficulty'),
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 9,
            children: difficulties.map((difficulty) {
              return _filterChip(
                label: difficulty,
                selected: selectedDifficulty == difficulty,
                onTap: () => onDifficultyChanged(difficulty),
              );
            }).toList(),
          ),
          const SizedBox(height: 22),
          _sectionTitle(Icons.check_circle_outline_rounded, 'Solved Status'),
          const SizedBox(height: 11),
          Row(
            children: statuses.map((status) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: status == 'Both' ? 0 : 8),
                  child: _filterChip(
                    label: status,
                    selected: selectedStatus == status,
                    expanded: true,
                    onTap: () => onStatusChanged(status),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 17, color: _muted),
        const SizedBox(width: 7),
        Text(
          title,
          style: const TextStyle(
            color: _text,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool expanded = false,
  }) {
    return Material(
      color: selected ? _primary : _background,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          width: expanded ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? _primary : const Color(0xFFE5E6EB),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, color: Colors.white, size: 15),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : _text,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
