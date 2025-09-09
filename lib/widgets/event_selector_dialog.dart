import 'package:flutter/material.dart';
import '../models/event.dart';
import '../widgets/create_event_dialog.dart';

class EventSelectorDialog extends StatefulWidget {
  final List<Event> events;
  final Function(Event) onEventSelected;
  final Function(Event) onEventCreated;
  final VoidCallback onDismiss;

  const EventSelectorDialog({
    super.key,
    required this.events,
    required this.onEventSelected,
    required this.onEventCreated,
    required this.onDismiss,
  });

  @override
  State<EventSelectorDialog> createState() => _EventSelectorDialogState();
}

class _EventSelectorDialogState extends State<EventSelectorDialog> {
  bool _showAllEvents = false;

  List<Event> get filteredEvents {
    if (_showAllEvents) {
      return widget.events;
    } else {
      // Filter for active, non-completed, non-sample events
      return widget.events.where((event) {
        final name = event.name.toLowerCase();
        final id = event.id.toLowerCase();
        
        // Check if it's a sample/test event
        final isSampleEvent = name.contains('sample') || 
                             name.contains('test') ||
                             name.contains('demo') ||
                             name.contains('example') ||
                             id.startsWith('event_') ||
                             id.contains('sample') ||
                             id.contains('test') ||
                             id.contains('demo');
        
        return event.isActive && !event.isCompleted && !isSampleEvent;
      }).toList();
    }
  }

  void _showCreateEventDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateEventDialog(
        onEventCreated: (event) {
          Navigator.of(context).pop(); // Close create dialog
          widget.onEventCreated(event);
        },
        onDismiss: () => Navigator.of(context).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredEventsList = filteredEvents;
    
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Event',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onDismiss,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            
            // Filter Toggle
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${filteredEventsList.length} event${filteredEventsList.length != 1 ? 's' : ''} found',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        _showAllEvents ? 'Show All' : 'Active Only',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: _showAllEvents,
                        onChanged: (value) {
                          setState(() {
                            _showAllEvents = value;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Event List
            Expanded(
              child: filteredEventsList.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_busy,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _showAllEvents
                                ? 'No events found'
                                : 'No active events found',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                          if (!_showAllEvents && widget.events.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _showAllEvents = true;
                                });
                              },
                              child: const Text('Show all events'),
                            ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredEventsList.length,
                      itemBuilder: (context, index) {
                        final event = filteredEventsList[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: event.isActive 
                                ? (event.isCompleted ? Colors.grey : Theme.of(context).colorScheme.primary)
                                : Colors.orange,
                              child: Text(
                                event.eventNumber.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              event.name,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Event #${event.eventNumber}'),
                                Text(
                                  event.shortDate,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if (event.location.isNotEmpty)
                                  Text(
                                    event.location,
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (event.isCompleted)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'Completed',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                      ),
                                    ),
                                  )
                                else if (!event.isActive)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'Inactive',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward_ios),
                              ],
                            ),
                            isThreeLine: event.location.isNotEmpty,
                            onTap: () => widget.onEventSelected(event),
                          ),
                        );
                      },
                    ),
            ),
            
            // Bottom Actions
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: widget.onDismiss,
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _showCreateEventDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Create Event'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
