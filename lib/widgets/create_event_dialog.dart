import 'dart:math';
import 'package:flutter/material.dart';
import '../services/group_session.dart';
import 'package:flutter/services.dart';
import '../models/event.dart';

class CreateEventDialog extends StatefulWidget {
  final Function(Event) onEventCreated;
  final VoidCallback onDismiss;

  const CreateEventDialog({
    super.key,
    required this.onEventCreated,
    required this.onDismiss,
  });

  @override
  State<CreateEventDialog> createState() => _CreateEventDialogState();
}

class _CreateEventDialogState extends State<CreateEventDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _eventNumberController = TextEditingController();
  
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _isActive = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    // Generate random event number between 100-999
    _eventNumberController.text = (100 + Random().nextInt(900)).toString();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _eventNumberController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _createEvent() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isCreating = true;
      });

      try {
        final eventDateTime = GroupSession.groupMode
            // Scan lists are day-scoped; no time component.
            ? DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day)
            : DateTime(
                _selectedDate.year,
                _selectedDate.month,
                _selectedDate.day,
                _selectedTime.hour,
                _selectedTime.minute,
              );

        // Group scan lists auto-number far above the SONIS id range so the
        // number never collides with attendance events and never needs to be
        // typed by staff.
        final eventNumber = GroupSession.groupMode
            ? 9000000 + (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 900000
            : int.parse(_eventNumberController.text);

        final event = Event.createNew(
          eventNumber: eventNumber,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          date: eventDateTime,
          location: _locationController.text.trim(),
          // Department mode: the new list belongs to the active group.
          groupId: GroupSession.groupMode ? GroupSession.groupId : null,
        ).copyWith(isActive: _isActive);

        widget.onEventCreated(event);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating event: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isCreating = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Create New Event',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: _isCreating ? null : widget.onDismiss,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Event Number — SONIS concept; group scan lists
                      // auto-number themselves out of the SONIS range.
                      if (!GroupSession.groupMode)
                      TextFormField(
                        controller: _eventNumberController,
                        decoration: const InputDecoration(
                          labelText: 'Event Number',
                          border: OutlineInputBorder(),
                          helperText: 'Unique identifier for this event',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Event number is required';
                          }
                          final num = int.tryParse(value);
                          if (num == null || num < 1) {
                            return 'Enter a valid event number';
                          }
                          return null;
                        },
                      ),

                      if (!GroupSession.groupMode) const SizedBox(height: 16),

                      // Event Name
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Event Name',
                          border: OutlineInputBorder(),
                          helperText: 'Required',
                        ),
                        maxLength: 100,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Event name is required';
                          }
                          return null;
                        },
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Description
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                          helperText: 'Optional',
                        ),
                        maxLines: 3,
                        maxLength: 500,
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Location
                      if (!GroupSession.groupMode)
                      TextFormField(
                        controller: _locationController,
                        decoration: const InputDecoration(
                          labelText: 'Location',
                          border: OutlineInputBorder(),
                          helperText: 'Optional',
                        ),
                        maxLength: 200,
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Date Selection
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                GroupSession.groupMode ? 'Event Date' : 'Event Date & Time',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Full-width rows: side-by-side chips wrapped
                              // their labels one character per line.
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _isCreating ? null : _selectDate,
                                  icon: const Icon(Icons.calendar_today),
                                  label: Text(
                                    '${_selectedDate.month}/${_selectedDate.day}/${_selectedDate.year}',
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                              if (!GroupSession.groupMode) ...[
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _isCreating ? null : _selectTime,
                                    icon: const Icon(Icons.access_time),
                                    label: Text(
                                      _selectedTime.format(context),
                                      maxLines: 1,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Event Status — group lists are always active.
                      if (!GroupSession.groupMode)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Event Status',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                title: const Text('Active'),
                                subtitle: Text(_isActive 
                                  ? 'Event is available for scanning'
                                  : 'Event is inactive and hidden'
                                ),
                                value: _isActive,
                                onChanged: _isCreating ? null : (value) {
                                  setState(() {
                                    _isActive = value;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isCreating ? null : widget.onDismiss,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isCreating ? null : _createEvent,
                  icon: _isCreating 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                  label: Text(_isCreating ? 'Creating...' : 'Create Event'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}