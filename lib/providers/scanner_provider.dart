import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/event.dart';
import '../models/student.dart';
import '../models/scan.dart';
import '../services/scanner_service.dart';

// Scanner State
@immutable
class ScannerState {
  final Event? currentEvent;
  final List<Event> availableEvents;
  final List<Scan> scans;
  final Student? verifiedStudent;
  final String? errorMessage;
  final bool isScanning;
  final bool showStudentDialog;
  final bool showDuplicateDialog;
  final bool showForgotIdDialog;
  final bool showEventSelector;
  final bool showCameraPreview;
  final bool isLoading; // Added loading state

  const ScannerState({
    this.currentEvent,
    this.availableEvents = const [],
    this.scans = const [],
    this.verifiedStudent,
    this.errorMessage,
    this.isScanning = false,
    this.showStudentDialog = false,
    this.showDuplicateDialog = false,
    this.showForgotIdDialog = false,
    this.showEventSelector = false,
    this.showCameraPreview = false,
    this.isLoading = false, // Default to false
  });

  ScannerState copyWith({
    Event? currentEvent,
    List<Event>? availableEvents,
    List<Scan>? scans,
    Student? verifiedStudent,
    String? errorMessage,
    bool? isScanning,
    bool? showStudentDialog,
    bool? showDuplicateDialog,
    bool? showForgotIdDialog,
    bool? showEventSelector,
    bool? showCameraPreview,
    bool? isLoading, // Add to copyWith
  }) {
    return ScannerState(
      currentEvent: currentEvent ?? this.currentEvent,
      availableEvents: availableEvents ?? this.availableEvents,
      scans: scans ?? this.scans,
      verifiedStudent: verifiedStudent ?? this.verifiedStudent,
      errorMessage: errorMessage ?? this.errorMessage,
      isScanning: isScanning ?? this.isScanning,
      showStudentDialog: showStudentDialog ?? this.showStudentDialog,
      showDuplicateDialog: showDuplicateDialog ?? this.showDuplicateDialog,
      showForgotIdDialog: showForgotIdDialog ?? this.showForgotIdDialog,
      showEventSelector: showEventSelector ?? this.showEventSelector,
      showCameraPreview: showCameraPreview ?? this.showCameraPreview,
      isLoading: isLoading ?? this.isLoading, // Add to copyWith
    );
  }
}

// Scanner Notifier
class ScannerNotifier extends StateNotifier<ScannerState> {
  final ScannerService _scannerService;

  ScannerNotifier(this._scannerService) : super(const ScannerState(isLoading: true)) {
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadEvents();
    if (state.currentEvent != null) {
      await _loadScansForCurrentEvent();
    }
    state = state.copyWith(isLoading: false);
  }

  Future<void> _loadEvents() async {
    final events = await _scannerService.getEvents();
    if (events.isNotEmpty) {
      state = state.copyWith(availableEvents: events, currentEvent: events.first);
    } else {
      state = state.copyWith(availableEvents: []);
    }
  }

  Future<void> _loadScansForCurrentEvent() async {
    if (state.currentEvent == null) return;
    final scans = await _scannerService.getScansForEvent(state.currentEvent!.id);
    state = state.copyWith(scans: scans);
  }

  Future<void> triggerScan() async {
    state = state.copyWith(showCameraPreview: true);
  }

  Future<void> processCameraScan(String code) async {
    state = state.copyWith(showCameraPreview: false, isScanning: true);
    final scanResult = ScanResult(code: code, timestamp: DateTime.now());
    await _processScanResult(scanResult);
    state = state.copyWith(isScanning: false);
  }

  Future<void> _processScanResult(ScanResult scanResult) async {
    final student = await _scannerService.getStudentById(scanResult.code);
    if (student != null) {
      final isDuplicate = state.scans.any((s) => s.studentId == student.studentId);
      if (isDuplicate) {
        state = state.copyWith(showDuplicateDialog: true, verifiedStudent: student);
        return;
      }

      final newScan = Scan(
        studentId: student.studentId,
        timestamp: scanResult.timestamp,
        studentName: student.fullName,
        studentEmail: student.email,
      );
      await _scannerService.recordScan(state.currentEvent!.id, newScan);
      final updatedScans = [newScan, ...state.scans];
      state = state.copyWith(
        scans: updatedScans,
        verifiedStudent: student,
        showStudentDialog: true,
      );
    } else {
      await _scannerService.recordError(state.currentEvent!.id, scanResult.code);
      state = state.copyWith(errorMessage: 'Student not found. Error has been logged.');
    }
  }

  void showEventSelector() {
    state = state.copyWith(showEventSelector: true);
  }

  void hideEventSelector() {
    state = state.copyWith(showEventSelector: false);
  }

  void showForgotIdDialog() {
    state = state.copyWith(showForgotIdDialog: true);
  }

  void hideForgotIdDialog() {
    state = state.copyWith(showForgotIdDialog: false);
  }

  void hideStudentDialog() {
    state = state.copyWith(showStudentDialog: false, verifiedStudent: null);
  }

  void hideDuplicateDialog() {
    state = state.copyWith(showDuplicateDialog: false, verifiedStudent: null);
  }

  Future<void> selectEvent(Event event) async {
    state = state.copyWith(isLoading: true, currentEvent: event, showEventSelector: false, scans: []);
    await _loadScansForCurrentEvent();
    state = state.copyWith(isLoading: false);
  }
}

// Providers
final scannerServiceProvider = Provider<ScannerService>((ref) {
  return ScannerService();
});

final scannerProvider =
    StateNotifierProvider<ScannerNotifier, ScannerState>((ref) {
  return ScannerNotifier(ref.read(scannerServiceProvider));
});
