import 'package:flutter/material.dart';
import '../models/event.dart';

class EventSelectorDialog extends StatefulWidget {
  final List<Event> events;
  final Event? currentEvent;
  final Function(Event) onEventSelected;
  final VoidCallback onCreateNewEvent;
  final Function(Event)? onStartEvent;
  final Function(Event)? onCompleteEvent;
  final Function(Event)? onReopenEvent;
  final VoidCallback onDismiss;

  const EventSelectorDialog({
    super.key,
    required this.events,
    this.currentEvent,
    required this.onEventSelected,
    required this.onCreateNewEvent,
    this.onStartEvent,
    this.onCompleteEvent,
    this.onReopenEvent,
    required this.onDismiss,
  });

  @override
  State<EventSelectorDialog> createState() => _EventSelectorDialogState();
}

class _EventSelectorDialogState extends State<EventSelectorDialog> {
  bool showCompletedEvents = false;

  @override
  Widget build(BuildContext context) {
    // Filter events based on toggle
    final filteredEvents = showCompletedEvents
        ? widget.events.where((e) => e.isCompleted).toList()
        : widget.events.where((e) => !e.isCompleted).toList();

    return Dialog(
      child: Card(
        margin: const EdgeInsets.all(16),
        elevation: 8,
        child: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxHeight: 600),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select Event',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  TextButton.icon(
                    onPressed: widget.onCreateNewEvent,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Event'),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Toggle Switch
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    showCompletedEvents ? 'Completed Events' : 'Active Events',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  Row(
                    children: [
                      Text(
                        'Show Completed',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: showCompletedEvents,
                        onChanged: (value) {
                          setState(() {
                            showCompletedEvents = value;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Events List
              Expanded(
                child: filteredEvents.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        itemCount: filteredEvents.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final event = filteredEvents[index];
                          return _EventCard(
                            event: event,
                            isSelected: widget.currentEvent?.id == event.id,
                            onSelected: () => widget.onEventSelected(event),
                            onStartEvent: widget.onStartEvent,
                            onCompleteEvent: widget.onCompleteEvent,
                            onReopenEvent: widget.onReopenEvent,
                          );
                        },
                      ),
              ),

              // Cancel Button
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.onDismiss,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              showCompletedEvents ? 'No Completed Events' : 'No Active Events',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              showCompletedEvents
                  ? 'Complete an event to see it here'
                  : 'Create your first event to get started',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final Event event;
  final bool isSelected;
  final VoidCallback onSelected;
  final Function(Event)? onStartEvent;
  final Function(Event)? onCompleteEvent;
  final Function(Event)? onReopenEvent;

  const _EventCard({
    required this.event,
    required this.isSelected,
    required this.onSelected,
    this.onStartEvent,
    this.onCompleteEvent,
    this.onReopenEvent,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isSelected
            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Event #${event.eventNumber}',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getStatusColor(context),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getStatusText(),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Colors.white,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        event.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Created: ${event.formattedDate}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(BuildContext context) {
    if (event.isCompleted) return Theme.of(context).colorScheme.tertiary;
    if (event.isActive) return Theme.of(context).colorScheme.primary;
    return Theme.of(context).colorScheme.outline;
  }

  String _getStatusText() {
    if (event.isCompleted) return 'COMPLETED';
    if (event.isActive) return 'ACTIVE';
    return 'INACTIVE';
  }
}
