import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/event.dart';
import '../models/student.dart';
import '../models/scan_record.dart';
import '../services/scanner_service.dart';
import '../services/firebase_service.dart';
import '../services/database_service.dart';

// Scanner State
class ScannerState {
  final Event? currentEvent;
  final List<Event> availableEvents;
  final List<ScanRecord> scans;
  final ScanRecord? lastScan;
  final Student? verifiedStudent;
  final Student? duplicateStudent;
  final List<Student> studentSearchResults;
  final String? scannedStudentId;
  final String? errorMessage;
  final bool isScanning;
  final bool isConnected;
  final bool isSearchingStudents;
  final bool showStudentDialog;
  final bool showDuplicateDialog;
  final bool showForgotIdDialog;
  final bool showEventSelector;
  final bool showNewEventDialog;
  final bool showNoEventDialog;
  final bool showCameraPreview;
  final int scanCount;
  final int uniqueStudentCount;
  final int duplicateScanCount;
  final int errorCount;
  final int forgotIdCount;

  const ScannerState({
    this.currentEvent,
    this.availableEvents = const [],
    this.scans = const [],
    this.lastScan,
    this.verifiedStudent,
    this.duplicateStudent,
    this.studentSearchResults = const [],
    this.scannedStudentId,
    this.errorMessage,
    this.isScanning = false,
    this.isConnected = false,
    this.isSearchingStudents = false,
    this.showStudentDialog = false,
    this.showDuplicateDialog = false,
    this.showForgotIdDialog = false,
    this.showEventSelector = false,
    this.showNewEventDialog = false,
    this.showNoEventDialog = false,
    this.showCameraPreview = false,
    this.scanCount = 0,
    this.uniqueStudentCount = 0,
    this.duplicateScanCount = 0,
    this.errorCount = 0,
    this.forgotIdCount = 0,
  });

  ScannerState copyWith({
    Event? currentEvent,
    List<Event>? availableEvents,
    List<ScanRecord>? scans,
    ScanRecord? lastScan,
    Student? verifiedStudent,
    Student? duplicateStudent,
    List<Student>? studentSearchResults,
    String? scannedStudentId,
    String? errorMessage,
    bool? isScanning,
    bool? isConnected,
    bool? isSearchingStudents,
    bool? showStudentDialog,
    bool? showDuplicateDialog,
    bool? showForgotIdDialog,
    bool? showEventSelector,
    bool? showNewEventDialog,
    bool? showNoEventDialog,
    bool? showCameraPreview,
    int? scanCount,
    int? uniqueStudentCount,
    int? duplicateScanCount,
    int? errorCount,
    int? forgotIdCount,
  }) {
    return ScannerState(
      currentEvent: currentEvent ?? this.currentEvent,
      availableEvents: availableEvents ?? this.availableEvents,
      scans: scans ?? this.scans,
      lastScan: lastScan ?? this.lastScan,
      verifiedStudent: verifiedStudent ?? this.verifiedStudent,
      duplicateStudent: duplicateStudent ?? this.duplicateStudent,
      studentSearchResults: studentSearchResults ?? this.studentSearchResults,
      scannedStudentId: scannedStudentId ?? this.scannedStudentId,
      errorMessage: errorMessage ?? this.errorMessage,
      isScanning: isScanning ?? this.isScanning,
      isConnected: isConnected ?? this.isConnected,
      isSearchingStudents: isSearchingStudents ?? this.isSearchingStudents,
      showStudentDialog: showStudentDialog ?? this.showStudentDialog,
      showDuplicateDialog: showDuplicateDialog ?? this.showDuplicateDialog,
      showForgotIdDialog: showForgotIdDialog ?? this.showForgotIdDialog,
      showEventSelector: showEventSelector ?? this.showEventSelector,
      showNewEventDialog: showNewEventDialog ?? this.showNewEventDialog,
      showNoEventDialog: showNoEventDialog ?? this.showNoEventDialog,
      showCameraPreview: showCameraPreview ?? this.showCameraPreview,
      scanCount: scanCount ?? this.scanCount,
      uniqueStudentCount: uniqueStudentCount ?? this.uniqueStudentCount,
      duplicateScanCount: duplicateScanCount ?? this.duplicateScanCount,
      errorCount: errorCount ?? this.errorCount,
      forgotIdCount: forgotIdCount ?? this.forgotIdCount,
    );
  }
}

