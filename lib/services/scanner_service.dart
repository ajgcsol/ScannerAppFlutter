import 'package:flutter/foundation.dart';
import '../models/event.dart';
import '../models/scan.dart';
import '../models/scan_record.dart';
import '../models/student.dart';
import '../models/error_record.dart' as error_model;
import 'firebase_service.dart';
import 'database_service.dart';
import 'sync_service.dart';

class ScannerService {
  final FirebaseService _firebaseService = FirebaseService.instance;
  final DatabaseService _databaseService = DatabaseService();
  final SyncService _syncService = SyncService();
  
  // Expose sync service for initialization and status
  SyncService get syncService => _syncService;
  
  // Cache for reducing API calls
  static final Map<String, List<Scan>> _scansCache = {};
  static final Map<String, List<Student>> _studentsCache = {};
  static DateTime? _lastCacheTime;

  Future<List<Event>> getEvents() async {
    try {
      final localEvents = await _databaseService.getAllEvents();
      
      // Check if we should refresh from Firebase
      final shouldRefreshFromFirebase = _syncService.currentStatus.isOnline && (
        localEvents.isEmpty || // No local events
        _lastCacheTime == null || // Never cached
        DateTime.now().difference(_lastCacheTime!).inMinutes > 5 // Cache older than 5 minutes
      );
      
      if (shouldRefreshFromFirebase) {
        debugPrint('📱 ONLINE: Refreshing events from Firebase');
        try {
          // Check for deleted events first
          await checkForDeletedEvents();
          
          final firebaseEvents = await _firebaseService.getEvents();
          
          // Sync events with targeted deletion detection
          await _syncEventsWithDeletionDetection(firebaseEvents, localEvents);
          
          _lastCacheTime = DateTime.now();
          debugPrint('📱 SYNC: Synced ${firebaseEvents.length} events from Firebase');
          
          // Return fresh events from database after sync
          return await _databaseService.getAllEvents();
        } catch (e) {
          debugPrint('📱 ERROR: Failed to refresh from Firebase: $e');
          // Fall back to local events if Firebase fails
          if (localEvents.isNotEmpty) {
            debugPrint('📱 FALLBACK: Using ${localEvents.length} local events');
            return localEvents;
          }
          return [];
        }
      }
      
      // Use local events
      if (localEvents.isNotEmpty) {
        debugPrint('📱 CACHED: Using ${localEvents.length} events from local database');
        return localEvents;
      }
      
      debugPrint('📱 OFFLINE: No events available');
      return [];
    } catch (e) {
      debugPrint('📱 ERROR: Failed to get events: $e');
      // Fallback to local database
      return await _databaseService.getAllEvents();
    }
  }

  void clearEventCache() {
    _lastCacheTime = null;
    debugPrint('📱 Event cache cleared, will refresh from Firebase on next request');
  }

  Future<void> _syncEventsWithDeletionDetection(List<Event> firebaseEvents, List<Event> localEvents) async {
    final firebaseEventIds = firebaseEvents.map((e) => e.id).toSet();
    final localEventIds = localEvents.map((e) => e.id).toSet();
    
    // Find events that exist locally but not in Firebase (candidates for deletion)
    final potentialDeleted = localEventIds.difference(firebaseEventIds);
    
    for (final eventId in potentialDeleted) {
      final localEvent = localEvents.firstWhere((e) => e.id == eventId);
      
      // Only delete if event was originally from Firebase (has proper Firebase ID format)
      // Keep locally created events (they might be pending upload)
      if (_isFirebaseEvent(localEvent)) {
        debugPrint('📱 DELETION: Removing deleted Firebase event: ${localEvent.name} (${eventId})');
        await _databaseService.deleteEvent(eventId);
      } else {
        debugPrint('📱 KEEP: Preserving locally created event: ${localEvent.name} (${eventId})');
      }
    }
    
    // Update or insert Firebase events
    for (final firebaseEvent in firebaseEvents) {
      await _databaseService.insertOrUpdateEvent(firebaseEvent);
    }
  }

