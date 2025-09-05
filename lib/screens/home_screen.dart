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
      if (next.showCameraPreview && (previous?.showCameraPreview ?? false) == false) {
        showDialog(
          context: context,
          builder: (context) => Dialog(
            child: CameraPreviewScreen(
              onScan: (code) {
                Navigator.of(context).pop();
                scannerNotifier.processCameraScan(code);
              },
            ),
          ),
        );
      }

      if (next.showEventSelector && (previous?.showEventSelector ?? false) == false) {
        showDialog(
          context: context,
          builder: (context) => EventSelectorDialog(
            events: next.availableEvents,
            onEventSelected: (event) {
              Navigator.of(context).pop();
              scannerNotifier.selectEvent(event);
            },
            onDismiss: () {
              Navigator.of(context).pop();
              scannerNotifier.hideEventSelector();
            },
          ),
        );
      }

      if (next.showForgotIdDialog && (previous?.showForgotIdDialog ?? false) == false) {
        showDialog(
          context: context,
          builder: (context) => ForgotIdDialog(
            onDismiss: () {
              Navigator.of(context).pop();
              scannerNotifier.hideForgotIdDialog();
            },
          ),
        );
      }

      if (next.showStudentDialog && next.verifiedStudent != null) {
        showDialog(
          context: context,
          builder: (context) => StudentVerificationDialog(
            student: next.verifiedStudent,
            onDismiss: () {
              Navigator.of(context).pop();
              scannerNotifier.hideStudentDialog();
            },
          ),
        );
      }

      if (next.showDuplicateDialog && next.verifiedStudent != null) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Duplicate Scan'),
            content: Text('${next.verifiedStudent!.fullName} has already been scanned for this event.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  scannerNotifier.hideDuplicateDialog();
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
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
                  onCompleteEvent: () {
                    // TODO: Implement event completion
                  },
                  onReopenEvent: (event) {
                    // TODO: Implement event reopening
                  },
                ),
              ],
            ),
      // No floating action button - using integrated buttons in Home tab
    );
  }

  Widget _buildHomeTab(BuildContext context, ScannerState scannerState, scannerNotifier) {
    final lastScan = scannerState.scans.isNotEmpty ? scannerState.scans.first : null;
    
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                          Text(
                            'Connected',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
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
      ),
    );
  }

  Widget _buildScansTab(BuildContext context, ScannerState scannerState, scannerNotifier) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Event Header
          EventHeaderCard(
            currentEvent: scannerState.currentEvent,
            onSelectEvent: () => scannerNotifier.showEventSelector(),
          ),
          
          // Scan List
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: scannerState.scans.length,
            itemBuilder: (context, index) {
              return ScanItem(scan: scannerState.scans[index]);
            },
          ),
          
          // Bottom spacing for FAB
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}