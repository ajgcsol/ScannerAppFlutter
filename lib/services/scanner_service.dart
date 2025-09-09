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
      // Try to get from local database first
      final localEvents = await _databaseService.getAllEvents();
      if (localEvents.isNotEmpty) {
        debugPrint('📱 OFFLINE: Using ${localEvents.length} events from local database');
        return localEvents;
      }
      
      // If no local events, try to fetch from Firebase
      if (_syncService.currentStatus.isOnline) {
        debugPrint('📱 ONLINE: Fetching events from Firebase');
        final firebaseEvents = await _firebaseService.getEvents();
        
        // Save to local database for offline use
        for (final event in firebaseEvents) {
          await _databaseService.insertEvent(event);
        }
        
        return firebaseEvents;
      } else {
        debugPrint('📱 OFFLINE: No local events and device is offline');
        return [];
      }
    } catch (e) {
      debugPrint('📱 ERROR: Failed to get events: $e');
      // Fallback to local database
      return await _databaseService.getAllEvents();
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
    
    // Check cache first (valid for 30 seconds)
    final now = DateTime.now();
    final cacheKey = eventNumber?.toString() ?? eventId;
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
      
      // If online, also try to get latest from Firebase
      if (_syncService.currentStatus.isOnline) {
        try {
          debugPrint('🔍 Fetching latest scan records from Firebase');
          final firebaseScans = await _firebaseService.getScanRecordsOnce(
            eventId: eventId, 
            eventNumber: eventNumber
          );
          
          // Merge with local scans (Firebase takes precedence for duplicates)
          final firebaseScanIds = firebaseScans.map((s) => s.id).toSet();
          final localOnlyScans = scans.where((s) => !firebaseScanIds.contains(s.studentId)).toList();
          
          scans = firebaseScans.map((record) {
            final student = studentMap[record.studentId ?? record.code];
            return Scan(
              studentId: record.studentId ?? record.code,
              timestamp: record.timestamp,
              studentName: student?.fullName ?? 'Unknown Student',
              studentEmail: student?.email ?? '',
            );
          }).toList();
          
          // Add local-only scans
          scans.addAll(localOnlyScans);
        } catch (e) {
          debugPrint('🔍 Failed to fetch from Firebase, using local data: $e');
        }
      }
      
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
    
    // Invalidate cache to show fresh data
    _scansCache.remove(eventId);
    if (eventNumber != null) {
      _scansCache.remove(eventNumber.toString());
    }
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
}