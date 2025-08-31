import 'package:flutter/material.dart';
import '../models/student.dart';

class DuplicateScanDialog extends StatelessWidget {
  final Student? student;
  final String studentId;
  final VoidCallback onDismiss;

  const DuplicateScanDialog({
    super.key,
    this.student,
    required this.studentId,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Card(
        child: Container(
          width: double.maxFinite,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning icon
              Icon(
                Icons.warning,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),

              const SizedBox(height: 16),

              // Title
              Text(
                'Duplicate Scan Detected',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Student info
              if (student != null) ...[
                Text(
                  '${student!.firstName} ${student!.lastName}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  'ID: $studentId',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                Text(
                  'Student ID: $studentId',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  '(Student not found)',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 16),

              // Message
              Text(
                'This student has already been scanned for the current event.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              // OK button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onDismiss,
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
