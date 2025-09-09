import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/event.dart';
import '../models/student.dart';
import '../models/scan_record.dart';
import '../models/error_record.dart' as error_model;

class DatabaseService {
  static Database? _database;
  static const String _databaseName = 'insession.db';
  static const int _databaseVersion = 2; // Bumped to remove sample data

  // Table names
  static const String _eventsTable = 'events';
  static const String _studentsTable = 'students';
  static const String _scansTable = 'scans';
  static const String _errorRecordsTable = 'error_records';

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite is not supported on web platform');
    }
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite is not supported on web platform');
    }
    
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _databaseName);
    
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create events table
    await db.execute('''
      CREATE TABLE $_eventsTable (
        id TEXT PRIMARY KEY,
        eventNumber INTEGER NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        date INTEGER NOT NULL,
        location TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        isCompleted INTEGER NOT NULL DEFAULT 0,
        completedAt INTEGER,
        createdAt INTEGER NOT NULL,
        createdBy TEXT,
        exportFormat TEXT NOT NULL DEFAULT 'textDelimited'
      )
    ''');

    // Create students table
    await db.execute('''
      CREATE TABLE $_studentsTable (
        studentId TEXT PRIMARY KEY,
        firstName TEXT NOT NULL,
        lastName TEXT NOT NULL,
        email TEXT NOT NULL,
        program TEXT,
        year TEXT,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Create scans table
    await db.execute('''
      CREATE TABLE $_scansTable (
        id TEXT PRIMARY KEY,
        code TEXT NOT NULL,
        symbology TEXT,
        timestamp INTEGER NOT NULL,
        eventId TEXT NOT NULL,
        studentId TEXT,
        deviceId TEXT,
        synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (eventId) REFERENCES $_eventsTable (id),
        FOREIGN KEY (studentId) REFERENCES $_studentsTable (studentId)
      )
    ''');

    // Create error records table
    await db.execute('''
      CREATE TABLE $_errorRecordsTable (
        id TEXT PRIMARY KEY,
        scannedId TEXT NOT NULL,
        studentEmail TEXT NOT NULL,
        eventId TEXT NOT NULL,
        eventName TEXT NOT NULL,
        eventDate TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        resolved INTEGER NOT NULL DEFAULT 0,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Create indexes
    await db.execute('CREATE INDEX idx_scans_event ON $_scansTable (eventId)');
    await db.execute('CREATE INDEX idx_scans_student ON $_scansTable (studentId)');
    await db.execute('CREATE INDEX idx_scans_timestamp ON $_scansTable (timestamp)');
    await db.execute('CREATE INDEX idx_students_name ON $_studentsTable (firstName, lastName)');

    // Don't insert sample data - use real Firebase data only
    // await _insertSampleData(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle database upgrades here
    if (oldVersion < newVersion) {
      // Add migration logic as needed
    }
  }

  Future<void> _insertSampleData(Database db) async {
    // Insert sample students
    final sampleStudents = [
      {
        'studentId': 'STUDENT_001',
        'firstName': 'John',
        'lastName': 'Doe',
        'email': 'john.doe@charlestonlaw.edu',
        'program': 'JD',
        'year': '2L',
        'active': 1,
      },
      {
        'studentId': 'STUDENT_002',
        'firstName': 'Jane',
        'lastName': 'Smith',
        'email': 'jane.smith@charlestonlaw.edu',
        'program': 'JD',
        'year': '3L',
        'active': 1,
      },
      {
        'studentId': 'STUDENT_003',
        'firstName': 'Michael',
        'lastName': 'Johnson',
        'email': 'michael.johnson@charlestonlaw.edu',
        'program': 'LLM',
        'year': '1L',
        'active': 1,
      },
      {
        'studentId': '1234567890123',
        'firstName': 'Test',
        'lastName': 'Student',
        'email': 'test.student@charlestonlaw.edu',
        'program': 'JD',
        'year': '1L',
        'active': 1,
      },
    ];

    for (final student in sampleStudents) {
      await db.insert(_studentsTable, student);
    }

    // Insert sample event
    final sampleEvent = {
      'id': 'event_${DateTime.now().millisecondsSinceEpoch}',
      'eventNumber': 1,
      'name': 'Sample Event',
      'description': 'This is a sample event for testing',
      'date': DateTime.now().millisecondsSinceEpoch,
      'location': 'Charleston Law School',
      'isActive': 1,
      'isCompleted': 0,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'createdBy': 'System',
      'exportFormat': 'textDelimited',
    };

    await db.insert(_eventsTable, sampleEvent);
  }

  // Event operations
  Future<List<Event>> getAllEvents() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _eventsTable,
      orderBy: 'createdAt DESC',
    );

    return List.generate(maps.length, (i) {
      return Event(
        id: maps[i]['id'],
        eventNumber: maps[i]['eventNumber'],
        name: maps[i]['name'],
        description: maps[i]['description'] ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(maps[i]['date']),
        location: maps[i]['location'] ?? '',
        isActive: maps[i]['isActive'] == 1,
        isCompleted: maps[i]['isCompleted'] == 1,
        completedAt: maps[i]['completedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(maps[i]['completedAt'])
            : null,
        createdAt: DateTime.fromMillisecondsSinceEpoch(maps[i]['createdAt']),
        createdBy: maps[i]['createdBy'] ?? '',
        exportFormat: ExportFormat.values.firstWhere(
          (e) => e.toString().split('.').last == maps[i]['exportFormat'],
          orElse: () => ExportFormat.textDelimited,
        ),
      );
    });
  }

  Future<void> insertEvent(Event event) async {
    final db = await database;
    await db.insert(
      _eventsTable,
      {
        'id': event.id,
        'eventNumber': event.eventNumber,
        'name': event.name,
        'description': event.description,
        'date': event.date.millisecondsSinceEpoch,
        'location': event.location,
        'isActive': event.isActive ? 1 : 0,
        'isCompleted': event.isCompleted ? 1 : 0,
        'completedAt': event.completedAt?.millisecondsSinceEpoch,
        'createdAt': event.createdAt.millisecondsSinceEpoch,
        'createdBy': event.createdBy,
        'exportFormat': event.exportFormat.toString().split('.').last,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateEvent(Event event) async {
    final db = await database;
    await db.update(
      _eventsTable,
      {
        'eventNumber': event.eventNumber,
        'name': event.name,
        'description': event.description,
        'date': event.date.millisecondsSinceEpoch,
        'location': event.location,
        'isActive': event.isActive ? 1 : 0,
        'isCompleted': event.isCompleted ? 1 : 0,
        'completedAt': event.completedAt?.millisecondsSinceEpoch,
        'createdBy': event.createdBy,
        'exportFormat': event.exportFormat.toString().split('.').last,
      },
      where: 'id = ?',
      whereArgs: [event.id],
    );
  }

  // Student operations
  Future<List<Student>> getAllStudents() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _studentsTable,
      where: 'active = ?',
      whereArgs: [1],
      orderBy: 'lastName, firstName',
    );

    return List.generate(maps.length, (i) {
      return Student(
        studentId: maps[i]['studentId'],
        firstName: maps[i]['firstName'],
        lastName: maps[i]['lastName'],
        email: maps[i]['email'],
        program: maps[i]['program'] ?? '',
        year: maps[i]['year'] ?? '',
        active: maps[i]['active'] == 1,
      );
    });
  }

  Future<Student?> getStudentById(String studentId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _studentsTable,
      where: 'studentId = ? AND active = ?',
      whereArgs: [studentId, 1],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return Student(
        studentId: maps[0]['studentId'],
        firstName: maps[0]['firstName'],
        lastName: maps[0]['lastName'],
        email: maps[0]['email'],
        program: maps[0]['program'] ?? '',
        year: maps[0]['year'] ?? '',
        active: maps[0]['active'] == 1,
      );
    }
    return null;
  }

  Future<List<Student>> searchStudents(String query) async {
    final db = await database;
    final searchTerm = '%$query%';
    final List<Map<String, dynamic>> maps = await db.query(
      _studentsTable,
      where: '''
        active = ? AND (
          firstName LIKE ? OR 
          lastName LIKE ? OR 
          email LIKE ? OR 
          studentId LIKE ?
        )
      ''',
      whereArgs: [1, searchTerm, searchTerm, searchTerm, searchTerm],
      orderBy: 'lastName, firstName',
      limit: 20,
    );

    return List.generate(maps.length, (i) {
      return Student(
        studentId: maps[i]['studentId'],
        firstName: maps[i]['firstName'],
        lastName: maps[i]['lastName'],
        email: maps[i]['email'],
        program: maps[i]['program'] ?? '',
        year: maps[i]['year'] ?? '',
        active: maps[i]['active'] == 1,
      );
    });
  }

  Future<void> insertStudent(Student student) async {
    final db = await database;
    await db.insert(
      _studentsTable,
      {
        'studentId': student.studentId,
        'firstName': student.firstName,
        'lastName': student.lastName,
        'email': student.email,
        'program': student.program,
        'year': student.year,
        'active': student.active ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Scan operations
  Future<List<ScanRecord>> getScansForEvent(String eventId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _scansTable,
      where: 'eventId = ?',
      whereArgs: [eventId],
      orderBy: 'timestamp DESC',
    );

    return List.generate(maps.length, (i) {
      return ScanRecord(
        id: maps[i]['id'],
        code: maps[i]['code'],
        symbology: maps[i]['symbology'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(maps[i]['timestamp']),
        eventId: maps[i]['eventId'],
        studentId: maps[i]['studentId'],
        deviceId: maps[i]['deviceId'] ?? '',
        synced: maps[i]['synced'] == 1,
      );
    });
  }

  Future<List<ScanRecord>> getScansForStudentInEvent(String studentId, String eventId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _scansTable,
      where: 'studentId = ? AND eventId = ?',
      whereArgs: [studentId, eventId],
      orderBy: 'timestamp DESC',
    );

    return List.generate(maps.length, (i) {
      return ScanRecord(
        id: maps[i]['id'],
        code: maps[i]['code'],
        symbology: maps[i]['symbology'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(maps[i]['timestamp']),
        eventId: maps[i]['eventId'],
        studentId: maps[i]['studentId'],
        deviceId: maps[i]['deviceId'] ?? '',
        synced: maps[i]['synced'] == 1,
      );
    });
  }

  Future<void> insertScan(ScanRecord scan) async {
    final db = await database;
    await db.insert(
      _scansTable,
      {
        'id': scan.id,
        'code': scan.code,
        'symbology': scan.symbology,
        'timestamp': scan.timestamp.millisecondsSinceEpoch,
        'eventId': scan.eventId,
        'studentId': scan.studentId,
        'deviceId': scan.deviceId,
        'synced': scan.synced ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markScanAsSynced(String scanId) async {
    final db = await database;
    await db.update(
      _scansTable,
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [scanId],
    );
  }

  Future<List<ScanRecord>> getUnsyncedScans() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _scansTable,
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
    );

    return List.generate(maps.length, (i) {
      return ScanRecord(
        id: maps[i]['id'],
        code: maps[i]['code'],
        symbology: maps[i]['symbology'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(maps[i]['timestamp']),
        eventId: maps[i]['eventId'],
        studentId: maps[i]['studentId'],
        deviceId: maps[i]['deviceId'] ?? '',
        synced: maps[i]['synced'] == 1,
      );
    });
  }

  // Error record operations
  Future<void> insertErrorRecord(error_model.ErrorRecord errorRecord) async {
    final db = await database;
    await db.insert(
      _errorRecordsTable,
      {
        'id': errorRecord.id,
        'scannedId': errorRecord.scannedId,
        'studentEmail': errorRecord.studentEmail,
        'eventId': errorRecord.eventId,
        'eventName': errorRecord.eventName,
        'eventDate': errorRecord.eventDate,
        'timestamp': errorRecord.timestamp.millisecondsSinceEpoch,
        'resolved': errorRecord.resolved ? 1 : 0,
        'synced': 0, // Default to not synced
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Database maintenance
  Future<void> clearOldData({int daysToKeep = 30}) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
    
    await db.delete(
      _scansTable,
      where: 'timestamp < ? AND synced = ?',
      whereArgs: [cutoffDate.millisecondsSinceEpoch, 1],
    );
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
