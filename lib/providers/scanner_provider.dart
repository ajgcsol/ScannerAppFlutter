import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/event.dart';
import '../models/student.dart';
import '../models/scan.dart';
import '../services/scanner_service.dart';
import '../services/sync_service.dart';

// Scan result from camera or manual input
class ScanResult {
  final String code;
  final DateTime timestamp;

  ScanResult({
    required this.code,
    required this.timestamp,
  });
}

// Scanner State
@immutable
class ScannerState {
  static const _errorMessageSentinel = Object();
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
  final bool isLoading;
  final bool isOnline;
  final bool isSyncing;
  final int pendingScansCount;

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
    this.isLoading = false,
    this.isOnline = true,
    this.isSyncing = false,
    this.pendingScansCount = 0,
  });

  // Computed properties for tab functionality
  int get scanCount => scans.length;
  int get uniqueStudentCount => scans.map((s) => s.studentId).toSet().length;
  int get duplicateScanCount => scanCount - uniqueStudentCount;
  int get manualCheckInCount => 0; // TODO: Track manual check-ins separately
  int get errorCount => 0; // TODO: Track errors separately

  ScannerState copyWith({
    Event? currentEvent,
    List<Event>? availableEvents,
    List<Scan>? scans,
    Student? verifiedStudent,
    Object? errorMessage = _errorMessageSentinel, // Use static sentinel to allow null
    bool? isScanning,
    bool? showStudentDialog,
    bool? showDuplicateDialog,
    bool? showForgotIdDialog,
    bool? showEventSelector,
    bool? showCameraPreview,
    bool? isLoading,
    bool? isOnline,
    bool? isSyncing,
    int? pendingScansCount,
  }) {
    return ScannerState(
      currentEvent: currentEvent ?? this.currentEvent,
      availableEvents: availableEvents ?? this.availableEvents,
      scans: scans ?? this.scans,
      verifiedStudent: verifiedStudent ?? this.verifiedStudent,
      errorMessage: identical(errorMessage, _errorMessageSentinel) ? this.errorMessage : errorMessage as String?,
      isScanning: isScanning ?? this.isScanning,
      showStudentDialog: showStudentDialog ?? this.showStudentDialog,
      showDuplicateDialog: showDuplicateDialog ?? this.showDuplicateDialog,
      showForgotIdDialog: showForgotIdDialog ?? this.showForgotIdDialog,
      showEventSelector: showEventSelector ?? this.showEventSelector,
      showCameraPreview: showCameraPreview ?? this.showCameraPreview,
      isLoading: isLoading ?? this.isLoading,
      isOnline: isOnline ?? this.isOnline,
      isSyncing: isSyncing ?? this.isSyncing,
      pendingScansCount: pendingScansCount ?? this.pendingScansCount,
    );
  }
}

// Scanner Notifier
class ScannerNotifier extends StateNotifier<ScannerState> {
  final ScannerService _scannerService;
  Timer? _refreshTimer;
  Timer? _debounceTimer;
  StreamSubscription<SyncStatus>? _syncStatusSubscription;

