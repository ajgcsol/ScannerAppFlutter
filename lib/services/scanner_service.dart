import 'package:flutter/foundation.dart';
import '../models/event.dart';
import '../models/scan.dart';
import '../models/scan_record.dart';
import '../models/student.dart';
import 'firebase_service.dart';

class ScannerService {
  final FirebaseService _firebaseService = FirebaseService.instance;

  Future<List<Event>> getEvents() async {
    return await _firebaseService.getEvents();
  }

  Future<List<Student>> getStudents() async {
    return await _firebaseService.getStudents();
  }

  Future<Student?> getStudentById(String studentId) async {
    return await _firebaseService.getStudentByStudentId(studentId);
  }

  // Cache for reducing API calls
  static final Map<String, List<Scan>> _scansCache = {};
  static final Map<String, List<Student>> _studentsCache = {};
  static DateTime? _lastCacheTime;
  
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
    
    // Fetch fresh data
    List<Student> students;
    if (_studentsCache.isEmpty || _lastCacheTime == null || 
        now.difference(_lastCacheTime!).inSeconds >= 30) {
      debugPrint('🔍 Fetching fresh student data');
      students = await _firebaseService.getStudents();
      _studentsCache['all'] = students;
    } else {
      debugPrint('🔍 Using cached student data');
      students = _studentsCache['all'] ?? [];
    }
    
    // Get scan records as single fetch instead of stream
    debugPrint('🔍 Fetching scan records for eventId: $eventId, eventNumber: $eventNumber');
    final scanRecords = await _firebaseService.getScanRecordsOnce(
      eventId: eventId, 
      eventNumber: eventNumber
    );
    final studentMap = {for (var s in students) s.studentId: s};

    final scans = scanRecords.map((record) {
      final student = studentMap[record.studentId];
      return Scan(
        studentId: record.studentId ?? record.code,
        timestamp: record.timestamp,
        studentName: student?.fullName ?? 'Unknown Student',
        studentEmail: student?.email ?? '',
      );
    }).toList();
    
    debugPrint('🔍 Found ${scans.length} scans for cacheKey: $cacheKey');
    
    // Cache the result
    _scansCache[cacheKey] = scans;
    _lastCacheTime = now;
    
    return scans;
  }

  Future<void> recordScan(String eventId, Scan scan, {int? eventNumber}) async {
    // Convert Scan to ScanRecord for storage
    // Use eventNumber as listId if available
    final listId = eventNumber?.toString() ?? eventId;
    
    await _firebaseService.addScanRecord(ScanRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      code: scan.studentId,
      timestamp: scan.timestamp,
      eventId: listId,  // Use listId for compatibility with existing Firestore structure
      studentId: scan.studentId,
      processed: false,
      synced: false,
      metadata: {'studentName': scan.studentName, 'studentEmail': scan.studentEmail},
    ));
    
    // Invalidate cache to show fresh data
    _scansCache.remove(listId);
    _scansCache.remove(eventId);
    _lastCacheTime = null;
  }

  Future<void> recordError(String eventId, String code) async {
    debugPrint('Recording error for eventId: $eventId, code: $code');
    // Convert to error record if needed
  }
}