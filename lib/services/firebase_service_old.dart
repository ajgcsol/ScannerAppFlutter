import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../firebase_options.dart';
import '../models/scan_record.dart';
import '../models/event.dart';
import '../models/student.dart';
import '../models/error_record.dart' as error_model;

class FirebaseService {
  static FirebaseService? _instance;
  static FirebaseService get instance => _instance ??= FirebaseService._();

  FirebaseService._();

  FirebaseFirestore? _firestore;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  bool get isAvailable => _firestore != null;
  bool get isConnected => isAvailable && _isInitialized;

  Future<void> initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _firestore = FirebaseFirestore.instance;

      // Enable offline persistence
      if (!kIsWeb) {
        _firestore = FirebaseFirestore.instanceFor(
          app: Firebase.app(),
        );
        _firestore!.settings = const Settings(persistenceEnabled: true);
      }

      _isInitialized = true;
      debugPrint('Firebase initialized successfully');
    } catch (e) {
      debugPrint('Firebase initialization failed: $e');
      _isInitialized = false;
      // Continue without Firebase - app will work in offline mode
    }
  }

  // Scan Records - Using nested structure to match Android app
  Future<void> addScanRecord(ScanRecord scanRecord) async {
    if (!isAvailable) {
      debugPrint('Firebase not available, scan record not synced');
      return;
    }

    try {
      // Use Android app's nested structure: lists/{listId}/scans/{scanId}
      await _firestore!
          .collection('lists')
          .doc(scanRecord.eventId ?? 'default')
          .collection('scans')
          .doc(scanRecord.id)
          .set(scanRecord.toJson());

      // ALSO write to flat structure for admin portal compatibility
      final scanData = {
        'code': scanRecord.code,
        'timestamp': scanRecord.timestamp.millisecondsSinceEpoch,
        'listId': scanRecord.eventId,
        'eventId': scanRecord.eventId,
        'deviceId': scanRecord.deviceId,
        'verified': scanRecord.processed,
        'symbology': scanRecord.symbology,
        'studentId': scanRecord.studentId,
        'synced': scanRecord.synced,
        'metadata': scanRecord.metadata,
      };

      await _firestore!.collection('scans').doc(scanRecord.id).set(scanData);

      debugPrint(
          'Scan record synced to Firebase (both structures): ${scanRecord.id}');
    } catch (e) {
      debugPrint('Failed to sync scan record: $e');
    }
  }

  Stream<List<ScanRecord>> getScanRecords({String? eventId}) {
    if (!isAvailable) {
      return Stream.value([]);
    }

    debugPrint('🔍 getScanRecords called with eventId: $eventId');

    if (eventId == null) {
      return _firestore!.collection('scans').snapshots().map((snapshot) {
        return snapshot.docs
            .map((doc) => _convertScanDocToScanRecord(doc))
            .toList();
      });
    }

    // Use the same approach as the admin portal - simple query with listId
    return _firestore!
        .collection('scans')
        .where('listId', isEqualTo: eventId)
        .snapshots()
        .map((snapshot) {
      debugPrint('🔍 Found ${snapshot.docs.length} scans for listId: $eventId');

      final scans =
          snapshot.docs.map((doc) => _convertScanDocToScanRecord(doc)).toList();

      // Sort by timestamp (newest first)
      scans.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      debugPrint('🔍 Converted ${scans.length} scans successfully');
      return scans;
    }).handleError((error) {
      debugPrint('🔍 Error in getScanRecords stream: $error');
      return <ScanRecord>[];
    });
  }

  // One-time fetch version to prevent rate limiting
  Future<List<ScanRecord>> getScanRecordsOnce({String? eventId}) async {
    if (!isAvailable) {
      return [];
    }

    try {
      debugPrint('🔍 getScanRecordsOnce called with eventId: $eventId');

      QuerySnapshot snapshot;
      if (eventId == null) {
        snapshot = await _firestore!.collection('scans').get();
      } else {
        snapshot = await _firestore!
            .collection('scans')
            .where('listId', isEqualTo: eventId)
            .get();
      }

      debugPrint('🔍 Found ${snapshot.docs.length} scans for listId: $eventId');

      final scans =
          snapshot.docs.map((doc) => _convertScanDocToScanRecord(doc)).toList();

      // Sort by timestamp (newest first)
      scans.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      debugPrint('🔍 Converted ${scans.length} scans successfully');
      return scans;
    } catch (error) {
      debugPrint('🔍 Error in getScanRecordsOnce: $error');
      return <ScanRecord>[];
    }
  }

  // Helper method to convert scan document to ScanRecord (simplified approach like admin portal)
  ScanRecord _convertScanDocToScanRecord(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    try {
      // Convert timestamp properly
      DateTime timestamp;
      if (data['timestamp'] is int) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(data['timestamp']);
      } else if (data['timestamp'] is Timestamp) {
        timestamp = (data['timestamp'] as Timestamp).toDate();
      } else if (data['timestamp'] is String) {
        timestamp = DateTime.parse(data['timestamp']);
      } else {
        timestamp = DateTime.now();
      }

      // Create ScanRecord directly (like admin portal approach)
      return ScanRecord(
        id: doc.id,
        code: data['code']?.toString() ?? '',
        symbology: data['symbology']?.toString(),
        timestamp: timestamp,
        eventId: data['listId']?.toString() ?? data['eventId']?.toString(),
        studentId: data['studentId']?.toString(),
        deviceId: data['deviceId']?.toString() ?? '',
        processed: data['verified'] == true || data['processed'] == true,
        synced: data['synced'] == true,
        metadata: (data['metadata'] as Map<String, dynamic>?) ?? {},
      );
    } catch (e) {
      debugPrint('🔍 Error converting scan ${doc.id}: $e');
      debugPrint('🔍 Raw data: ${data.toString()}');

      // Return a fallback ScanRecord to prevent crashes
      return ScanRecord(
        id: doc.id,
        code: data['code']?.toString() ?? 'UNKNOWN',
        symbology: 'UNKNOWN',
        timestamp: DateTime.now(),
        eventId: data['listId']?.toString() ?? data['eventId']?.toString(),
        studentId: data['studentId']?.toString(),
        deviceId: '',
        processed: false,
        synced: false,
        metadata: {},
      );
    }
  }

  // Helper method to convert flat structure scan to ScanRecord
  ScanRecord _convertFlatScanToScanRecord(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final convertedData = {
      'id': doc.id,
      'code': data['code'],
      'symbology': data['symbology'],
      'timestamp': data['timestamp'] is int
          ? DateTime.fromMillisecondsSinceEpoch(data['timestamp'])
              .toIso8601String()
          : data['timestamp'],
      'eventId': data['listId'], // Admin portal uses 'listId' field
      'studentId': data['studentId'],
      'deviceId': data['deviceId'] ?? '',
      'processed': data['verified'] ?? false,
      'synced': data['synced'] ?? false,
      'metadata': data['metadata'] ?? {},
    };

    return ScanRecord.fromJson(convertedData);
  }

  // Helper method to convert nested structure scan to ScanRecord
  ScanRecord _convertNestedScanToScanRecord(
      QueryDocumentSnapshot doc, String eventId) {
    final data = doc.data() as Map<String, dynamic>;

    final convertedData = {
      'id': doc.id,
      'code': data['code'],
      'symbology': data['symbology'] ?? '',
      'timestamp': data['timestamp'] is int
          ? DateTime.fromMillisecondsSinceEpoch(data['timestamp'])
              .toIso8601String()
          : (data['timestamp'] is Timestamp
              ? (data['timestamp'] as Timestamp).toDate().toIso8601String()
              : DateTime.now().toIso8601String()),
      'eventId': eventId,
      'studentId': data['studentId'] ?? '',
      'deviceId': data['deviceId'] ?? '',
      'processed': data['processed'] ?? false,
      'synced': data['synced'] ?? false,
      'metadata': data['metadata'] ?? {},
    };

    return ScanRecord.fromJson(convertedData);
  }

  // Events
  Future<void> addEvent(Event event) async {
    if (!isAvailable) {
      debugPrint('Firebase not available, event not synced');
      return;
    }

    try {
      await _firestore!.collection('events').doc(event.id).set(event.toJson());
      debugPrint('Event synced to Firebase: ${event.id}');
    } catch (e) {
      debugPrint('Failed to sync event: $e');
    }
  }

  Future<void> updateEvent(Event event) async {
    if (!isAvailable) {
      debugPrint('Firebase not available, event update not synced');
      return;
    }

    try {
      await _firestore!
          .collection('events')
          .doc(event.id)
          .update(event.toJson());
      debugPrint('Event updated in Firebase: ${event.id}');
    } catch (e) {
      debugPrint('Failed to update event: $e');
    }
  }


  // Students
  Future<void> addStudent(Student student) async {
    if (!isAvailable) {
      debugPrint('Firebase not available, student not synced');
      return;
    }

    try {
      await _firestore!
          .collection('students')
          .doc(student.studentId)
          .set(student.toJson());
      debugPrint('Student synced to Firebase: ${student.studentId}');
    } catch (e) {
      debugPrint('Failed to sync student: $e');
    }
  }


  Future<List<Student>> searchStudents(String query) async {
    if (!isAvailable) {
      debugPrint('Firebase not available, cannot search students');
      return [];
    }

    if (query.length < 2) {
      debugPrint('Search query too short: $query');
      return [];
    }

    try {
      debugPrint('Searching students for: "$query"');

      // Get all students and filter client-side for better search flexibility
      // This is acceptable for small datasets (< 1000 students)
      final snapshot = await _firestore!
          .collection('students')
          .limit(500) // Reasonable limit for client-side filtering
          .get();

      debugPrint('Retrieved ${snapshot.docs.length} students from Firebase');

      final List<Student> allStudents = [];
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final convertedData = _convertFirestoreTimestamps(data);
          final student = Student.fromJson(convertedData);
          allStudents.add(student);
        } catch (e) {
          debugPrint('Error parsing student document ${doc.id}: $e');
        }
      }

      debugPrint('Successfully parsed ${allStudents.length} students');

      // Client-side case-insensitive search
      final queryLower = query.toLowerCase();
      final matchingStudents = allStudents
          .where((student) {
            final firstNameMatch =
                student.firstName.toLowerCase().contains(queryLower);
            final lastNameMatch =
                student.lastName.toLowerCase().contains(queryLower);
            final emailMatch = student.email.toLowerCase().contains(queryLower);
            final studentIdMatch =
                student.studentId.toLowerCase().contains(queryLower);

            return firstNameMatch ||
                lastNameMatch ||
                emailMatch ||
                studentIdMatch;
          })
          .take(10)
          .toList();

      debugPrint(
          'Found ${matchingStudents.length} matching students for "$query"');

      // Debug: Print first few matches
      for (int i = 0; i < matchingStudents.length && i < 3; i++) {
        final student = matchingStudents[i];
        debugPrint(
            'Match $i: ${student.firstName} ${student.lastName} (${student.studentId})');
      }

      return matchingStudents;
    } catch (e) {
      debugPrint('Failed to search students: $e');
      return [];
    }
  }

  // Error Records
  Future<void> addErrorRecord(error_model.ErrorRecord errorRecord) async {
    if (!isAvailable) {
      debugPrint('Firebase not available, error record not synced');
      return;
    }

    try {
      await _firestore!
          .collection('error_records')
          .doc(errorRecord.id)
          .set(errorRecord.toJson());
      debugPrint('Error record synced to Firebase: ${errorRecord.id}');
    } catch (e) {
      debugPrint('Failed to sync error record: $e');
    }
  }

  // Batch Operations
  Future<void> batchSyncScanRecords(List<ScanRecord> scanRecords) async {
    if (!isAvailable || scanRecords.isEmpty) {
      debugPrint('Firebase not available or no records to sync');
      return;
    }

    try {
      final batch = _firestore!.batch();

      for (final record in scanRecords) {
        // Convert to admin portal format for batch operations too
        final scanData = {
          'code': record.code,
          'timestamp': record.timestamp.millisecondsSinceEpoch,
          'listId':
              record.eventId, // Admin portal uses 'listId' instead of 'eventId'
          'deviceId': record.deviceId,
          'verified': record
              .processed, // Admin portal uses 'verified' instead of 'processed'
          'symbology': record.symbology,
          'studentId': record.studentId,
          'synced': record.synced,
          'metadata': record.metadata,
        };

        final docRef = _firestore!
            .collection('scans')
            .doc(record.id); // Use 'scans' collection
        batch.set(docRef, scanData);
      }

      await batch.commit();
      debugPrint('Batch synced ${scanRecords.length} scan records');
    } catch (e) {
      debugPrint('Failed to batch sync scan records: $e');
    }
  }

  // Event completion notification
  Future<void> notifyEventCompleted(Event event, int totalScans) async {
    if (!isAvailable) {
      debugPrint('Firebase not available, event completion not notified');
      return;
    }

    try {
      await _firestore!.collection('notifications').add({
        'type': 'EVENT_COMPLETED',
        'eventId': event.id,
        'eventName': event.name,
        'eventNumber': event.eventNumber,
        'completedAt': FieldValue.serverTimestamp(),
        'totalScans': totalScans,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'exported': false,
      });

      debugPrint(
          'Event completion notified: ${event.name} with $totalScans scans');
    } catch (e) {
      debugPrint('Failed to notify event completion: $e');
    }
  }

  // Additional methods expected by ScannerProvider
  Future<void> uploadScan(ScanRecord scanRecord) async {
    return addScanRecord(scanRecord);
  }

  Future<void> saveErrorRecord(
    String scannedId,
    String email,
    String eventId,
    String eventName,
    String eventDate,
  ) async {
    final errorRecord = error_model.ErrorRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      scannedId: scannedId,
      studentEmail: email,
      eventId: eventId,
      eventName: eventName,
      eventDate: eventDate,
      timestamp: DateTime.now(),
      resolved: false,
    );

    return addErrorRecord(errorRecord);
  }

  // Helper method to convert Firestore Timestamps to ISO8601 strings
  Map<String, dynamic> _convertFirestoreTimestamps(Map<String, dynamic> data) {
    final converted = <String, dynamic>{};

    for (final entry in data.entries) {
      if (entry.value is Timestamp) {
        // Convert Firestore Timestamp to ISO8601 string
        final timestamp = entry.value as Timestamp;
        converted[entry.key] = timestamp.toDate().toIso8601String();
      } else if (entry.value is int && _isTimestampField(entry.key)) {
        // Convert integer timestamps (milliseconds since epoch) to ISO8601 string
        final timestamp = DateTime.fromMillisecondsSinceEpoch(entry.value);
        converted[entry.key] = timestamp.toIso8601String();
      } else if (entry.value is Map<String, dynamic>) {
        // Recursively convert nested maps
        converted[entry.key] = _convertFirestoreTimestamps(entry.value);
      } else if (entry.value is List) {
        // Handle lists that might contain maps with timestamps
        converted[entry.key] = _convertFirestoreList(entry.value);
      } else {
        // Keep other values as-is
        converted[entry.key] = entry.value;
      }
    }

    return converted;
  }

  // Helper method to identify timestamp fields
  bool _isTimestampField(String fieldName) {
    const timestampFields = {
      'createdAt',
      'completedAt',
      'date',
      'scannedAt',
      'timestamp',
      'uploadedAt',
    };
    return timestampFields.contains(fieldName);
  }

  // Events - Load from Firestore
  Future<List<Event>> getEvents() async {
    if (!isAvailable) return [];

    try {
      final QuerySnapshot snapshot = await _firestore!
          .collection('events')
          .orderBy('eventNumber', descending: false)
          .get();

      final List<Event> events = [];
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        
        try {
          final event = Event(
            id: doc.id,
            eventNumber: data['eventNumber'] as int? ?? 0,
            name: data['name'] as String? ?? 'Unnamed Event',
            description: data['description'] as String? ?? '',
            location: data['location'] as String? ?? '',
            date: data['date'] != null 
                ? (data['date'] as Timestamp).toDate()
                : DateTime.now(),
            createdAt: data['createdAt'] != null
                ? (data['createdAt'] as Timestamp).toDate()
                : DateTime.now(),
            isActive: data['isActive'] as bool? ?? true,
            isCompleted: data['isCompleted'] as bool? ?? false,
          );
          events.add(event);
        } catch (e) {
          debugPrint('Error parsing event ${doc.id}: $e');
        }
      }

      debugPrint('✅ Loaded ${events.length} events from Firestore');
      return events;
    } catch (e) {
      debugPrint('❌ Error loading events from Firestore: $e');
      return [];
    }
  }

  // Students - Load from Firestore
  Future<Student?> getStudent(String studentId) async {
    if (!isAvailable) return null;

    try {
      final DocumentSnapshot doc = await _firestore!
          .collection('students')
          .doc(studentId)
          .get();

      if (!doc.exists) return null;

      final data = doc.data() as Map<String, dynamic>;
      return Student(
        studentId: doc.id,
        firstName: data['firstName'] as String? ?? data['first_name'] as String? ?? 'Unknown',
        lastName: data['lastName'] as String? ?? data['last_name'] as String? ?? 'Student',
        email: data['email'] as String? ?? '',
        program: data['program'] as String? ?? '',
        year: data['year'] as String? ?? '',
        active: data['active'] as bool? ?? data['isActive'] as bool? ?? true,
      );
    } catch (e) {
      debugPrint('❌ Error loading student $studentId: $e');
      return null;
    }
  }

  // Helper method to convert lists that might contain Firestore Timestamps
  List<dynamic> _convertFirestoreList(List<dynamic> list) {
    return list.map((item) {
      if (item is Timestamp) {
        return item.toDate().toIso8601String();
      } else if (item is Map<String, dynamic>) {
        return _convertFirestoreTimestamps(item);
      } else {
        return item;
      }
    }).toList();
  }
}