// Scanner Notifier
class ScannerNotifier extends StateNotifier<ScannerState> {
  final ScannerService _scannerService;
  final FirebaseService _firebaseService;
  final DatabaseService _databaseService;

  ScannerNotifier(
    this._scannerService,
    this._firebaseService,
    this._databaseService,
  ) : super(const ScannerState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    // Initialize scanner service
    await _scannerService.initialize();
    
    // Load events from database
    await _loadEvents();
    
    // Check connectivity
    await _checkConnectivity();
    
    // Load scans for current event
    if (state.currentEvent != null) {
      await _loadScans();
    }
  }

  Future<void> _loadEvents() async {
    try {
      final events = await _databaseService.getAllEvents();
      state = state.copyWith(availableEvents: events);
      
      // Set current event if none selected
      if (state.currentEvent == null && events.isNotEmpty) {
        final activeEvent = events.where((e) => e.isActive).firstOrNull;
        if (activeEvent != null) {
          state = state.copyWith(currentEvent: activeEvent);
        }
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load events: $e');
    }
  }

  Future<void> _loadScans() async {
    if (state.currentEvent == null) return;
    
    try {
      final scans = await _databaseService.getScansForEvent(state.currentEvent!.id);
      final scanCount = scans.length;
      final uniqueStudents = scans.map((s) => s.studentId).toSet().length;
      final duplicates = scanCount - uniqueStudents;
      
      state = state.copyWith(
        scans: scans,
        scanCount: scanCount,
        uniqueStudentCount: uniqueStudents,
        duplicateScanCount: duplicates,
        lastScan: scans.isNotEmpty ? scans.first : null,
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load scans: $e');
    }
  }

  Future<void> _checkConnectivity() async {
    final isConnected = _firebaseService.isConnected;
    state = state.copyWith(isConnected: isConnected);
  }

  // Public methods
  Future<void> triggerScan() async {
    if (state.currentEvent == null) {
      state = state.copyWith(showNoEventDialog: true);
      return;
    }

    state = state.copyWith(isScanning: true, errorMessage: null);
    
    try {
      final scanResult = await _scannerService.scan();
      await _processScanResult(scanResult);
    } catch (e) {
      state = state.copyWith(
        isScanning: false,
        errorMessage: 'Scan failed: $e',
      );
    }
  }

  Future<void> _processScanResult(ScanResult scanResult) async {
    state = state.copyWith(isScanning: false);
    
    // Create scan record
    final scanRecord = ScanRecord.create(
      code: scanResult.code,
      symbology: scanResult.symbology,
      eventId: state.currentEvent!.id,
    );
    
    // Save to local database
    await _databaseService.insertScan(scanRecord);
    
    // Try to sync to Firebase
    if (state.isConnected) {
      try {
        await _firebaseService.uploadScan(scanRecord);
      } catch (e) {
        // Sync will happen later when connection is restored
      }
    }
    
    // Look up student
    final student = await _databaseService.getStudentById(scanResult.code);
    
    if (student != null) {
      // Check for duplicates
      final existingScans = await _databaseService.getScansForStudentInEvent(
        student.studentId,
        state.currentEvent!.id,
      );
      
      if (existingScans.isNotEmpty) {
        state = state.copyWith(
          showDuplicateDialog: true,
          duplicateStudent: student,
          scannedStudentId: scanResult.code,
        );
      } else {
        state = state.copyWith(
          showStudentDialog: true,
          verifiedStudent: student,
          scannedStudentId: scanResult.code,
        );
      }
    } else {
      // Student not found - show error dialog
      state = state.copyWith(
        errorMessage: 'Student ID ${scanResult.code} not found in database',
      );
    }
    
    // Reload scans
    await _loadScans();
  }

  void showEventSelector() {
    state = state.copyWith(showEventSelector: true);
  }

  void hideEventSelector() {
    state = state.copyWith(showEventSelector: false);
  }

  void showNewEventDialog() {
    state = state.copyWith(
      showEventSelector: false,
      showNewEventDialog: true,
    );
  }

  void hideNewEventDialog() {
    state = state.copyWith(showNewEventDialog: false);
  }

  void showForgotIdDialog() {
    if (state.currentEvent == null) {
      state = state.copyWith(showNoEventDialog: true);
      return;
    }
    state = state.copyWith(showForgotIdDialog: true);
  }

  void hideForgotIdDialog() {
    state = state.copyWith(
      showForgotIdDialog: false,
      studentSearchResults: [],
      isSearchingStudents: false,
    );
  }

  void hideStudentDialog() {
    state = state.copyWith(
      showStudentDialog: false,
      verifiedStudent: null,
      scannedStudentId: null,
    );
  }

  void dismissDuplicateDialog() {
    state = state.copyWith(
      showDuplicateDialog: false,
      duplicateStudent: null,
      scannedStudentId: null,
    );
  }

  void dismissNoEventDialog() {
    state = state.copyWith(showNoEventDialog: false);
  }

  Future<void> selectEvent(Event event) async {
    state = state.copyWith(
      currentEvent: event,
      showEventSelector: false,
    );
    await _loadScans();
  }

  Future<void> createNewEvent(int eventNumber, String name, String description) async {
    try {
      final event = Event.createNew(
        eventNumber: eventNumber,
        name: name,
        description: description,
      );
      
      await _databaseService.insertEvent(event);
      await _loadEvents();
      
      state = state.copyWith(
        currentEvent: event,
        showNewEventDialog: false,
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to create event: $e');
    }
  }

  Future<void> searchStudents(String query) async {
    if (query.isEmpty) {
      state = state.copyWith(studentSearchResults: []);
      return;
    }
    
    state = state.copyWith(isSearchingStudents: true);
    
    try {
      final students = await _databaseService.searchStudents(query);
      state = state.copyWith(
        studentSearchResults: students,
        isSearchingStudents: false,
      );
    } catch (e) {
      state = state.copyWith(
        isSearchingStudents: false,
        errorMessage: 'Search failed: $e',
      );
    }
  }

  Future<void> manualCheckIn(Student student) async {
    if (state.currentEvent == null) return;
    
    try {
      // Create scan record for manual check-in
      final scanRecord = ScanRecord.create(
        code: student.studentId,
        symbology: 'MANUAL',
        eventId: state.currentEvent!.id,
        studentId: student.studentId,
      );
      
      await _databaseService.insertScan(scanRecord);
      
      // Sync to Firebase if connected
      if (state.isConnected) {
        await _firebaseService.uploadScan(scanRecord);
      }
      
      state = state.copyWith(
        showForgotIdDialog: false,
        studentSearchResults: [],
        forgotIdCount: state.forgotIdCount + 1,
      );
      
      await _loadScans();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Manual check-in failed: $e');
    }
  }

  Future<void> completeCurrentEvent() async {
    if (state.currentEvent == null) return;
    
    try {
      final completedEvent = state.currentEvent!.copyWith(
        isCompleted: true,
        completedAt: DateTime.now(),
        isActive: false,
      );
      
      await _databaseService.updateEvent(completedEvent);
      
      // Notify Firebase
      if (state.isConnected) {
        await _firebaseService.notifyEventCompleted(
          completedEvent,
          state.scanCount,
        );
      }
      
      state = state.copyWith(currentEvent: completedEvent);
      await _loadEvents();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to complete event: $e');
    }
  }

  Future<void> reopenEvent(Event event) async {
    try {
      final reopenedEvent = event.copyWith(
        isCompleted: false,
        completedAt: null,
        isActive: true,
      );
      
      await _databaseService.updateEvent(reopenedEvent);
      
      state = state.copyWith(currentEvent: reopenedEvent);
      await _loadEvents();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to reopen event: $e');
    }
  }

  Future<void> submitErrorRecord(String scannedId, String email) async {
    if (state.currentEvent == null) return;
    
    try {
      await _firebaseService.saveErrorRecord(
        scannedId,
        email,
        state.currentEvent!.id,
        state.currentEvent!.name,
        state.currentEvent!.formattedDate,
      );
      
      state = state.copyWith(
        showStudentDialog: false,
        verifiedStudent: null,
        scannedStudentId: null,
        errorCount: state.errorCount + 1,
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to submit error record: $e');
    }
  }
}

// Providers
final scannerServiceProvider = Provider<ScannerService>((ref) {
  return ScannerService();
});

final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  return FirebaseService.instance;
});

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

final scannerProvider = StateNotifierProvider<ScannerNotifier, ScannerState>((ref) {
  return ScannerNotifier(
    ref.read(scannerServiceProvider),
    ref.read(firebaseServiceProvider),
    ref.read(databaseServiceProvider),
  );
});

// Extension for null safety
extension IterableExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