  bool _isFirebaseEvent(Event event) {
    // Firebase events typically have 20+ character IDs and don't start with local prefixes
    return event.id.length > 15 && 
           !event.id.startsWith('local_') && 
           !event.id.startsWith('offline_') &&
           !event.id.startsWith('temp_');
  }

  Future<void> deleteEventById(String eventId) async {
    debugPrint('📱 API DELETION: Removing event by ID: $eventId');
    await _databaseService.deleteEvent(eventId);
    clearEventCache(); // Force refresh on next load
  }

  Future<void> checkForDeletedEvents() async {
    if (!_syncService.currentStatus.isOnline) {
      debugPrint('📱 OFFLINE: Skipping deleted events check');
      return;
    }

    try {
      debugPrint('📱 Checking for deleted events from admin portal...');
      
      final deletedEvents = await _firebaseService.getDeletedEvents();
      
      if (deletedEvents.isEmpty) {
        debugPrint('📱 No deleted events found');
        return;
      }

      debugPrint('📱 Found ${deletedEvents.length} deleted events to process');
      
      for (final deletedEvent in deletedEvents) {
        final eventId = deletedEvent['originalEventId'] as String?;
        final eventName = deletedEvent['eventName'] as String?;
        
        if (eventId != null) {
          debugPrint('📱 Processing deletion for event: $eventName ($eventId)');
          await _databaseService.deleteEvent(eventId);
        }
      }
      
      clearEventCache(); // Force refresh on next load
      debugPrint('📱 Deleted events processing complete');
      
    } catch (e) {
      debugPrint('📱 ERROR: Failed to check for deleted events: $e');
    }
  }

  Future<List<Student>> getStudents() async {
    try {
      // Try to get from local database first
      final localStudents = await _databaseService.getAllStudents();
      if (localStudents.isNotEmpty) {
        debugPrint('📱 OFFLINE: Using ${localStudents.length} students from local database');
        return localStudents;
      }
      
      // If no local students, try to fetch from Firebase
      if (_syncService.currentStatus.isOnline) {
        debugPrint('📱 ONLINE: Fetching students from Firebase');
        final firebaseStudents = await _firebaseService.getStudents();
        
        // Save to local database for offline use
        for (final student in firebaseStudents) {
          await _databaseService.insertStudent(student);
        }
        
        return firebaseStudents;
      } else {
        debugPrint('📱 OFFLINE: No local students and device is offline');
        return [];
      }
    } catch (e) {
      debugPrint('📱 ERROR: Failed to get students: $e');
      // Fallback to local database
      return await _databaseService.getAllStudents();
    }
  }

  Future<Student?> getStudentById(String studentId) async {
    try {
      // Try local database first (faster)
      final localStudent = await _databaseService.getStudentById(studentId);
      if (localStudent != null) {
        debugPrint('📱 OFFLINE: Found student $studentId in local database');
        return localStudent;
      }
      
      // If not found locally and online, try Firebase
      if (_syncService.currentStatus.isOnline) {
        debugPrint('📱 ONLINE: Searching for student $studentId in Firebase');
        final firebaseStudent = await _firebaseService.getStudentByStudentId(studentId);
        
        // Save to local database if found
        if (firebaseStudent != null) {
          await _databaseService.insertStudent(firebaseStudent);
        }
        
        return firebaseStudent;
      } else {
        debugPrint('📱 OFFLINE: Student $studentId not found locally and device is offline');
        return null;
      }
    } catch (e) {
      debugPrint('📱 ERROR: Failed to get student by ID: $e');
      // Fallback to local database
      return await _databaseService.getStudentById(studentId);
    }
  }
  
