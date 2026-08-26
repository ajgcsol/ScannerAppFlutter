import 'package:flutter/material.dart';
import '../models/event.dart';
import '../utils/theme.dart';

/// The active-event banner on the Home tab.
///
/// This is the single most consequential piece of state in the app — every
/// scan lands on whatever it names — so it is deliberately loud: brand-tinted,
/// bordered, with the event's DATE always visible and a "Today" badge when the
/// event is actually today. Confusing the selected event is how attendance
/// ends up on the wrong list.
class EventHeaderCard extends StatelessWidget {
  final Event? currentEvent;
  final VoidCallback onSelectEvent;

  const EventHeaderCard({
    super.key,
    required this.currentEvent,
    required this.onSelectEvent,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  // Event dates are calendar dates stored at midnight UTC; formatting must use
  // UTC components or the date renders a day early in US timezones.
  DateTime get _dateUtc => currentEvent!.date.toUtc();

  bool get _isToday {
    final now = DateTime.now();
    final d = _dateUtc;
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  String get _dateLabel {
    final d = _dateUtc;
    return '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final event = currentEvent;

    if (event == null) {
      return _shell(
        context,
        accent: AppTheme.warningOrange,
        child: Row(
          children: [
            const Icon(Icons.event_busy, color: AppTheme.warningOrange, size: 30),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No Event Selected',
                      style: TextStyle(
                          fontSize: 19, fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text('Tap to choose before scanning',
                      style: TextStyle(fontSize: 14)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: AppTheme.warningOrange, size: 26),
          ],
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return _shell(
      context,
      accent: scheme.primary,
      child: Row(
        children: [
          // Date block — the detail that prevents scanning the wrong event.
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  _months[_dateUtc.month - 1].toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5),
                ),
                Text(
                  '${_dateUtc.day}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      height: 1.1,
                      fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_isToday)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.successGreen,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('TODAY',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5)),
                      ),
                    // Only SONIS attendance events have a meaningful number.
                    if (event.groupId == null)
                      Text('#${event.eventNumber}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  event.name,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.bold, height: 1.15),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  _dateLabel,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            children: [
              Icon(Icons.swap_horiz, color: scheme.primary, size: 22),
              const SizedBox(height: 2),
              Text('CHANGE',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: scheme.primary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shell(BuildContext context,
      {required Color accent, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onSelectEvent,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.45), width: 2),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
