import 'package:flutter/foundation.dart';
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

  // Computed properties from actual scan data
  int get manualCheckInCount =>
      scans.where((scan) => scan.symbology == 'MANUAL').length;
  int get verifiedScanCount => scans.where((scan) => scan.processed).length;
  int get unverifiedScanCount => scans.where((scan) => !scan.processed).length;

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
    // Initialize Firebase first
    await _firebaseService.initialize();

    // Initialize scanner service
    await _scannerService.initialize();

    // Load events from appropriate source
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
      if (kIsWeb) {
        // Web: Use Firebase directly
        if (_firebaseService.isAvailable) {
          try {
            // Listen to Firebase events stream with error handling
            _firebaseService.getEvents().listen(
              (events) {
                state = state.copyWith(availableEvents: events);

                // Set current event if none selected
                if (state.currentEvent == null && events.isNotEmpty) {
                  final activeEvent =
                      events.where((e) => e.isActive).firstOrNull;
                  if (activeEvent != null) {
                    state = state.copyWith(currentEvent: activeEvent);
                  } else {
                    state = state.copyWith(currentEvent: events.first);
                  }
                }
              },
              onError: (error) {
                debugPrint('Firebase events stream error: $error');
                _loadMockEvents();
              },
            );

            // If no events in Firebase, create a demo event
            try {
              final currentEvents =
                  await _firebaseService.getEvents().first.timeout(
                        const Duration(seconds: 5),
                        onTimeout: () => <Event>[],
                      );
              if (currentEvents.isEmpty) {
                final demoEvent = _getMockEvents().first;
                await _firebaseService.addEvent(demoEvent);
              }
            } catch (e) {
              debugPrint('Failed to check/create demo event: $e');
              _loadMockEvents();
            }
          } catch (e) {
            debugPrint('Failed to load from Firebase, using mock data: $e');
            _loadMockEvents();
          }
        } else {
          _loadMockEvents();
        }
      } else {
        // Mobile/Desktop: Use SQLite database with Firebase sync
        final events = await _databaseService.getAllEvents();
        state = state.copyWith(availableEvents: events);

        // Set current event if none selected
        if (state.currentEvent == null && events.isNotEmpty) {
          final activeEvent = events.where((e) => e.isActive).firstOrNull;
          if (activeEvent != null) {
            state = state.copyWith(currentEvent: activeEvent);
          }
        }

        // Sync with Firebase in background if available
        if (_firebaseService.isAvailable) {
          _syncEventsWithFirebase();
        }
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load events: $e');
      _loadMockEvents();
    }
  }

  Future<void> _syncEventsWithFirebase() async {
    try {
      // This runs in background for mobile/desktop to sync with Firebase
      final localEvents = await _databaseService.getAllEvents();
      for (final event in localEvents) {
        await _firebaseService.addEvent(event);
      }
    } catch (e) {
      debugPrint('Background Firebase sync failed: $e');
    }
  }

  void _loadMockEvents() {
    final mockEvents = _getMockEvents();
    state = state.copyWith(availableEvents: mockEvents);

    if (state.currentEvent == null && mockEvents.isNotEmpty) {
      state = state.copyWith(currentEvent: mockEvents.first);
    }
  }

  List<Event> _getMockEvents() {
    return [
      Event(
        id: 'OSor8OVvwq39fMkharTO', // Use the actual event ID from Firestore
        eventNumber: 4,
        name: 'happy day',
        description: 'Event #4 - happy day',
        date: DateTime.now(),
        location: 'Charleston Law School',
        isActive: true,
        isCompleted: false,
        createdAt: DateTime.now(),
        createdBy: 'Android App',
        exportFormat: ExportFormat.textDelimited,
      ),
    ];
  }

  List<Student> _getMockStudents() {
    return [
      const Student(
        studentId: 'DEMO_001',
        firstName: 'John',
        lastName: 'Doe',
        email: 'john.doe@charlestonlaw.edu',
        program: 'JD',
        year: '2L',
        active: true,
      ),
      const Student(
        studentId: 'DEMO_002',
        firstName: 'Jane',
        lastName: 'Smith',
        email: 'jane.smith@charlestonlaw.edu',
        program: 'JD',
        year: '3L',
        active: true,
      ),
      const Student(
        studentId: '1234567890123',
        firstName: 'Test',
        lastName: 'Student',
        email: 'test.student@charlestonlaw.edu',
        program: 'JD',
        year: '1L',
        active: true,
      ),
    ];
  }

  Future<void> _loadScans() async {
    if (state.currentEvent == null) return;

    try {
      if (kIsWeb) {
        // Web: Load scans from Firebase
        if (_firebaseService.isAvailable) {
          _firebaseService
              .getScanRecords(eventId: state.currentEvent!.id)
              .listen((scans) {
            final scanCount = scans.length;
            final uniqueStudents = scans
                .map((s) => s.studentId)
                .where((id) => id != null)
                .toSet()
                .length;
            final duplicates = scanCount - uniqueStudents;

            state = state.copyWith(
              scans: scans,
              scanCount: scanCount,
              uniqueStudentCount: uniqueStudents,
              duplicateScanCount: duplicates,
              lastScan: scans.isNotEmpty ? scans.first : null,
            );
          });
        } else {
          // Fallback to empty state
          state = state.copyWith(
            scans: [],
            scanCount: 0,
            uniqueStudentCount: 0,
            duplicateScanCount: 0,
            lastScan: null,
          );
        }
      } else {
        // Mobile/Desktop: Load from SQLite
        final scans =
            await _databaseService.getScansForEvent(state.currentEvent!.id);
        final scanCount = scans.length;
        final uniqueStudents = scans
            .map((s) => s.studentId)
            .where((id) => id != null)
            .toSet()
            .length;
        final duplicates = scanCount - uniqueStudents;

        state = state.copyWith(
          scans: scans,
          scanCount: scanCount,
          uniqueStudentCount: uniqueStudents,
          duplicateScanCount: duplicates,
          lastScan: scans.isNotEmpty ? scans.first : null,
        );
      }
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

    if (kIsWeb) {
      // Web: Use mock scanning
      state = state.copyWith(isScanning: true, errorMessage: null);

      try {
        await Future.delayed(const Duration(seconds: 1));
        final mockCodes = [
          '1234567890123',
          'DEMO_001',
          'DEMO_002',
          'TEST_STUDENT'
        ];
        final mockCode =
            mockCodes[DateTime.now().millisecond % mockCodes.length];

        final scanResult = ScanResult(
          code: mockCode,
          symbology: 'DEMO',
          timestamp: DateTime.now(),
        );
        await _processScanResult(scanResult);
      } catch (e) {
        state = state.copyWith(
          isScanning: false,
          errorMessage: 'Scan failed: $e',
        );
      }
    } else {
      // Mobile: Show camera preview
      showCameraPreview();
    }
  }

  void showCameraPreview() {
    state = state.copyWith(showCameraPreview: true);
  }

  void hideCameraPreview() {
    state = state.copyWith(showCameraPreview: false);
  }

  Future<void> processCameraScan(String code) async {
    // Hide camera preview first
    hideCameraPreview();

    // Process the scanned code
    final scanResult = ScanResult(
      code: code,
      symbology: 'CAMERA',
      timestamp: DateTime.now(),
    );

    await _processScanResult(scanResult);
  }

  Future<void> _processScanResult(ScanResult scanResult) async {
    state = state.copyWith(isScanning: false);

    // Create scan record
    final scanRecord = ScanRecord.create(
      code: scanResult.code,
      symbology: scanResult.symbology,
      eventId: state.currentEvent!.id,
    );

    // Look up student first
    Student? student;
    if (kIsWeb) {
      // Web: Look up student from Firebase
      if (_firebaseService.isAvailable) {
        student = await _firebaseService.getStudent(scanResult.code);
      }

      // Fallback to mock students if Firebase not available or student not found
      if (student == null) {
        final mockStudents = _getMockStudents();
        student = mockStudents
            .where((s) => s.studentId == scanResult.code)
            .firstOrNull;
      }
    } else {
      // Mobile/Desktop: Look up from SQLite
      student = await _databaseService.getStudentById(scanResult.code);
    }

    // Update scan record with student info if found and mark as processed/verified
    final updatedScanRecord = student != null
        ? scanRecord.copyWith(
            studentId: student.studentId,
            processed: true, // Mark as verified since we found the student
          )
        : scanRecord;

    // Save scan record
    if (kIsWeb) {
      // Web: Save directly to Firebase
      if (_firebaseService.isAvailable) {
        try {
          await _firebaseService.addScanRecord(updatedScanRecord);
        } catch (e) {
          debugPrint('Failed to save scan to Firebase: $e');
        }
      }
    } else {
      // Mobile/Desktop: Save to SQLite and sync to Firebase
      await _databaseService.insertScan(updatedScanRecord);

      // Try to sync to Firebase
      if (state.isConnected) {
        try {
          await _firebaseService.uploadScan(updatedScanRecord);
        } catch (e) {
          // Sync will happen later when connection is restored
        }
      }
    }

    if (student != null) {
      // Check for duplicates
      if (kIsWeb) {
        final existingScans = state.scans
            .where((s) => s.studentId == student!.studentId)
            .toList();
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
            errorMessage: null, // Clear any previous error messages
          );
        }
      } else {
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
      }
    } else {
      // Student not found - increment error count and show error dialog
      state = state.copyWith(
        errorMessage: 'Student ID ${scanResult.code} not found in database',
        errorCount: state.errorCount + 1,
      );
    }

    // Update scan list for web (Firebase will update via stream for web)
    if (kIsWeb) {
      final updatedScans = [updatedScanRecord, ...state.scans];
      state = state.copyWith(
        scans: updatedScans,
        scanCount: updatedScans.length,
        uniqueStudentCount: updatedScans.map((s) => s.studentId).toSet().length,
        lastScan: updatedScanRecord,
      );
    } else {
      // Reload scans from database
      await _loadScans();
    }
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

  Future<void> createNewEvent(
      int eventNumber, String name, String description) async {
    try {
      final event = Event.createNew(
        eventNumber: eventNumber,
        name: name,
        description: description,
      );

      if (kIsWeb) {
        // Web: Save to Firebase
        if (_firebaseService.isAvailable) {
          await _firebaseService.addEvent(event);
        }
      } else {
        // Mobile/Desktop: Save to SQLite and sync to Firebase
        await _databaseService.insertEvent(event);

        // Sync to Firebase if connected
        if (state.isConnected) {
          await _firebaseService.addEvent(event);
        }
      }

      // Reload events to include the new one
      await _loadEvents();

      state = state.copyWith(
        currentEvent: event,
        showNewEventDialog: false,
        errorMessage: null, // Clear any previous errors
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
      if (kIsWeb) {
        // Web: Use Firebase for student search
        if (_firebaseService.isAvailable) {
          final students = await _firebaseService.searchStudents(query);
          state = state.copyWith(
            studentSearchResults: students,
            isSearchingStudents: false,
          );
        } else {
          // Fallback to mock data if Firebase not available
          await Future.delayed(const Duration(milliseconds: 500));
          final mockStudents = _getMockStudents();
          final results = mockStudents
              .where((s) =>
                  s.firstName.toLowerCase().contains(query.toLowerCase()) ||
                  s.lastName.toLowerCase().contains(query.toLowerCase()) ||
                  s.studentId.toLowerCase().contains(query.toLowerCase()))
              .toList();

          state = state.copyWith(
            studentSearchResults: results,
            isSearchingStudents: false,
          );
        }
      } else {
        final students = await _databaseService.searchStudents(query);
        state = state.copyWith(
          studentSearchResults: students,
          isSearchingStudents: false,
        );
      }
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
      // Create scan record for manual check-in - mark as processed/verified since we found the student
      final scanRecord = ScanRecord.create(
        code: student.studentId,
        symbology: 'MANUAL',
        eventId: state.currentEvent!.id,
        studentId: student.studentId,
      ).copyWith(processed: true); // Mark as verified for admin portal

      if (kIsWeb) {
        // Web: Save directly to Firebase
        if (_firebaseService.isAvailable) {
          try {
            await _firebaseService.addScanRecord(scanRecord);
          } catch (e) {
            debugPrint('Failed to save manual check-in to Firebase: $e');
          }
        }

        // Update state immediately for web
        final updatedScans = [scanRecord, ...state.scans];
        state = state.copyWith(
          showForgotIdDialog: false,
          studentSearchResults: [],
          forgotIdCount: state.forgotIdCount + 1,
          scans: updatedScans,
          scanCount: updatedScans.length,
          uniqueStudentCount:
              updatedScans.map((s) => s.studentId).toSet().length,
          lastScan: scanRecord,
          errorMessage: null, // Clear any previous error messages
        );
      } else {
        // Mobile/Desktop: Save to SQLite and sync to Firebase
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
      }
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

      if (!kIsWeb) {
        await _databaseService.updateEvent(completedEvent);

        // Notify Firebase
        if (state.isConnected) {
          await _firebaseService.notifyEventCompleted(
            completedEvent,
            state.scanCount,
          );
        }
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

      if (!kIsWeb) {
        await _databaseService.updateEvent(reopenedEvent);
      }

      state = state.copyWith(currentEvent: reopenedEvent);
      await _loadEvents();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to reopen event: $e');
    }
  }

  Future<void> submitErrorRecord(String scannedId, String email) async {
    if (state.currentEvent == null) return;

    try {
      if (!kIsWeb) {
        await _firebaseService.saveErrorRecord(
          scannedId,
          email,
          state.currentEvent!.id,
          state.currentEvent!.name,
          state.currentEvent!.formattedDate,
        );
      }

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

final scannerProvider =
    StateNotifierProvider<ScannerNotifier, ScannerState>((ref) {
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
