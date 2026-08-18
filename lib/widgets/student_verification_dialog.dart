import 'package:flutter/material.dart';
import '../models/student.dart';

/// Shown when a student is identified — after a successful scan, or from the
/// forgot-ID list as a confirmation step before the scan is recorded.
///
/// Leads with a large ID photo plus the student's name and email in large
/// type, so staff can verify at a glance that the person in front of them
/// matches the record.
class StudentVerificationDialog extends StatelessWidget {
  final Student? student;
  final VoidCallback onDismiss;

  /// When set, the dialog acts as a confirmation: Cancel/Confirm buttons are
  /// shown and nothing has been recorded yet. When null, it is a success
  /// notice for an already-recorded scan.
  final VoidCallback? onConfirm;

  const StudentVerificationDialog({
    super.key,
    this.student,
    required this.onDismiss,
    this.onConfirm,
  });

  bool get _isConfirmation => onConfirm != null;

  @override
  Widget build(BuildContext context) {
    if (student == null) {
      return AlertDialog(
        title: const Text('Student Not Found'),
        content: const Text('The scanned ID was not found in the database.'),
        actions: [
          TextButton(
            onPressed: onDismiss,
            child: const Text('OK'),
          ),
        ],
      );
    }

    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Text(
                _isConfirmation
                    ? 'Confirm Student'
                    : "You're all set, ${student!.firstName}!",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: _isConfirmation
                      ? theme.colorScheme.primary
                      : Colors.green,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),

              // Large ID photo
              _StudentPhoto(student: student!),

              const SizedBox(height: 20),

              // Name — large
              Text(
                '${student!.firstName} ${student!.lastName}',
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              // Email — large, always on one line: long addresses shrink to
              // fit instead of wrapping.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  student!.email,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                  maxLines: 1,
                ),
              ),

              const SizedBox(height: 24),

              if (_isConfirmation)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onDismiss,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onConfirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Confirm',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onDismiss,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The large photo block: network image when the student has one, otherwise
/// an initials avatar. Never blocks the dialog — loading shows a spinner over
/// the fallback and errors degrade to the initials.
class _StudentPhoto extends StatelessWidget {
  final Student student;

  const _StudentPhoto({required this.student});

  static const double _size = 250;

  @override
  Widget build(BuildContext context) {
    final url = student.photoUrl;

    Widget fallback = Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: 76,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );

    if (url == null || url.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        url,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: _size,
            height: _size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                fallback,
                const CircularProgressIndicator(strokeWidth: 2),
              ],
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }

  String get _initials {
    final f = student.firstName.isNotEmpty ? student.firstName[0] : '';
    final l = student.lastName.isNotEmpty ? student.lastName[0] : '';
    final joined = '$f$l'.toUpperCase();
    return joined.isEmpty ? '?' : joined;
  }
}
