import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NewEventDialog extends StatefulWidget {
  final Function(int, String, String) onCreateEvent;
  final VoidCallback onDismiss;

  const NewEventDialog({
    super.key,
    required this.onCreateEvent,
    required this.onDismiss,
  });

  @override
  State<NewEventDialog> createState() => _NewEventDialogState();
}

class _NewEventDialogState extends State<NewEventDialog> {
  final TextEditingController _eventNumberController = TextEditingController();
  final TextEditingController _eventNameController = TextEditingController();
  final TextEditingController _eventDescriptionController =
      TextEditingController();

  String showError = '';

  @override
  void dispose() {
    _eventNumberController.dispose();
    _eventNameController.dispose();
    _eventDescriptionController.dispose();
    super.dispose();
  }

  void _validateAndCreate() {
    final eventNumber = _eventNumberController.text.trim();
    final eventName = _eventNameController.text.trim();
    final eventDescription = _eventDescriptionController.text.trim();

    setState(() {
      if (eventNumber.isEmpty) {
        showError = 'Please enter an event number';
      } else if (int.tryParse(eventNumber) == null) {
        showError = 'Event number must be a valid number';
      } else if (int.parse(eventNumber) <= 0) {
        showError = 'Event number must be greater than 0';
      } else if (eventName.isEmpty) {
        showError = 'Please enter an event name';
      } else if (eventName.length < 3) {
        showError = 'Event name must be at least 3 characters';
      } else {
        // Valid input - create event
        showError = '';
        widget.onCreateEvent(
          int.parse(eventNumber),
          eventName,
          eventDescription,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Card(
        margin: const EdgeInsets.all(16),
        elevation: 8,
        child: Container(
          width: double.maxFinite,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Create New Event',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),

              const SizedBox(height: 20),

              // Event Number Field
              TextField(
                controller: _eventNumberController,
                decoration: const InputDecoration(
                  labelText: 'Event Number',
                  hintText: 'e.g., 889',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) {
                  setState(() {
                    showError = '';
                  });
                },
              ),

              const SizedBox(height: 16),

              // Event Name Field
              TextField(
                controller: _eventNameController,
                decoration: const InputDecoration(
                  labelText: 'Event Name',
                  hintText: 'e.g., Spring Career Fair 2024',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    showError = '';
                  });
                },
              ),

              const SizedBox(height: 16),

              // Event Description Field (Optional)
              TextField(
                controller: _eventDescriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'Brief description of the event...',
                  border: OutlineInputBorder(),
                ),
                minLines: 2,
                maxLines: 3,
              ),

              const SizedBox(height: 16),

              // Error Message
              if (showError.isNotEmpty)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            showError,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (showError.isNotEmpty) const SizedBox(height: 16),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.onDismiss,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _validateAndCreate,
                    child: const Text('Create Event'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
