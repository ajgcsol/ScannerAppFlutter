import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/scanner_provider.dart';
import '../widgets/event_header_card.dart';
import '../widgets/scan_item.dart';
import '../widgets/event_selector_dialog.dart';
import '../widgets/forgot_id_dialog.dart';
import '../widgets/student_verification_dialog.dart';
import '../screens/camera_preview_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: () => scannerNotifier.showForgotIdDialog(),
          ),
        ],
      ),
      body: scannerState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  EventHeaderCard(
                    currentEvent: scannerState.currentEvent,
                    onSelectEvent: () => scannerNotifier.showEventSelector(),
                  ),
                  if (scannerState.showEventSelector)
                    EventSelectorDialog(
                      events: scannerState.availableEvents,
                      onEventSelected: (event) => scannerNotifier.selectEvent(event),
                      onDismiss: () => scannerNotifier.hideEventSelector(),
                    ),
                  if (scannerState.showForgotIdDialog)
                    ForgotIdDialog(
                      onDismiss: () => scannerNotifier.hideForgotIdDialog(),
                    ),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: scannerState.scans.length,
                    itemBuilder: (context, index) {
                      return ScanItem(scan: scannerState.scans[index]);
                    },
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => scannerNotifier.triggerScan(),
        label: const Text('SCAN'),
        icon: const Icon(Icons.qr_code_scanner),
      ),
    );
  }
}