  ScannerNotifier(this._scannerService) : super(const ScannerState(isLoading: true)) {
    _initialize();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _debounceTimer?.cancel();
    _syncStatusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    // Initialize sync service
    await _scannerService.syncService.initialize();
    
    // Listen to sync status changes
    _syncStatusSubscription = _scannerService.syncStatusStream.listen((syncStatus) {
      state = state.copyWith(
        isOnline: syncStatus.isOnline,
        isSyncing: syncStatus.isSyncing,
        pendingScansCount: syncStatus.pendingScans,
      );
    });
    
    await _loadEvents();
    if (state.currentEvent != null) {
      await _loadScansForCurrentEvent();
      _startPeriodicRefresh();
    }
    state = state.copyWith(isLoading: false);
  }

  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    // Refresh scan data every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadScansForCurrentEvent();
    });
  }

  Future<void> _loadEvents() async {
    debugPrint('📱 _loadEvents() called');
    final events = await _scannerService.getEvents();
    debugPrint('📱 Loaded ${events.length} events');
    if (events.isNotEmpty) {
      // Prefer active events, but prioritize real Firebase events over sample events
      final activeEvents = events.where((e) => e.isActive == true).toList();
      
      Event selectedEvent;
      if (activeEvents.isNotEmpty) {
        // Filter out sample/test events and prefer real Firebase events
        final realActiveEvents = activeEvents.where((e) {
          final name = e.name.toLowerCase();
          final id = e.id.toLowerCase();
          return !name.contains('sample') && 
                 !name.contains('test') &&
                 !name.contains('demo') &&
                 !id.startsWith('event_') &&
                 !id.contains('sample') &&
                 !id.contains('test');
        }).toList();
        
        selectedEvent = realActiveEvents.isNotEmpty ? realActiveEvents.first : activeEvents.first;
      } else {
        selectedEvent = events.first;
      }
      
      debugPrint('📱 Setting current event to: ${selectedEvent.name} (id: ${selectedEvent.id}, active: ${selectedEvent.isActive})');
      
      // Filter available events to show only real events by default (hide sample/test events)
      final filteredEvents = events.where((e) {
        final name = e.name.toLowerCase();
        final id = e.id.toLowerCase();
        return !name.contains('sample') && 
               !name.contains('test') &&
               !name.contains('demo') &&
               !id.startsWith('event_') &&
               !id.contains('sample') &&
               !id.contains('test');
      }).toList();
      
      // Use filtered events for the available events list, but keep original events if no real events found
      final eventsToShow = filteredEvents.isNotEmpty ? filteredEvents : events;
      state = state.copyWith(availableEvents: eventsToShow, currentEvent: selectedEvent);
    } else {
      debugPrint('📱 No events found, setting empty list');
      state = state.copyWith(availableEvents: []);
    }
  }

  Future<void> _loadScansForCurrentEvent() async {
    debugPrint('📊 _loadScansForCurrentEvent: Starting with error message: ${state.errorMessage}');
    if (state.currentEvent == null) return;
    final databaseScans = await _scannerService.getScansForEvent(
      state.currentEvent!.id,
      eventNumber: state.currentEvent!.eventNumber,
    );
    
    debugPrint('📊 _loadScansForCurrentEvent: Got ${databaseScans.length} scans from database, current UI has ${state.scans.length} scans');
    
    // Merge database scans with existing UI scans, removing duplicates
    final mergedScans = _mergeScansWithDeduplication(databaseScans, state.scans);
    
    debugPrint('📊 _loadScansForCurrentEvent: Before state update, error message: ${state.errorMessage}');
    debugPrint('📊 _loadScansForCurrentEvent: Before state update, showStudentDialog: ${state.showStudentDialog}');
    debugPrint('📊 _loadScansForCurrentEvent: Merged to ${mergedScans.length} deduplicated scans');
    
    // Preserve dialog states when updating scans
    state = state.copyWith(
      scans: mergedScans,
      // Explicitly preserve dialog states
      showStudentDialog: state.showStudentDialog,
      showDuplicateDialog: state.showDuplicateDialog,
      verifiedStudent: state.verifiedStudent,
      errorMessage: state.errorMessage,
    );
    debugPrint('📊 _loadScansForCurrentEvent: After state update, error message: ${state.errorMessage}');
    debugPrint('📊 _loadScansForCurrentEvent: After state update, showStudentDialog: ${state.showStudentDialog}');
  }
  
  List<Scan> _mergeScansWithDeduplication(List<Scan> databaseScans, List<Scan> existingScans) {
    // Use a Map to deduplicate by studentId + timestamp combination
    final Map<String, Scan> scanMap = {};
    
    // Add database scans first (they are the source of truth)
    for (final scan in databaseScans) {
      final key = '${scan.studentId}_${scan.timestamp.millisecondsSinceEpoch}';
      scanMap[key] = scan;
    }
    
    // Add existing UI scans that aren't already in database (optimistic updates not yet persisted)
    for (final scan in existingScans) {
      final key = '${scan.studentId}_${scan.timestamp.millisecondsSinceEpoch}';
      if (!scanMap.containsKey(key)) {
        scanMap[key] = scan;
      }
    }
    
    // Convert back to list and sort by timestamp descending
    final mergedScans = scanMap.values.toList();
    mergedScans.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    return mergedScans;
  }

  Future<void> triggerScan() async {
    // Debounce rapid button taps
    if (_debounceTimer?.isActive ?? false) {
      debugPrint('📱 DIALOG: triggerScan() - ignoring due to debounce');
      return;
    }
    
    // Prevent scan if camera is already showing
    if (state.showCameraPreview) {
      debugPrint('📱 DIALOG: triggerScan() - camera already showing, ignoring');
      return;
    }
    
    debugPrint('📱 DIALOG: triggerScan() - setting showCameraPreview to true');
    state = state.copyWith(showCameraPreview: true);
    
    // Set debounce timer for 500ms
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {});
  }

  Future<void> processCameraScan(String code) async {
    debugPrint('📱 DIALOG: processCameraScan($code) - setting showCameraPreview to false, isScanning to true');
    state = state.copyWith(showCameraPreview: false, isScanning: true);
    final scanResult = ScanResult(code: code, timestamp: DateTime.now());
    await _processScanResult(scanResult);
    debugPrint('📱 DIALOG: processCameraScan($code) - setting isScanning to false');
    debugPrint('📱 DIALOG: Current error message before isScanning update: ${state.errorMessage}');
    // Preserve existing error message when updating isScanning
    state = state.copyWith(
      isScanning: false,
      errorMessage: state.errorMessage, // Explicitly preserve error message
    );
    debugPrint('📱 DIALOG: Error message after isScanning update: ${state.errorMessage}');
    
    // Give UI listener time to react to error state before any refresh calls
    if (state.errorMessage != null) {
      debugPrint('📱 DIALOG: Error detected, waiting 100ms for UI listener to react');
      await Future.delayed(const Duration(milliseconds: 100));
      debugPrint('📱 DIALOG: Delay completed, error message still: ${state.errorMessage}');
    }
  }

  Future<void> _processScanResult(ScanResult scanResult) async {
    debugPrint('📱 SCAN_PROCESS: _processScanResult started with code: ${scanResult.code}');
    
    try {
      debugPrint('📱 SCAN_PROCESS: Calling getStudentById...');
      final student = await _scannerService.getStudentById(scanResult.code);
      debugPrint('📱 SCAN_PROCESS: getStudentById returned: ${student != null ? student.studentId : 'null'}');
      
      if (student != null) {
        debugPrint('📱 SCAN_PROCESS: Student found, checking for duplicates...');
        final isDuplicate = state.scans.any((s) => s.studentId == student.studentId);
        if (isDuplicate) {
          debugPrint('📱 SCAN_PROCESS: Duplicate found, showing duplicate dialog');
          state = state.copyWith(showDuplicateDialog: true, verifiedStudent: student);
          return;
        }

        debugPrint('📱 SCAN_PROCESS: No duplicate, recording scan...');
        final newScan = Scan(
          studentId: student.studentId,
          timestamp: scanResult.timestamp,
          studentName: student.fullName,
          studentEmail: student.email,
        );
        
        await _scannerService.recordScan(
          state.currentEvent!.id, 
          newScan,
          eventNumber: state.currentEvent!.eventNumber,
        );
        
        // Optimistically add scan to current list for instant UI update (lightning fast!)
        final updatedScans = [newScan, ...state.scans]; // Add to front (most recent first)
        
        // Set state to show student dialog after successful scan
        debugPrint('📱 SCAN_PROCESS: Setting showStudentDialog to true with optimistic UI update');
        state = state.copyWith(
          verifiedStudent: student,
          showStudentDialog: true,
          scans: updatedScans, // Update UI instantly
        );
        debugPrint('📱 SCAN_PROCESS: Success path completed');
      } else {
        debugPrint('📱 SCAN_PROCESS: Student NOT found - recording as error scan');
        debugPrint('📱 SCAN_PROCESS: Current state before error update - errorMessage: ${state.errorMessage}');
        
        // Record both error record and scan record for error cases
        await _scannerService.recordError(state.currentEvent!.id, scanResult.code);
        debugPrint('📱 SCAN_PROCESS: recordError completed');
        
        // Also create a scan record for the error so it shows up in the scan list
        final errorScan = Scan(
          studentId: scanResult.code,
          timestamp: scanResult.timestamp,
          studentName: 'Unknown Student (${scanResult.code})',
          studentEmail: 'Error - Student Not Found',
        );
        
        await _scannerService.recordScan(
          state.currentEvent!.id, 
          errorScan,
          eventNumber: state.currentEvent!.eventNumber,
        );
        debugPrint('📱 SCAN_PROCESS: Error scan recorded as scan record');
        
        // Optimistically add error scan to current list for instant UI update (lightning fast!)
        final updatedScans = [errorScan, ...state.scans]; // Add to front (most recent first)
        
        debugPrint('📱 SCAN_PROCESS: About to call state.copyWith with error message and optimistic UI update');
        final oldState = state;
        state = state.copyWith(
          errorMessage: 'Student not found. Scan recorded with report option.',
          showStudentDialog: false,
          verifiedStudent: null,
          scans: updatedScans, // Update UI instantly
        );
        
        debugPrint('📱 SCAN_PROCESS: state.copyWith completed');
        debugPrint('📱 SCAN_PROCESS: Old state errorMessage: ${oldState.errorMessage}');
        debugPrint('📱 SCAN_PROCESS: New state errorMessage: ${state.errorMessage}');
        debugPrint('📱 SCAN_PROCESS: State update completed for error case');
      }
    } catch (e, stackTrace) {
      debugPrint('📱 SCAN_PROCESS: EXCEPTION caught: $e');
      debugPrint('📱 SCAN_PROCESS: Stack trace: $stackTrace');
      
      debugPrint('📱 SCAN_PROCESS: Setting exception error message');
      state = state.copyWith(
        errorMessage: 'Error processing scan. Please try again.',
        showStudentDialog: false,
        verifiedStudent: null,
      );
      debugPrint('📱 SCAN_PROCESS: Exception error message set to: ${state.errorMessage}');
    }
    
    debugPrint('📱 SCAN_PROCESS: _processScanResult completed');
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

  void showStudentSuccessDialog(Student student) {
    state = state.copyWith(showStudentDialog: true, verifiedStudent: student);
  }

  void hideDuplicateDialog() {
    state = state.copyWith(showDuplicateDialog: false, verifiedStudent: null);
  }

  void clearErrorMessage() {
    debugPrint('📱 CLEAR_ERROR: Clearing error message and resetting dialog states');
    final oldState = state;
    state = state.copyWith(
      errorMessage: null,
      showStudentDialog: false,
      showDuplicateDialog: false,
      showCameraPreview: false,
      showForgotIdDialog: false,
      showEventSelector: false, // Explicitly ensure event selector is false
      verifiedStudent: null,
      isScanning: false, // Explicitly ensure scanning state is false
      isLoading: false,  // Explicitly ensure loading state is false
    );
    debugPrint('📱 CLEAR_ERROR: Error message cleared and states reset');
    debugPrint('📱 CLEAR_ERROR: State change - old errorMessage: ${oldState.errorMessage} -> new: ${state.errorMessage}');
    debugPrint('📱 CLEAR_ERROR: Final state - isScanning: ${state.isScanning}, isLoading: ${state.isLoading}');
  }

  Future<void> addManualScan(Student student) async {
    debugPrint('🔍 MANUAL_SCAN: addManualScan called for ${student.studentId}');
    if (state.currentEvent == null) {
      debugPrint('🔍 MANUAL_SCAN: ERROR - currentEvent is null');
      return;
    }

    debugPrint('🔍 MANUAL_SCAN: Creating scan for event ${state.currentEvent!.id}');
    final newScan = Scan(
      studentId: student.studentId,
      timestamp: DateTime.now(),
      studentName: student.fullName,
      studentEmail: student.email,
    );

    debugPrint('🔍 MANUAL_SCAN: Calling recordScan...');
    await _scannerService.recordScan(
      state.currentEvent!.id, 
      newScan,
      eventNumber: state.currentEvent!.eventNumber,
    );
    debugPrint('🔍 MANUAL_SCAN: recordScan completed, updating UI optimistically...');
    
    // Optimistically add scan to current list for instant UI update (lightning fast!)
    final updatedScans = [newScan, ...state.scans]; // Add to front (most recent first)
    state = state.copyWith(scans: updatedScans);
    
    debugPrint('🔍 MANUAL_SCAN: addManualScan completed successfully with ${updatedScans.length} scans');
  }

  Future<void> selectEvent(Event event) async {
    debugPrint('📱 selectEvent: Switching to event ${event.name} (${event.id})');
    
    // Clear cache for the new event to ensure fresh data
    _scannerService.clearCacheForEvent(event.id);
    
    state = state.copyWith(isLoading: true, currentEvent: event, showEventSelector: false, scans: []);
    await _loadScansForCurrentEvent();
    _startPeriodicRefresh(); // Restart refresh timer for new event
    state = state.copyWith(isLoading: false);
    
    debugPrint('📱 selectEvent: Event switched successfully, loaded ${state.scans.length} scans');
  }

  Future<void> createEvent(Event event) async {
    try {
      debugPrint('📱 CREATE_EVENT: Creating event ${event.name} (#${event.eventNumber})');
      
      state = state.copyWith(isLoading: true);
      
      // Create the event using the scanner service
      final createdEvent = await _scannerService.createEvent(event);
      
      // Refresh the available events list to include the new event
      final updatedEvents = await _scannerService.getEvents();
      
      // Update state with the new event and select it
      state = state.copyWith(
        availableEvents: updatedEvents,
        currentEvent: createdEvent,
        isLoading: false,
        scans: [], // Clear scans for the new event
        showEventSelector: false,
      );
      
      // Load scans for the new event (if any)
      await _loadScansForCurrentEvent();
      _startPeriodicRefresh(); // Start refresh timer for the new event
      
      debugPrint('📱 CREATE_EVENT: Event created and selected successfully');
    } catch (e) {
      debugPrint('📱 CREATE_EVENT: Failed to create event: $e');
      
      // Show error to user but don't change loading state to false yet
      // The dialog will handle that
      state = state.copyWith(
        errorMessage: 'Failed to create event: ${e.toString().replaceAll('Exception: ', '')}',
        isLoading: false,
      );
      
      rethrow; // Let the UI handle the error dialog
    }
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