  Future<List<Scan>> getScansForEvent(String eventId, {int? eventNumber}) async {
    debugPrint('🔍 getScansForEvent called with eventId: $eventId, eventNumber: $eventNumber');
    
    // Use eventId consistently as cache key to prevent cross-event cache conflicts
    final cacheKey = eventId;
    
    // Check cache first (valid for 30 seconds)
    final now = DateTime.now();
    if (_lastCacheTime != null && 
        now.difference(_lastCacheTime!).inSeconds < 30 && 
        _scansCache.containsKey(cacheKey)) {
      debugPrint('🔍 Returning cached scans for cacheKey: $cacheKey');
      return _scansCache[cacheKey]!;
    }
    
    try {
      // Get scan records from local database first
      final localScans = await _databaseService.getScansForEvent(eventId);
      
      // Get students for mapping names
      final students = await getStudents();
      final studentMap = {for (var s in students) s.studentId: s};
      
      // Convert local scans to Scan models
      List<Scan> scans = localScans.map((record) {
        final student = studentMap[record.studentId ?? record.code];
        return Scan(
          studentId: record.studentId ?? record.code,
          timestamp: record.timestamp,
          studentName: student?.fullName ?? 'Unknown Student',
          studentEmail: student?.email ?? '',
        );
      }).toList();
      
      // If online, use Firebase as primary source of truth
      if (_syncService.currentStatus.isOnline) {
        try {
          debugPrint('🔍 Fetching latest scan records from Firebase (primary source)');
          final firebaseScans = await _firebaseService.getScanRecordsOnce(
            eventId: eventId, 
            eventNumber: eventNumber
          );
          
          // Use Firebase as primary source, only add recent unsynced local scans
          scans = firebaseScans.map((record) {
            final student = studentMap[record.studentId ?? record.code];
            return Scan(
              studentId: record.studentId ?? record.code,
              timestamp: record.timestamp,
              studentName: student?.fullName ?? 'Unknown Student',
              studentEmail: student?.email ?? '',
            );
          }).toList();
          
          // Only add local scans that are very recent and unsynced (last 5 minutes)
          final recentCutoff = DateTime.now().subtract(const Duration(minutes: 5));
          final recentLocalScans = localScans
              .where((record) => 
                  record.synced == false && 
                  record.timestamp.isAfter(recentCutoff) &&
                  !firebaseScans.any((fs) => fs.studentId == record.studentId || fs.code == record.studentId))
              .map((record) {
                final student = studentMap[record.studentId ?? record.code];
                return Scan(
                  studentId: record.studentId ?? record.code,
                  timestamp: record.timestamp,
                  studentName: student?.fullName ?? 'Unknown Student',
                  studentEmail: student?.email ?? '',
                );
              });
          
          scans.addAll(recentLocalScans);
          
          debugPrint('🔍 Using Firebase as primary source: ${firebaseScans.length} Firebase + ${recentLocalScans.length} recent local scans');
        } catch (e) {
          debugPrint('🔍 Failed to fetch from Firebase, using local data: $e');
        }
      }
      
      // Ensure scans are sorted by timestamp descending (most recent first)
      scans.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      debugPrint('🔍 Found ${scans.length} scans for cacheKey: $cacheKey');
      
      // Cache the result
      _scansCache[cacheKey] = scans;
      _lastCacheTime = now;
      
      return scans;
    } catch (e) {
      debugPrint('🔍 ERROR: Failed to get scans: $e');
      return [];
    }
  }

  Future<void> recordScan(String eventId, Scan scan, {int? eventNumber}) async {
    debugPrint('🔍 RECORD_SCAN: recordScan called with eventId=$eventId, eventNumber=$eventNumber');
    
    // Create ScanRecord
    final scanRecord = ScanRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      code: scan.studentId,
      timestamp: scan.timestamp,
      eventId: eventId,
      studentId: scan.studentId,
      processed: false,
      synced: false,
      metadata: {'studentName': scan.studentName, 'studentEmail': scan.studentEmail},
    );
    
    // ALWAYS save to local database first (offline-first)
    debugPrint('📱 OFFLINE-FIRST: Saving scan to local database');
    await _databaseService.insertScan(scanRecord);
    
    // Don't sync immediately - let the sync service handle all syncing
    // This prevents double-syncing issues where the same scan gets sent twice
    debugPrint('📱 SCAN_SAVED: Scan saved locally, will be synced by sync service');
    
    // Invalidate cache to show fresh data - only use eventId as key for consistency
    _scansCache.remove(eventId);
    _lastCacheTime = null;
    
    // Trigger sync attempt (will check connectivity internally)
    _syncService.syncAll();
    
