import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/student.dart';
import '../services/scanner_service.dart';
import '../providers/scanner_provider.dart';
import 'student_verification_dialog.dart';

class ForgotIdDialog extends ConsumerStatefulWidget {
  final VoidCallback onDismiss;

  const ForgotIdDialog({
    super.key,
    required this.onDismiss,
  });

  @override
  ConsumerState<ForgotIdDialog> createState() => _ForgotIdDialogState();
}

class _ForgotIdDialogState extends ConsumerState<ForgotIdDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Student> _allStudents = [];
  List<Student> _filteredStudents = [];
  bool _isLoading = true;
  String _searchText = '';
  Timer? _debounceTimer;
  static const _debounceDelay = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _loadStudents();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    try {
      // Use existing scanner service from provider instead of creating new instance
      final scannerService = ref.read(scannerServiceProvider);
      final students = await scannerService.getStudents();
      if (mounted) {
        setState(() {
          _allStudents = students;
          _filteredStudents = students;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading students: $e')),
        );
      }
    }
  }

  void _onSearchChanged() {
    // Cancel previous debounce timer
    _debounceTimer?.cancel();
    
    // Start new debounce timer
    _debounceTimer = Timer(_debounceDelay, () {
      final searchText = _searchController.text.toLowerCase();
      if (mounted) {
        setState(() {
          _searchText = searchText;
          _performSearch(searchText);
        });
      }
    });
  }
  
  void _performSearch(String searchText) {
    if (searchText.isEmpty) {
      _filteredStudents = _allStudents;
    } else {
      // Use efficient filtering with early exit
      _filteredStudents = [];
      for (final student in _allStudents) {
        if (_filteredStudents.length >= 50) break; // Limit results for performance
        
        final firstName = student.firstName.toLowerCase();
        final lastName = student.lastName.toLowerCase();
        final studentId = student.studentId.toLowerCase();
        final email = student.email.toLowerCase();
        
        if (firstName.contains(searchText) ||
            lastName.contains(searchText) ||
            studentId.contains(searchText) ||
            email.contains(searchText)) {
          _filteredStudents.add(student);
        }
      }
    }
  }

  /// Tapping a student shows their photo, name, and email first — the scan is
  /// only recorded after staff confirms the person matches the picture.
  void _selectStudent(Student student) async {
    debugPrint('🔍 FORGOT_ID: _selectStudent called for ${student.studentId} - ${student.firstName} ${student.lastName}');

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StudentVerificationDialog(
        student: student,
        onDismiss: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );

    if (confirmed != true || !mounted) {
      debugPrint('🔍 FORGOT_ID: Selection not confirmed, returning to list');
      return;
    }

    try {
      debugPrint('🔍 FORGOT_ID: Getting scanner notifier...');
      final scannerNotifier = ref.read(scannerProvider.notifier);
      debugPrint('🔍 FORGOT_ID: Calling addManualScan...');
      await scannerNotifier.addManualScan(student);
      debugPrint('🔍 FORGOT_ID: addManualScan completed successfully');
      
      debugPrint('🔍 FORGOT_ID: Successfully added manual scan for ${student.studentId}');
      
      // The confirmation popup already showed the photo and details, so a
      // second dialog would be redundant — a snackbar confirms the record.
      if (mounted) {
        debugPrint('🔍 FORGOT_ID: Dismissing dialog...');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ ${student.fullName} marked as attending'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        widget.onDismiss(); // This will handle both dialog close and state reset
        debugPrint('🔍 FORGOT_ID: Dialog dismissed, snackbar shown');
      }
    } catch (e, stackTrace) {
      debugPrint('🔍 FORGOT_ID: EXCEPTION in _selectStudent: $e');
      debugPrint('🔍 FORGOT_ID: Stack trace: $stackTrace');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error: Could not add student'),
            backgroundColor: Colors.red,
          ),
        );
        // Don't close dialog on error, let user try again
        debugPrint('🔍 FORGOT_ID: Error handled, dialog remains open for retry');
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
                  'Find Student',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                IconButton(
                  onPressed: widget.onDismiss,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Search Field
            TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 17),
              decoration: const InputDecoration(
                hintText: 'Search by name, ID, or email...',
                prefixIcon: Icon(Icons.search),
              ),
              autofocus: true,
            ),
            
            const SizedBox(height: 16),
            
            // Results Count
            if (!_isLoading)
              Text(
                '${_filteredStudents.length} student${_filteredStudents.length != 1 ? 's' : ''} found',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            
            const SizedBox(height: 8),
            
            // Student List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredStudents.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_search,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchText.isEmpty
                                    ? 'No students available'
                                    : 'No students found for "$_searchText"',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredStudents.length,
                          itemBuilder: (context, index) {
                            final student = _filteredStudents[index];
                            final initials =
                                '${student.firstName.isNotEmpty ? student.firstName[0] : ''}'
                                '${student.lastName.isNotEmpty ? student.lastName[0] : ''}';
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                leading: CircleAvatar(
                                  radius: 26,
                                  backgroundColor:
                                      Theme.of(context).colorScheme.primary,
                                  // ID photo when available; initials otherwise.
                                  foregroundImage: (student.photoUrl != null &&
                                          student.photoUrl!.isNotEmpty)
                                      ? NetworkImage(student.photoUrl!)
                                      : null,
                                  child: Text(
                                    initials.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  '${student.firstName} ${student.lastName}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 17,
                                  ),
                                ),
                                subtitle: Text(
                                  student.email.isNotEmpty
                                      ? '${student.studentId} · ${student.email}'
                                      : student.studentId,
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                trailing:
                                    const Icon(Icons.chevron_right, size: 22),
                                onTap: () => _selectStudent(student),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
