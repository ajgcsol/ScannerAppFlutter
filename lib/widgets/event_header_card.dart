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
    final hasEvent = currentEvent != null;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: hasEvent 
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : Theme.of(context).colorScheme.errorContainer,
      child: InkWell(
        onTap: onSelectEvent,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.event,
                color: hasEvent 
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onErrorContainer,
                size: 24,
              ),
              
              const SizedBox(width: 12),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Event',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: hasEvent 
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                    
                    const SizedBox(height: 4),
                    
                    if (hasEvent) ...[
                      Text(
                        'Event #${currentEvent!.eventNumber}: ${currentEvent!.name}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      if (currentEvent!.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          currentEvent!.description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      
                      const SizedBox(height: 4),
                      
                      // Event Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getStatusColor(currentEvent!.status),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _getStatusText(currentEvent!.status),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ] else ...[
                      Text(
                        'No Event Selected',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                      
                      const SizedBox(height: 2),
                      
                      Text(
                        'Tap to select or create an event',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              Icon(
                Icons.chevron_right,
                color: hasEvent 
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onErrorContainer,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(EventStatus status) {
    switch (status) {
      case EventStatus.active:
        return Colors.green;
      case EventStatus.inactive:
        return Colors.grey;
      case EventStatus.completed:
        return Colors.blue;
    }
  }

  String _getStatusText(EventStatus status) {
    switch (status) {
      case EventStatus.active:
        return 'ACTIVE';
      case EventStatus.inactive:
        return 'INACTIVE';
      case EventStatus.completed:
        return 'COMPLETED';
    }
  }
}
