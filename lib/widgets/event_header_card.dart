import 'package:flutter/material.dart';
import '../models/event.dart';

class EventHeaderCard extends StatelessWidget {
  final Event? currentEvent;
  final VoidCallback onSelectEvent;

  const EventHeaderCard({
    super.key,
    required this.currentEvent,
    required this.onSelectEvent,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(currentEvent?.name ?? 'No Event Selected'),
        subtitle: Text(currentEvent?.description ?? 'Tap to select an event'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onSelectEvent,
      ),
    );
  }
}
