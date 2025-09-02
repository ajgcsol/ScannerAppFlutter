import 'package:flutter/material.dart';
import '../models/student.dart';

class StudentVerificationDialog extends StatelessWidget {
  final Student? student;
  final VoidCallback onDismiss;

  const StudentVerificationDialog({
    super.key,
    this.student,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(student != null ? 'Student Verified' : 'Student Not Found'),
      content: SingleChildScrollView(
        child: student != null
            ? Text('Successfully scanned ${student!.fullName}.')
            : const Text('The scanned ID was not found in the database.'),
      ),
      actions: [
        TextButton(
          onPressed: onDismiss,
          child: const Text('OK'),
        ),
      ],
    );
  }
}
