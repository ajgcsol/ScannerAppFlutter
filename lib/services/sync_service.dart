import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database_service.dart';
import 'firebase_service.dart';
import '../models/scan_record.dart';
import '../models/error_record.dart' as error_model;
import '../models/scan.dart';
import '../models/event.dart';
import '../models/student.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final DatabaseService _databaseService = DatabaseService();
  final FirebaseService _firebaseService = FirebaseService.instance;
  final Connectivity _connectivity = Connectivity();
  
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _syncTimer;
  bool _isSyncing = false;
  bool _isOnline = true;
  
  // Sync status stream
  final StreamController<SyncStatus> _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;
  
  // Current sync status
  SyncStatus _currentStatus = SyncStatus(
    isOnline: true,
    isSyncing: false,
    pendingScans: 0,
    pendingErrors: 0,
    lastSyncTime: null,
  );
  
  SyncStatus get currentStatus => _currentStatus;
  
  Future<void> initialize() async {
    debugPrint('🔄 SYNC: Initializing sync service');
    
    // Check initial connectivity
    await _checkConnectivity();
    
    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = results.any((result) => result != ConnectivityResult.none);
      
      debugPrint('🔄 SYNC: Connectivity changed - Online: $_isOnline');
      
      if (!wasOnline && _isOnline) {
        debugPrint('🔄 SYNC: Device came online, triggering sync');
        syncAll();
      }
      
      _updateStatus(isOnline: _isOnline);
    });
    
    // Start periodic sync timer (every 30 seconds when online)
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isOnline && !_isSyncing) {
        syncAll();
      }
    });
    
    // Initial sync if online
    if (_isOnline) {
      syncAll();
    }
  }
  
  Future<void> _checkConnectivity() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    _isOnline = connectivityResult.any((result) => result != ConnectivityResult.none);
    debugPrint('🔄 SYNC: Initial connectivity check - Online: $_isOnline');
    _updateStatus(isOnline: _isOnline);
  }
  
  void _updateStatus({
    bool? isOnline,
    bool? isSyncing,
    int? pendingScans,
    int? pendingErrors,
    DateTime? lastSyncTime,
  }) {
    _currentStatus = SyncStatus(
      isOnline: isOnline ?? _currentStatus.isOnline,
      isSyncing: isSyncing ?? _currentStatus.isSyncing,
      pendingScans: pendingScans ?? _currentStatus.pendingScans,
      pendingErrors: pendingErrors ?? _currentStatus.pendingErrors,
      lastSyncTime: lastSyncTime ?? _currentStatus.lastSyncTime,
    );
    _syncStatusController.add(_currentStatus);
  }
  
  Future<void> syncAll() async {
    if (_isSyncing) {
      debugPrint('🔄 SYNC: Already syncing, skipping');
      return;
    }
    
    if (!_isOnline) {
      debugPrint('🔄 SYNC: Device is offline, skipping sync');
      return;
    }
    
    _isSyncing = true;
    _updateStatus(isSyncing: true);
    
    debugPrint('🔄 SYNC: Starting sync process');
    
    try {
      // Sync events and students first (download from Firebase)
      await _syncEventsFromFirebase();
      await _syncStudentsFromFirebase();
      
      // Then sync scans and errors (upload to Firebase)
      await _syncScansToFirebase();
      await _syncErrorsToFirebase();
      
      _updateStatus(lastSyncTime: DateTime.now());
      debugPrint('🔄 SYNC: Sync completed successfully');
    } catch (e) {
      debugPrint('🔄 SYNC: Error during sync: $e');
    } finally {
      _isSyncing = false;
      _updateStatus(isSyncing: false);
    }
  }
  
  Future<void> _syncEventsFromFirebase() async {
    try {
      debugPrint('🔄 SYNC: Fetching events from Firebase');
      final events = await _firebaseService.getEvents();
      
      for (final event in events) {
        await _databaseService.insertEvent(event);
      }
      
      debugPrint('🔄 SYNC: Synced ${events.length} events to local database');
    } catch (e) {
      debugPrint('🔄 SYNC: Error syncing events: $e');
    }
  }
  
  Future<void> _syncStudentsFromFirebase() async {
    try {
      debugPrint('🔄 SYNC: Fetching students from Firebase');
      final students = await _firebaseService.getStudents();
      
      for (final student in students) {
        await _databaseService.insertStudent(student);
      }
      
      debugPrint('🔄 SYNC: Synced ${students.length} students to local database');
    } catch (e) {
      debugPrint('🔄 SYNC: Error syncing students: $e');
    }
  }
  
  Future<void> _syncScansToFirebase() async {
    try {
      final unsyncedScans = await _databaseService.getUnsyncedScans();
      final pendingCount = unsyncedScans.length;
      
      _updateStatus(pendingScans: pendingCount);
      
      if (pendingCount == 0) {
        debugPrint('🔄 SYNC: No unsynced scans to upload');
        return;
      }
      
      debugPrint('🔄 SYNC: Found $pendingCount unsynced scans to upload');
      
      for (final scan in unsyncedScans) {
        try {
          // Upload to Firebase
          await _firebaseService.addScanRecord(scan);
          
          // Mark as synced in local database
          await _databaseService.markScanAsSynced(scan.id);
          
          debugPrint('🔄 SYNC: Successfully synced scan ${scan.id}');
        } catch (e) {
          debugPrint('🔄 SYNC: Error syncing scan ${scan.id}: $e');
        }
      }
      
      // Update pending count
      final remainingUnsynced = await _databaseService.getUnsyncedScans();
      _updateStatus(pendingScans: remainingUnsynced.length);
      
    } catch (e) {
      debugPrint('🔄 SYNC: Error syncing scans: $e');
    }
  }
  
  Future<void> _syncErrorsToFirebase() async {
    try {
      // For now, we'll just count errors as they are synced immediately
      // In the future, we can implement offline error storage
      _updateStatus(pendingErrors: 0);
    } catch (e) {
      debugPrint('🔄 SYNC: Error syncing errors: $e');
    }
  }
  
  Future<void> forceSyncNow() async {
    debugPrint('🔄 SYNC: Force sync requested');
    await _checkConnectivity();
    if (_isOnline) {
      await syncAll();
    } else {
      debugPrint('🔄 SYNC: Cannot force sync - device is offline');
    }
  }
  
  void dispose() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
    _syncStatusController.close();
    _databaseService.close();
  }
}

class SyncStatus {
  final bool isOnline;
  final bool isSyncing;
  final int pendingScans;
  final int pendingErrors;
  final DateTime? lastSyncTime;
  
  SyncStatus({
    required this.isOnline,
    required this.isSyncing,
    required this.pendingScans,
    required this.pendingErrors,
    this.lastSyncTime,
  });
  
  bool get hasPendingData => pendingScans > 0 || pendingErrors > 0;
}