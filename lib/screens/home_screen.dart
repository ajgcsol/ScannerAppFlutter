import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/loading_splash_screen.dart';
import '../widgets/event_header_card.dart';
import '../widgets/status_card.dart';
import '../widgets/last_scan_card.dart';
import '../widgets/scan_item.dart';
import '../widgets/event_summary_tab.dart';
import '../widgets/event_selector_dialog.dart';
import '../widgets/forgot_id_dialog.dart';
import '../widgets/student_verification_dialog.dart';
import '../widgets/new_event_dialog.dart';
import '../widgets/duplicate_scan_dialog.dart';
import '../screens/camera_preview_screen.dart';
import '../providers/scanner_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  int _selectedTabIndex = 0;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Show loading animation for 2 seconds on initial load
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showAppInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info, color: Colors.blue),
            SizedBox(width: 8),
            Text('About InSession'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Charleston Law Event Scanner',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 12),
            Text('Author: Andrew Gregware'),
            Text('Co-Author: Claude Code'),
            SizedBox(height: 8),
            Text('Created: August 30, 2025'),
            Text('Last Updated: January 2025'),
            SizedBox(height: 8),
            Text('Flutter iOS Port - Phase 1'),
            SizedBox(height: 8),
            Text(
              'GitHub Repository:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            Text(
              'github.com/ajgcsol/ScannerAppFlutter',
              style: TextStyle(color: Colors.blue, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSupportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.support_agent, color: Colors.green),
            SizedBox(width: 8),
            Text('Support'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Need help with the scanner app?'),
            SizedBox(height: 12),
            Text('• Check the FAQ in the Summary tab'),
            Text('• Contact IT Support for technical issues'),
            Text('• Report bugs via the admin portal'),
            SizedBox(height: 12),
            Text(
              'Emergency Contact:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('IT Support: ext. 1234'),
            Text('Admin Portal: localhost:8080'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const LoadingSplashScreen();
    }

    final scannerState = ref.watch(scannerProvider);
    final scannerNotifier = ref.read(scannerProvider.notifier);

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Icon(Icons.fact_check, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Charleston Law Event Scanner',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.info),
                onPressed: _showAppInfoDialog,
              ),
              IconButton(
                icon: const Icon(Icons.support),
                onPressed: _showSupportDialog,
              ),
            ],
          ),
          body: Column(
            children: [
              const SizedBox(height: 8),

              // Event Selection Card
              EventHeaderCard(
                currentEvent: scannerState.currentEvent,
                onSelectEvent: () => scannerNotifier.showEventSelector(),
              ),

              const SizedBox(height: 16),

              // Tab Bar
              TabBar(
                controller: _tabController,
                onTap: (index) => setState(() => _selectedTabIndex = index),
                tabs: const [
                  Tab(text: 'Home'),
                  Tab(text: 'Scans'),
                  Tab(text: 'Summary'),
                ],
              ),

              const SizedBox(height: 16),

              // Tab Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildHomeTab(scannerState),
                    _buildScansTab(scannerState),
                    EventSummaryTab(
                      uiState: scannerState,
                      onCompleteEvent: () =>
                          scannerNotifier.completeCurrentEvent(),
                      onReopenEvent: (event) =>
                          scannerNotifier.reopenEvent(event),
                    ),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: _selectedTabIndex == 0
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Forgot ID Button
                    FloatingActionButton.extended(
                      heroTag: "forgot_id",
                      onPressed: () => scannerNotifier.showForgotIdDialog(),
                      backgroundColor: Colors.green,
                      icon: const Icon(Icons.person_search),
                      label: const Text('FORGOT ID?'),
                    ),

                    const SizedBox(width: 12),

                    // Main Scan Button
                    FloatingActionButton.extended(
                      heroTag: "scan",
                      onPressed: () => scannerNotifier.triggerScan(),
                      backgroundColor: Theme.of(context).primaryColor,
                      icon: scannerState.isScanning
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.qr_code_scanner),
                      label: Text(
                          scannerState.isScanning ? 'Scanning...' : 'SCAN'),
                    ),
                  ],
                )
              : null,
        ),

        // Dialog Overlays
        if (scannerState.showEventSelector)
          EventSelectorDialog(
            events: scannerState.availableEvents,
            currentEvent: scannerState.currentEvent,
            onEventSelected: (event) => scannerNotifier.selectEvent(event),
            onCreateNewEvent: () => scannerNotifier.showNewEventDialog(),
            onDismiss: () => scannerNotifier.hideEventSelector(),
          ),

        if (scannerState.showNewEventDialog)
          NewEventDialog(
            onCreateEvent: (eventNumber, name, description) =>
                scannerNotifier.createNewEvent(eventNumber, name, description),
            onDismiss: () => scannerNotifier.hideNewEventDialog(),
          ),

        if (scannerState.showForgotIdDialog)
          ForgotIdDialog(
            onDismiss: () => scannerNotifier.hideForgotIdDialog(),
            onSearchStudents: (query) => scannerNotifier.searchStudents(query),
            searchResults: scannerState.studentSearchResults,
            isSearching: scannerState.isSearchingStudents,
            onStudentSelected: (student) =>
                scannerNotifier.manualCheckIn(student),
          ),

        if (scannerState.showStudentDialog &&
            scannerState.scannedStudentId != null)
          StudentVerificationDialog(
            student: scannerState.verifiedStudent,
            scannedId: scannerState.scannedStudentId!,
            onDismiss: () => scannerNotifier.hideStudentDialog(),
            onSubmitErrorRecord: (scannedId, email) =>
                scannerNotifier.submitErrorRecord(scannedId, email),
          ),

        if (scannerState.showDuplicateDialog &&
            scannerState.scannedStudentId != null)
          DuplicateScanDialog(
            student: scannerState.duplicateStudent,
            studentId: scannerState.scannedStudentId!,
            onDismiss: () => scannerNotifier.dismissDuplicateDialog(),
          ),

        // Camera Preview Screen
        if (scannerState.showCameraPreview)
          CameraPreviewScreen(
            onBarcodeScanned: (code) => scannerNotifier.processCameraScan(code),
            onClose: () => scannerNotifier.hideCameraPreview(),
          ),

        // No Event Selected Dialog
        if (scannerState.showNoEventDialog)
          AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 8),
                Text('No Event Selected'),
              ],
            ),
            content: const Text(
                'Please select or create an event before scanning or using the Forgot ID feature.'),
            actions: [
              TextButton(
                onPressed: () => scannerNotifier.dismissNoEventDialog(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  scannerNotifier.dismissNoEventDialog();
                  scannerNotifier.showEventSelector();
                },
                child: const Text('Select Event'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildHomeTab(ScannerState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Status Cards
          Row(
            children: [
              Expanded(
                child: StatusCard(
                  title: 'Status',
                  value: state.isConnected ? 'Connected' : 'Disconnected',
                  icon: state.isConnected ? Icons.check_circle : Icons.error,
                  color: state.isConnected
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatusCard(
                  title: 'Count',
                  value: state.scanCount.toString(),
                  icon: Icons.numbers,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Last Scan Card
          if (state.lastScan != null) ...[
            LastScanCard(scan: state.lastScan!),
            const SizedBox(height: 16),
          ],

          // Error Message
          if (state.errorMessage != null) ...[
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildScansTab(ScannerState state) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: state.scans.length > 15 ? 15 : state.scans.length,
      itemBuilder: (context, index) {
        return ScanItem(scan: state.scans[index]);
      },
    );
  }
}
