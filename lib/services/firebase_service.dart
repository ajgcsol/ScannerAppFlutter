import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';  // Disabled due to BoringSSL issues
import '../models/scan_record.dart';
import '../models/event.dart';
import '../models/student.dart';
import '../models/error_record.dart' as error_model;

class FirebaseService {
  static FirebaseService? _instance;
  static FirebaseService get instance => _instance ??= FirebaseService._();

  FirebaseService._();

  late final Dio _dio;
  static const String _baseUrl = 'https://insession-api-fc.azurewebsites.net';

  // The backend requires an authenticated caller on every endpoint that touches
  // student data. Supplied at build time so the key never lands in source
  // control: flutter build ios --dart-define=INSESSION_API_KEY=<key>
  static const String _apiKey = String.fromEnvironment('INSESSION_API_KEY');
  
  bool _isInitialized = false;
  Object? _authService; // AuthService once sign-in completes (kept untyped to avoid a hard import cycle)

  // FirebaseFirestore? _firestore;  // Disabled due to BoringSSL issues
  bool get isInitialized => _isInitialized;
  bool get isAvailable => _isInitialized;
  bool get isConnected => _isInitialized;

  /// Called after Microsoft 365 sign-in so every request carries the user.
  void attachAuth(Object authService) {
    _authService = authService;
  }

  Future<void> initialize() async {
    debugPrint('🔥 Firebase initialize() started');
    debugPrint('🔥 Base URL: $_baseUrl');
    
    try {
      _dio = Dio(BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          if (_apiKey.isNotEmpty) 'x-api-key': _apiKey,
        },
      ));

      if (_apiKey.isEmpty) {
        debugPrint(
          '⚠️ INSESSION_API_KEY was not set at build time; '
          'the backend will reject requests with 401.',
        );
      }