    debugPrint('🔍 RECORD_SCAN: recordScan completed successfully');
  }

  Future<void> recordError(String eventId, String code) async {
    debugPrint('Recording error for eventId: $eventId, code: $code');
    
    try {
      // Create error record
      final errorRecord = error_model.ErrorRecord.create(
        scannedId: code,
        studentEmail: 'unknown@unknown.com',
        eventId: eventId,
        eventName: 'Current Event',
        eventDate: DateTime.now().toIso8601String(),
      );
      
      // Save to local database first
      debugPrint('📱 OFFLINE-FIRST: Saving error to local database');
      await _databaseService.insertErrorRecord(errorRecord);
      
      // Try to sync to Firebase if online
      if (_syncService.currentStatus.isOnline) {
        try {
          await _firebaseService.addErrorRecord(errorRecord);
          debugPrint('📱 ONLINE: Error record synced to Firebase');
        } catch (e) {
          debugPrint('📱 SYNC_ERROR: Failed to sync error record: $e');
        }
      } else {
        debugPrint('📱 OFFLINE: Error saved locally for later sync');
      }
      
      debugPrint('🔍 ERROR_RECORD: Error record saved: ${errorRecord.id}');
    } catch (e) {
      debugPrint('🔍 ERROR_RECORD: Failed to save error record: $e');
    }
  }
  
  // Get sync status for UI
  Stream<SyncStatus> get syncStatusStream => _syncService.syncStatusStream;
  SyncStatus get syncStatus => _syncService.currentStatus;
  
  // Force sync now (for manual sync button)
  Future<void> forceSyncNow() => _syncService.forceSyncNow();
  
  // Clear cache for specific event (used when switching events)
  void clearCacheForEvent(String eventId) {
    _scansCache.remove(eventId);
    _lastCacheTime = null;
    debugPrint('🔍 Cache cleared for event: $eventId');
  }
  
  // Force clear all caches (used for manual sync)
  void clearAllCaches() {
    _scansCache.clear();
    _studentsCache.clear();
    _lastCacheTime = null;
    debugPrint('🔍 All caches cleared for manual sync');
  }
  
  // Create a new event
  Future<Event> createEvent(Event event) async {
    try {
      debugPrint('📱 Creating event: ${event.name} (#${event.eventNumber})');
      
      if (_syncService.currentStatus.isOnline) {
        // Create event on Firebase
        debugPrint('📱 ONLINE: Creating event on Firebase');
        final createdEvent = await _firebaseService.createEvent(event);
        
        // Save to local database for offline access
        await _databaseService.insertEvent(createdEvent);
        
        debugPrint('📱 SUCCESS: Event created and saved locally: ${createdEvent.id}');
        return createdEvent;
      } else {
        // Save locally only when offline
        debugPrint('📱 OFFLINE: Saving event locally only');
        await _databaseService.insertEvent(event);
        
        // Mark for sync when online
        // TODO: Implement event sync queue for offline creation
        
        debugPrint('📱 OFFLINE: Event saved locally for later sync: ${event.id}');
        return event;
      }
    } catch (e) {
      debugPrint('📱 ERROR: Failed to create event: $e');
      
      // Try to save locally as fallback
      try {
        await _databaseService.insertEvent(event);
        debugPrint('📱 FALLBACK: Event saved locally after Firebase error');
        return event;
      } catch (localError) {
        debugPrint('📱 CRITICAL: Failed to save event locally: $localError');
        rethrow;
      }
    }
  }

  Future<Event> updateEvent(Event event) async {
    debugPrint('📱 UPDATE_EVENT: Updating event ${event.name} (${event.id})');

    try {
      // Update event locally first
      await _databaseService.updateEvent(event);
      debugPrint('📱 UPDATE_EVENT: Event updated locally');

      // Try to update remotely if online
      if (_syncService.currentStatus.isOnline) {
        await _firebaseService.updateEvent(event);
        debugPrint('📱 UPDATE_EVENT: Event updated in Firebase');
      } else {
        // TODO: Implement event sync queue for offline updates
        debugPrint('📱 OFFLINE: Event updated locally for later sync: ${event.id}');
      }

      return event;
    } catch (e) {
      debugPrint('📱 ERROR: Failed to update event: $e');
      rethrow;
    }
  }
}