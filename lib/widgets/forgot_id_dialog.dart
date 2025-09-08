import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/student.dart';
import '../services/scanner_service.dart';
import '../providers/scanner_provider.dart';

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
    super.dispose();
  }

  Future<void> _loadStudents() async {
    try {
      final scannerService = ScannerService();
      final students = await scannerService.getStudents();
      setState(() {
        _allStudents = students;
        _filteredStudents = students;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading students: $e')),
        );
      }
    }
  }

  void _onSearchChanged() {
    final searchText = _searchController.text.toLowerCase();
    setState(() {
      _searchText = searchText;
      if (searchText.isEmpty) {
        _filteredStudents = _allStudents;
      } else {
        _filteredStudents = _allStudents.where((student) {
          return student.firstName.toLowerCase().contains(searchText) ||
                 student.lastName.toLowerCase().contains(searchText) ||
                 student.studentId.toLowerCase().contains(searchText) ||
                 student.email.toLowerCase().contains(searchText);
        }).toList();
      }
    });
  }

  void _selectStudent(Student student) async {
    debugPrint('🔍 FORGOT_ID: _selectStudent called for ${student.studentId} - ${student.firstName} ${student.lastName}');
    
    try {
      debugPrint('🔍 FORGOT_ID: Getting scanner notifier...');
      final scannerNotifier = ref.read(scannerProvider.notifier);
      debugPrint('🔍 FORGOT_ID: Calling addManualScan...');
      await scannerNotifier.addManualScan(student);
      debugPrint('🔍 FORGOT_ID: addManualScan completed successfully');
      
      debugPrint('🔍 FORGOT_ID: Successfully added manual scan for ${student.studentId}');
      
      // Close dialog and trigger success dialog
      if (mounted) {
        debugPrint('🔍 FORGOT_ID: Dismissing dialog...');
        widget.onDismiss(); // This will handle both dialog close and state reset
        
        // Set state to show student success dialog
        scannerNotifier.showStudentSuccessDialog(student);
        
        debugPrint('🔍 FORGOT_ID: Dialog dismissed and success dialog triggered');
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
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
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
              decoration: const InputDecoration(
                hintText: 'Search by name, ID, or email...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
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
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  child: Text(
                                    '${student.firstName[0]}${student.lastName[0]}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  '${student.firstName} ${student.lastName}',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('ID: ${student.studentId}'),
                                    if (student.email.isNotEmpty)
                                      Text(
                                        student.email,
                                        style: const TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                  ],
                                ),
                                isThreeLine: student.email.isNotEmpty,
                                trailing: const Icon(Icons.arrow_forward_ios),
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