      // Signed-in requests carry the user's Microsoft 365 token; the shared
      // key stays as a fallback so scanning keeps working mid-transition.
      _dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) async {
          final auth = _authService;
          if (auth != null) {
            try {
              final token = await (auth as dynamic).bearerToken();
              if (token != null) {
                options.headers['Authorization'] = 'Bearer $token';
              }
            } catch (_) {}
          }
          handler.next(options);
        },
      ));

      // Add logging interceptor for debugging
      if (kDebugMode) {
        _dio.interceptors.add(LogInterceptor(
          requestBody: true,
          responseBody: true,
          error: true,
          request: true,
          logPrint: (obj) => debugPrint('🌐 HTTP: $obj'),
        ));
      }

      // Initialize Firestore (disabled due to BoringSSL issues)
      // try {
      //   _firestore = FirebaseFirestore.instance;
      //   debugPrint('🔥 Firestore initialized successfully');
      // } catch (e) {
      //   debugPrint('🔥 Firestore initialization failed: $e');
      // }
      
      _isInitialized = true;
      debugPrint('🔥 Firebase Functions service initialized successfully - isInitialized: $_isInitialized');
    } catch (e) {
      debugPrint('🔥 Firebase Functions initialization failed: $e');
      _isInitialized = false;
    }
  }

  /// Saves a free-text note on a scan (prospect scan lists).
  Future<bool> updateScanNote(String scanId, String eventId, String note) async {
    try {
      final response = await _dio.patch('/data/scans/$scanId', data: {'note': note});
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('🔥 updateScanNote failed: $e');
      return false;
    }
  }

  /// Emails the event's scan list to every member of the group.
  Future<Map<String, dynamic>?> emailEventReport(String eventId, String groupId) async {
    try {
      final response = await _dio.post('/emailEventReport',
          data: {'eventId': eventId, 'groupId': groupId});
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
    } catch (e) {
      debugPrint('🔥 emailEventReport failed: $e');
    }
    return null;
  }

  // Scan Records Operations
  Future<void> addScanRecord(ScanRecord scanRecord) async {
    debugPrint('🔥 ADD_SCAN: addScanRecord called for ${scanRecord.id}');
    if (!isAvailable) {
      debugPrint('🔥 ADD_SCAN: Firebase Functions not available, scan record not synced');
      return;
    }

    try {
      debugPrint('🔥 ADD_SCAN: Making POST request to /addScanRecord...');
      final response = await _dio.post('/addScanRecord', 
        data: scanRecord.toJson());
      
      debugPrint('🔥 ADD_SCAN: Response received - status: ${response.statusCode}');
      if (response.statusCode == 200) {
        debugPrint('🔥 ADD_SCAN: Scan record synced via Firebase Functions: ${scanRecord.id}');
      } else {
        debugPrint('🔥 ADD_SCAN: Failed to sync scan record: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      debugPrint('🔥 ADD_SCAN: Exception in addScanRecord: $e');
      debugPrint('🔥 ADD_SCAN: Stack trace: $stackTrace');
      // Don't rethrow - handle silently to prevent app crashes
    }
  }

  Future<List<ScanRecord>> getScanRecordsOnce({String? eventId, int? eventNumber}) async {
    if (!isAvailable) {
      return [];
    }

    try {
      // Always use eventId for consistency, ignore eventNumber to prevent confusion
      debugPrint('🔍 getScanRecordsOnce called with eventId: $eventId, eventNumber: $eventNumber (using eventId only)');
      
      // Use eventId parameter as expected by Firebase Function  
      final response = await _dio.get('/getScanRecords', 
        queryParameters: {'eventId': eventId});
      
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        debugPrint('🔍 Received ${data.length} scan records from Functions API');
        final scanRecords = data.map((item) => _convertScanDataToScanRecord(item)).toList();
        debugPrint('🔍 Successfully converted ${scanRecords.length} scan records');
        return scanRecords;
      } else {
        debugPrint('🔍 Error getting scan records - status: ${response.statusCode}');
        return [];
      }
    } catch (error) {
      debugPrint('🔍 Error in getScanRecordsOnce: $error');
      if (error is DioException) {
        debugPrint('🔍 DioException details: ${error.message}');
        debugPrint('🔍 Response: ${error.response}');
      }
      return [];
    }
  }

  // Keep stream method for compatibility, but convert to polling
  Stream<List<ScanRecord>> getScanRecords({String? eventId}) {
    return Stream.periodic(const Duration(seconds: 10))
        .asyncMap((_) => getScanRecordsOnce(eventId: eventId));
  }

  // Events Operations
  Future<List<Event>> getEvents() async {
    debugPrint('🔥 getEvents() called - isAvailable: $isAvailable');
    if (!isAvailable) {
      debugPrint('🔥 Firebase not available, returning empty events list');
      return [];
    }

    try {
      debugPrint('🔥 Making request to: $_baseUrl/getEvents');
      final response = await _dio.get('/getEvents');
      
      debugPrint('🔥 Response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        debugPrint('🔥 Received ${data.length} events from API');
        final events = data.map((item) => _convertEventData(item)).toList();
        debugPrint('🔥 Successfully converted ${events.length} events');
        return events;
      } else {
        debugPrint('🔥 Error getting events - status: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('🔥 Exception getting events: $e');
      if (e is DioException) {
        debugPrint('🔥 DioException details: ${e.message}');
        debugPrint('🔥 Response: ${e.response}');
      }
      return [];
    }
  }

  Event _convertEventData(Map<String, dynamic> data) {
    try {
      // Handle date field - could be string, int timestamp, or DateTime object
      DateTime eventDate;
      if (data['date'] is String) {
        eventDate = DateTime.parse(data['date']);
      } else if (data['date'] is int) {
        eventDate = DateTime.fromMillisecondsSinceEpoch(data['date']);
      } else {
        eventDate = DateTime.now();
      }

      // Handle createdAt field - could be string, int, or Firestore timestamp object
      DateTime createdAtDate;
      if (data['createdAt'] is Map && data['createdAt']['_seconds'] != null) {
        createdAtDate = DateTime.fromMillisecondsSinceEpoch(data['createdAt']['_seconds'] * 1000);
      } else if (data['createdAt'] is String) {
        createdAtDate = DateTime.parse(data['createdAt']);
      } else if (data['createdAt'] is int) {
        createdAtDate = DateTime.fromMillisecondsSinceEpoch(data['createdAt']);
      } else {
        createdAtDate = DateTime.now();
      }

      // Handle completedAt field - could be null, string, or int
      DateTime? completedAtDate;
      if (data['completedAt'] != null) {
        if (data['completedAt'] is String) {
          completedAtDate = DateTime.parse(data['completedAt']);
        } else if (data['completedAt'] is int) {
          completedAtDate = DateTime.fromMillisecondsSinceEpoch(data['completedAt']);
        }
      }

      return Event(
        id: data['id']?.toString() ?? '',
        eventNumber: data['eventNumber'] ?? 0,
        name: data['name']?.toString() ?? '',
        description: data['description']?.toString() ?? '',
        date: eventDate,
        location: data['location']?.toString() ?? '',
        isActive: data['isActive'] == true || data['active'] == true,
        isCompleted: data['isCompleted'] == true || data['completed'] == true,
        completedAt: completedAtDate,
        createdAt: createdAtDate,
        createdBy: data['createdBy']?.toString() ?? '',
        groupId: data['groupId'],
        customColumns: [], // TODO: Parse custom columns if needed
        staticValues: Map<String, String>.from(data['staticValues'] ?? {}),
        exportFormat: ExportFormat.textDelimited, // Default for now
      );
    } catch (e) {
      debugPrint('Error converting event data: $e');
      debugPrint('Raw event data: ${data.toString()}');
      
      // Return a fallback event to prevent crashes
      return Event(
        id: data['id']?.toString() ?? 'UNKNOWN',
        eventNumber: 0,
        name: data['name']?.toString() ?? 'Unknown Event',
        description: '',
        date: DateTime.now(),
        location: '',
        isActive: false,
        isCompleted: false,
        createdAt: DateTime.now(),
      );
    }
  }

  // Students Operations
  Future<List<Student>> getStudents() async {
    if (!isAvailable) return [];

    try {
      final response = await _dio.get('/getStudents');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((item) => Student.fromJson(item)).toList();
      } else {
        debugPrint('Error getting students: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('Error getting students: $e');
      return [];
    }
  }

  Future<Student?> getStudentByStudentId(String studentId) async {
    if (!isAvailable) return null;

    try {
      final response = await _dio.get('/getStudentById', 
        queryParameters: {'studentId': studentId});
      
      if (response.statusCode == 200) {
        return Student.fromJson(response.data);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        debugPrint('Error getting student: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error getting student: $e');
      return null;
    }
  }

  // Error Records
  Future<void> addErrorRecord(error_model.ErrorRecord errorRecord) async {
    if (!isAvailable) return;

    try {
      await _dio.post('/addErrorRecord', data: errorRecord.toJson());
      debugPrint('Error record synced via Firebase Functions');
    } catch (e) {
      debugPrint('Failed to sync error record via Functions: $e');
    }
  }


  // Helper method to convert Firebase Functions response to ScanRecord
  ScanRecord _convertScanDataToScanRecord(Map<String, dynamic> data) {
    try {
      // Convert timestamp properly
      DateTime timestamp;
      if (data['timestamp'] is int) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(data['timestamp']);
      } else if (data['timestamp'] is Map && data['timestamp']['seconds'] != null) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(data['timestamp']['seconds'] * 1000);
      } else if (data['timestamp'] is String) {
        timestamp = DateTime.parse(data['timestamp']);
      } else {
        timestamp = DateTime.now();
      }

      return ScanRecord(
        id: data['id'] ?? '',
        code: data['code']?.toString() ?? '',
        symbology: data['symbology']?.toString(),
        timestamp: timestamp,
        eventId: data['listId']?.toString() ?? data['eventId']?.toString(),
        studentId: data['studentId']?.toString(),
        deviceId: data['deviceId']?.toString() ?? '',
        processed: data['verified'] == true || data['processed'] == true,
        synced: data['synced'] == true,
        metadata: Map<String, dynamic>.from(data['metadata'] ?? {}),
        note: data['note']?.toString(),
      );
    } catch (e) {
      debugPrint('🔍 Error converting scan data: $e');
      debugPrint('🔍 Raw data: ${data.toString()}');
      
      // Return a fallback ScanRecord to prevent crashes
      return ScanRecord(
        id: data['id']?.toString() ?? 'UNKNOWN',
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

  // Create a new event
  Future<Event> createEvent(Event event) async {
    try {
      debugPrint('🔥 Creating event: ${event.name} (${event.eventNumber})');
      
      final eventData = {
        'eventNumber': event.eventNumber,
        'name': event.name,
        'description': event.description,
        'date': event.date.toIso8601String(),
        'location': event.location,
        'isActive': event.isActive,
        'isCompleted': event.isCompleted,
        'completedAt': event.completedAt?.toIso8601String(),
        'createdBy': event.createdBy,
        'customColumns': event.customColumns.map((col) => col.toJson()).toList(),
        'staticValues': event.staticValues,
        'exportFormat': event.exportFormat.toString().split('.').last.toUpperCase(),
        'groupId': event.groupId,
      };
      
      final response = await _dio.post('/createEvent', data: eventData);
      
      if (response.statusCode == 201) {
        final responseData = response.data as Map<String, dynamic>;
        final createdEventData = responseData['event'] as Map<String, dynamic>;
        
        debugPrint('🔥 Event created successfully: ${createdEventData['id']}');
        
        // Convert the response back to an Event object
        return Event(
          id: createdEventData['id'],
          eventNumber: createdEventData['eventNumber'],
          name: createdEventData['name'],
          description: createdEventData['description'] ?? '',
          date: DateTime.parse(createdEventData['date']),
          location: createdEventData['location'] ?? '',
          isActive: createdEventData['isActive'] ?? true,
          isCompleted: createdEventData['isCompleted'] ?? false,
          completedAt: createdEventData['completedAt'] != null 
            ? DateTime.parse(createdEventData['completedAt']) 
            : null,
          createdAt: DateTime.parse(createdEventData['createdAt']),
          createdBy: createdEventData['createdBy'] ?? '',
          customColumns: (createdEventData['customColumns'] as List?)
            ?.map((col) => EventColumn.fromJson(col))
            .toList() ?? [],
          staticValues: Map<String, String>.from(createdEventData['staticValues'] ?? {}),
          exportFormat: _parseExportFormat(createdEventData['exportFormat']),
        );
      } else {
        throw Exception('Failed to create event: ${response.statusCode}');
      }
    } on DioException catch (e) {
      debugPrint('🔥 DioException creating event: ${e.response?.data}');
      if (e.response?.statusCode == 409) {
        final errorData = e.response?.data as Map<String, dynamic>?;
        throw Exception(errorData?['error'] ?? 'Event number already exists');
      }
      throw Exception('Network error creating event: ${e.message}');
    } catch (e) {
      debugPrint('🔥 Error creating event: $e');
      rethrow;
    }
  }

  ExportFormat _parseExportFormat(String? format) {
    switch (format?.toUpperCase()) {
      case 'CSV':
        return ExportFormat.csv;
      case 'FIXED_WIDTH':
        return ExportFormat.fixedWidth;
      case 'XLSX':
        return ExportFormat.xlsx;
      case 'TEXT_DELIMITED':
      default:
        return ExportFormat.textDelimited;
    }
  }

  Future<Event> updateEvent(Event event) async {
    debugPrint('🔥 Updating event: ${event.id}');

    try {
      final response = await _dio.put(
        '$_baseUrl/updateEvent',
        data: {
          'id': event.id,
          'eventNumber': event.eventNumber,
          'name': event.name,
          'description': event.description,
          'location': event.location,
          'date': event.date.toIso8601String(),
          'isActive': event.isActive,
          'isCompleted': event.isCompleted,
          'completedAt': event.completedAt?.toIso8601String(),
          'exportFormat': event.exportFormat.name.toUpperCase(),
        },
      );

      if (response.statusCode == 200) {
        debugPrint('🔥 Event updated successfully');
        final updatedEventData = response.data as Map<String, dynamic>;
        
        return Event(
          id: updatedEventData['id'],
          eventNumber: updatedEventData['eventNumber'],
          name: updatedEventData['name'],
          description: updatedEventData['description'] ?? '',
          date: DateTime.parse(updatedEventData['date']),
          location: updatedEventData['location'] ?? '',
          isActive: updatedEventData['isActive'] ?? true,
          isCompleted: updatedEventData['isCompleted'] ?? false,
          completedAt: updatedEventData['completedAt'] != null 
            ? DateTime.parse(updatedEventData['completedAt']) 
            : null,
          createdAt: DateTime.parse(updatedEventData['createdAt']),
          createdBy: updatedEventData['createdBy'] ?? '',
          exportFormat: _parseExportFormat(updatedEventData['exportFormat']),
        );
      } else {
        throw Exception('Failed to update event: ${response.statusCode}');
      }
    } on DioException catch (e) {
      debugPrint('🔥 DioException updating event: ${e.response?.data}');
      throw Exception('Network error updating event: ${e.message}');
    } catch (e) {
      debugPrint('🔥 Error updating event: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getDeletedEvents() async {
    try {
      debugPrint('🔥 Fetching deleted events from Firebase Functions');
      
      final response = await _dio.get(
        'https://insession-api-fc.azurewebsites.net/getDeletedEvents',
        options: Options(
          headers: {'Content-Type': 'application/json'},
        ),
      );

      if (response.statusCode == 200 && response.data is List) {
        final deletedEvents = List<Map<String, dynamic>>.from(response.data);
        debugPrint('🔥 Retrieved ${deletedEvents.length} deleted events');
        return deletedEvents;
      } else {
        debugPrint('🔥 Unexpected response format for deleted events');
        return [];
      }
    } on DioException catch (e) {
      debugPrint('🔥 DioException fetching deleted events: ${e.response?.data}');
      throw Exception('Network error fetching deleted events: ${e.message}');
    } catch (e) {
      debugPrint('🔥 Error fetching deleted events: $e');
      return []; // Return empty list on error to avoid disrupting the app
    }
  }
}