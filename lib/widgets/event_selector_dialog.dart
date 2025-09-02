import 'package:flutter/material.dart';
import '../models/event.dart';

class EventSelectorDialog extends StatelessWidget {
  final List<Event> events;
  final Function(Event) onEventSelected;
  final VoidCallback onDismiss;

  const EventSelectorDialog({
    super.key,
    required this.events,
    required this.onEventSelected,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Event'),
      content: SingleChildScrollView(
        child: Column(
          children: events
              .map((event) => ListTile(
                    title: Text(event.name),
                    onTap: () => onEventSelected(event),
                  ))
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: onDismiss,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
