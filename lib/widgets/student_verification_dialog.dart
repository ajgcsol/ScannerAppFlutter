import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/student.dart';

class StudentVerificationDialog extends StatefulWidget {
  final Student? student;
  final String scannedId;
  final VoidCallback onDismiss;
  final Function(String, String)? onSubmitErrorRecord;

  const StudentVerificationDialog({
    super.key,
    this.student,
    required this.scannedId,
    required this.onDismiss,
    this.onSubmitErrorRecord,
  });

  @override
  State<StudentVerificationDialog> createState() =>
      _StudentVerificationDialogState();
}

class _StudentVerificationDialogState extends State<StudentVerificationDialog>
    with TickerProviderStateMixin {
  bool showDialog = true;
  bool isInteracting = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    if (widget.student != null) {
      _animationController.repeat(reverse: true);
    }

    // Auto-dismiss logic
    _setupAutoDismiss();
  }

  void _setupAutoDismiss() {
    if (widget.student != null) {
      // Success dialog - auto dismiss after 4 seconds
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && !isInteracting) {
          _dismissDialog();
        }
      });
    } else {
      // Failure dialog - auto dismiss after 6 seconds if not interacting
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted && !isInteracting) {
          _dismissDialog();
        }
      });
    }
  }

  void _dismissDialog() {
    if (mounted) {
      setState(() {
        showDialog = false;
      });
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!showDialog) return const SizedBox.shrink();

    final isTablet = MediaQuery.of(context).size.width > 600;

    return Dialog(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: isTablet
            ? MediaQuery.of(context).size.width * 0.6
            : MediaQuery.of(context).size.width * 0.9,
        child: widget.student != null
            ? _SuccessDialog(
                student: widget.student!,
                onDismiss: _dismissDialog,
                scaleAnimation: _scaleAnimation,
              )
            : _FailureDialog(
                scannedId: widget.scannedId,
                onDismiss: _dismissDialog,
                onSubmitErrorRecord: widget.onSubmitErrorRecord,
                onInteractionChanged: (interacting) {
                  setState(() {
                    isInteracting = interacting;
                  });
                },
              ),
      ),
    );
  }
}

class _SuccessDialog extends StatelessWidget {
  final Student student;
  final VoidCallback onDismiss;
  final Animation<double> scaleAnimation;

  const _SuccessDialog({
    required this.student,
    required this.onDismiss,
    required this.scaleAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 12,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Success Animation
            AnimatedBuilder(
              animation: scaleAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: scaleAnimation.value,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E8),
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      size: 48,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Success Message
            Text(
              "You're all set, ${student.firstName}!",
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2E7D32),
                  ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            Text(
              'Please ensure the information below is relevant to your student record',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Student Information Card
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _StudentInfoRow(
                      icon: Icons.person,
                      label: 'Name',
                      value: '${student.firstName} ${student.lastName}',
                    ),
                    const SizedBox(height: 12),
                    _StudentInfoRow(
                      icon: Icons.badge,
                      label: 'Student ID',
                      value: student.studentId,
                    ),
                    if (student.email.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _StudentInfoRow(
                        icon: Icons.email,
                        label: 'Email',
                        value: student.email,
                      ),
                    ],
                    if (student.program.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _StudentInfoRow(
                        icon: Icons.school,
                        label: 'Program',
                        value: student.program,
                      ),
                    ],
                    if (student.year.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _StudentInfoRow(
                        icon: Icons.date_range,
                        label: 'Year',
                        value: student.year,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Close Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onDismiss,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  'Continue',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailureDialog extends StatefulWidget {
  final String scannedId;
  final VoidCallback onDismiss;
  final Function(String, String)? onSubmitErrorRecord;
  final Function(bool) onInteractionChanged;

  const _FailureDialog({
    required this.scannedId,
    required this.onDismiss,
    this.onSubmitErrorRecord,
    required this.onInteractionChanged,
  });

  @override
  State<_FailureDialog> createState() => _FailureDialogState();
}

class _FailureDialogState extends State<_FailureDialog> {
  String email = '';
  bool isEmailValid = false;
  bool showEmailInput = false;
  final TextEditingController _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _emailController.addListener(() {
      setState(() {
        email = _emailController.text;
        isEmailValid = _isValidEmail(email);
      });
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 12,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Error Icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(40),
              ),
              child: const Icon(
                Icons.warning,
                size: 48,
                color: Color(0xFFD32F2F),
              ),
            ),

            const SizedBox(height: 24),

            // Error Message
            Text(
              'Student Not Found',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFD32F2F),
                  ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            Text(
              'The scanned ID is not registered in our system',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Scanned ID Information
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      'Scanned ID:',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.scannedId,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Email Input Section
            if (showEmailInput) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Please enter your email to report this issue:',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      hintText: 'student@example.com',
                      border: const OutlineInputBorder(),
                      errorText: email.isNotEmpty && !isEmailValid
                          ? 'Please enter a valid email address'
                          : null,
                    ),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (value) {
                      widget.onInteractionChanged(true);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          showEmailInput = false;
                          email = '';
                          _emailController.clear();
                        });
                        widget.onInteractionChanged(false);
                      },
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isEmailValid
                          ? () {
                              widget.onSubmitErrorRecord
                                  ?.call(widget.scannedId, email);
                              widget.onInteractionChanged(false);
                              widget.onDismiss();
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Submit'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                'Please contact the administrator or verify the correct student ID',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (widget.onSubmitErrorRecord != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            showEmailInput = true;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Report Issue'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: widget.onDismiss,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StudentInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StudentInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer
                          .withOpacity(0.7),
                    ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
