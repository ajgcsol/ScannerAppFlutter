import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/scanner_provider.dart';
import '../widgets/event_header_card.dart';
import '../widgets/scan_item.dart';
import '../widgets/event_selector_dialog.dart';
import '../widgets/forgot_id_dialog.dart';
import '../widgets/student_verification_dialog.dart';
import '../widgets/event_summary_tab.dart';
import '../screens/camera_preview_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isErrorDialogShowing = false;
  bool _isCameraDialogShowing = false;
  bool _isEventSelectorShowing = false;
  bool _isForgotIdDialogShowing = false;
  bool _isStudentDialogShowing = false;
  bool _isDuplicateDialogShowing = false;
  
  // Master dialog guard - prevents any dialog if another is active
  bool get _isAnyDialogShowing => _isErrorDialogShowing || 
    _isCameraDialogShowing || _isEventSelectorShowing || 
    _isForgotIdDialogShowing || _isStudentDialogShowing || 
    _isDuplicateDialogShowing;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scannerState = ref.watch(scannerProvider);
    final scannerNotifier = ref.read(scannerProvider.notifier);

    ref.listen<ScannerState>(scannerProvider, (previous, next) {
      debugPrint('🏠 LISTENER: State change detected');
      debugPrint('🏠 LISTENER: Previous errorMessage: ${previous?.errorMessage}');
      debugPrint('🏠 LISTENER: Next errorMessage: ${next.errorMessage}');
      debugPrint('🏠 LISTENER: showCameraPreview: ${next.showCameraPreview}');
      debugPrint('🏠 LISTENER: showStudentDialog: ${next.showStudentDialog}');
      debugPrint('🏠 LISTENER: showDuplicateDialog: ${next.showDuplicateDialog}');
      
      if (next.showCameraPreview && previous != null && (previous.showCameraPreview == false) && !_isAnyDialogShowing) {
        debugPrint('🏠 LISTENER: Showing camera preview dialog');
        _isCameraDialogShowing = true;
        showDialog(
          context: context,
          builder: (context) => Dialog(
            child: CameraPreviewScreen(
              onScan: (code) {
                debugPrint('🏠 LISTENER: Camera scan completed with code: $code');
                Navigator.of(context).pop();
                _isCameraDialogShowing = false;
                scannerNotifier.processCameraScan(code);
              },
            ),
          ),
        ).then((_) => _isCameraDialogShowing = false);
      }

      if (next.showEventSelector && previous != null && (previous.showEventSelector == false) && !_isAnyDialogShowing) {
        debugPrint('🏠 LISTENER: Showing event selector dialog');
        _isEventSelectorShowing = true;
        showDialog(
          context: context,
          builder: (context) => EventSelectorDialog(
            events: next.availableEvents,
            onEventSelected: (event) {
              Navigator.of(context).pop();
              _isEventSelectorShowing = false;
              scannerNotifier.selectEvent(event);
            },
            onEventCreated: (event) async {
              Navigator.of(context).pop();
              _isEventSelectorShowing = false;
              try {
                await scannerNotifier.createEvent(event);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Event "${event.name}" created successfully!'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to create event: ${e.toString().replaceAll('Exception: ', '')}'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }
            },
            onDismiss: () {
              Navigator.of(context).pop();
              _isEventSelectorShowing = false;
              scannerNotifier.hideEventSelector();
            },
          ),
        ).then((_) => _isEventSelectorShowing = false);
      }

      if (next.showForgotIdDialog && previous != null && (previous.showForgotIdDialog == false) && !_isAnyDialogShowing) {
        debugPrint('🏠 LISTENER: Showing forgot ID dialog');
        _isForgotIdDialogShowing = true;
        showDialog(
          context: context,
          barrierDismissible: false, // Prevent dismissal by tapping outside
          builder: (context) => ForgotIdDialog(
            onDismiss: () {
              Navigator.of(context).pop();
              _isForgotIdDialogShowing = false;
              scannerNotifier.hideForgotIdDialog();
            },
          ),
        ).then((_) => _isForgotIdDialogShowing = false);
      }

      if (next.showStudentDialog && previous != null && (previous.showStudentDialog == false) && next.verifiedStudent != null && !_isAnyDialogShowing) {
        debugPrint('🏠 LISTENER: Showing student dialog');
        _isStudentDialogShowing = true;
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => StudentVerificationDialog(
            student: next.verifiedStudent,
            onDismiss: () {
              Navigator.of(context).pop();
              _isStudentDialogShowing = false;
              scannerNotifier.clearErrorMessage();
            },
          ),
        ).then((_) => _isStudentDialogShowing = false);
      }

      if (next.showDuplicateDialog && previous != null && (previous.showDuplicateDialog == false) && next.verifiedStudent != null && !_isAnyDialogShowing) {
        debugPrint('🏠 LISTENER: Showing duplicate dialog');
        _isDuplicateDialogShowing = true;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Duplicate Scan'),
            content: Text('${next.verifiedStudent!.fullName} has already been scanned for this event.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _isDuplicateDialogShowing = false;
                  // Use comprehensive state reset instead of just hiding duplicate dialog
                  scannerNotifier.clearErrorMessage();
                },
                child: const Text('OK'),
              ),
            ],
          ),
        ).then((_) => _isDuplicateDialogShowing = false);
      }

      // Handle error messages with dialog
      if (next.errorMessage != null && (previous?.errorMessage ?? '') != next.errorMessage) {
        if (!_isAnyDialogShowing) {
          _isErrorDialogShowing = true;
          debugPrint('🏠 LISTENER: Error message detected: "${next.errorMessage}"');
          debugPrint('🏠 LISTENER: Showing error dialog');
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text(
                'Scan Error',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Text(next.errorMessage!),
              actions: [
                TextButton(
                  onPressed: () {
                    debugPrint('🏠 LISTENER: Error dialog dismissed - about to pop dialog');
                    Navigator.of(context).pop();
                    _isErrorDialogShowing = false; // Reset dialog flag
                    debugPrint('🏠 LISTENER: Dialog popped, now calling clearErrorMessage()');
                    scannerNotifier.clearErrorMessage();
                    debugPrint('🏠 LISTENER: clearErrorMessage() called successfully');
                  },
                  child: const Text('OK'),
                ),
                TextButton(
                  onPressed: () {
                    debugPrint('🏠 LISTENER: Report button pressed - showing email input');
                    Navigator.of(context).pop(); // Close error dialog first
                    _isErrorDialogShowing = false;
                    _showReportDialog(context, scannerNotifier);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                  child: const Text('Report'),
                ),
              ],
            ),
          ).then((_) {
            // Ensure flag is reset even if dialog is dismissed other ways
            _isErrorDialogShowing = false;
          });
        } else {
          debugPrint('🏠 LISTENER: Dialog already showing, skipping new error dialog');
        }
      } else if (next.errorMessage != null) {
        debugPrint('🏠 LISTENER: Error message exists but not new: "${next.errorMessage}"');
      } else {
        debugPrint('🏠 LISTENER: No error message in state');
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'InSession',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              'Charleston Law',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1A237E), // Darker blue for better contrast
        foregroundColor: Colors.white,
        elevation: 4,
        toolbarHeight: 70, // Increased height for two-line title
        // Removed top-right forgot ID button - only keep bottom button
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorWeight: 3,
          tabs: const [
            Tab(
              icon: Icon(Icons.home, size: 24),
              text: 'Home',
            ),
            Tab(
              icon: Icon(Icons.qr_code_scanner, size: 24),
              text: 'Scans',
            ),
            Tab(
              icon: Icon(Icons.analytics, size: 24),
              text: 'Summary',
            ),
          ],
        ),
      ),
      body: scannerState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Home Tab
                _buildHomeTab(context, scannerState, scannerNotifier),
                // Scans Tab
                _buildScansTab(context, scannerState, scannerNotifier),
                // Summary Tab
                EventSummaryTab(
                  uiState: scannerState,
                  onCompleteEvent: () async {
                    try {
                      await scannerNotifier.completeEvent();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Event marked as completed'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error completing event: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  onReopenEvent: (event) async {
                    try {
                      await scannerNotifier.reopenEvent(event);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Event reopened successfully'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error reopening event: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
      // No floating action button - using integrated buttons in Home tab
    );
  }

  Widget _buildHomeTab(BuildContext context, ScannerState scannerState, scannerNotifier) {
    final lastScan = scannerState.scans.isNotEmpty ? scannerState.scans.first : null;
    
    return RefreshIndicator(
      onRefresh: () async {
        debugPrint('🔄 Pull to refresh triggered');
        // Reload events and current event data
        await scannerNotifier.loadEvents();
        if (scannerState.currentEvent != null) {
          await scannerNotifier.refreshCurrentEvent();
        }
        debugPrint('🔄 Pull to refresh completed');
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        children: [
          // Current Event Section
          EventHeaderCard(
            currentEvent: scannerState.currentEvent,
            onSelectEvent: () => scannerNotifier.showEventSelector(),
          ),
            
            const SizedBox(height: 20),
            
            // Status and Count Section
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 40,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Status',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (scannerState.isSyncing)
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                )
                              else
                                Icon(
                                  scannerState.isOnline 
                                    ? Icons.cloud_done 
                                    : Icons.cloud_off,
                                  size: 16,
                                  color: scannerState.isOnline 
                                    ? Colors.green 
                                    : Colors.orange,
                                ),
                              const SizedBox(width: 6),
                              Text(
                                scannerState.isOnline 
                                  ? (scannerState.isSyncing ? 'Syncing' : 'Online')
                                  : 'Offline',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: scannerState.isOnline 
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.orange,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              if (scannerState.pendingScansCount > 0)
                                Text(
                                  ' (${scannerState.pendingScansCount})',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.orange,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.tag,
                            size: 40,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Count',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${scannerState.scanCount}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Last Scan Section
            if (lastScan != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.qr_code_scanner,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Last Scan',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        lastScan.studentId,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        lastScan.studentName,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Student ID',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            '${lastScan.timestamp.hour.toString().padLeft(2, '0')}:${lastScan.timestamp.minute.toString().padLeft(2, '0')}:${lastScan.timestamp.second.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 40),
            
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: scannerState.currentEvent != null
                        ? () => scannerNotifier.showForgotIdDialog()
                        : null,
                    icon: const Icon(Icons.person_search),
                    label: const Text('Forgot ID?'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: scannerState.currentEvent != null
                        ? () => scannerNotifier.triggerScan()
                        : null,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('SCAN'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
            
          // Bottom spacing
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildScansTab(BuildContext context, ScannerState scannerState, scannerNotifier) {
    return RefreshIndicator(
      onRefresh: () async {
        debugPrint('🔄 Scans tab: Pull to refresh triggered');
        // Reload events and current event data
        await scannerNotifier.loadEvents();
        if (scannerState.currentEvent != null) {
          await scannerNotifier.refreshCurrentEvent();
        }
        debugPrint('🔄 Scans tab: Pull to refresh completed');
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: scannerState.scans.length + 2, // +2 for header and bottom spacing
        itemBuilder: (context, index) {
          if (index == 0) {
            // Event Header
            return EventHeaderCard(
              currentEvent: scannerState.currentEvent,
              onSelectEvent: () => scannerNotifier.showEventSelector(),
            );
          } else if (index <= scannerState.scans.length) {
            // Scan items
            return ScanItem(scan: scannerState.scans[index - 1]);
          } else {
            // Bottom spacing
            return const SizedBox(height: 80);
          }
        },
      ),
    );
  }

  void _showReportDialog(BuildContext context, ScannerNotifier scannerNotifier) {
    final TextEditingController emailController = TextEditingController();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text(
          'Report Scan Issue',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please provide the correct email address for this student:',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Student Email',
                hintText: 'student@charlestonlaw.edu',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              debugPrint('🏠 REPORT: Cancel button pressed');
              Navigator.of(context).pop();
              scannerNotifier.clearErrorMessage();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final email = emailController.text.trim();
              if (email.isNotEmpty && email.contains('@')) {
                debugPrint('🏠 REPORT: Submitting report with email: $email');
                // TODO: Update the error scan record with the provided email
                // For now, just show confirmation and close
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Report submitted with email: $email',
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 3),
                  ),
                );
                scannerNotifier.clearErrorMessage();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid email address'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Submit Report'),
          ),
        ],
      ),
    );
  }
}