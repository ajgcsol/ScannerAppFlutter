import 'package:flutter/material.dart';

class ForgotIdDialog extends StatelessWidget {
  final VoidCallback onDismiss;

  const ForgotIdDialog({
    super.key,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Forgot ID'),
      content: const Text('This feature is not yet implemented.'),
      actions: [
        TextButton(
          onPressed: onDismiss,
          child: const Text('Close'),
        ),
      ],
    );
  }
}
