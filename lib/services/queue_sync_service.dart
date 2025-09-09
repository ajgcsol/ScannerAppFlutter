import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/sync_operation.dart';
import '../models/scan.dart';
import '../models/scan_record.dart';
import 'database_service.dart';
import 'firebase_service.dart';

/// Advanced sync service with add/delete queues and timestamp-based conflict resolution
class QueueSyncService {
  static final QueueSyncService _instance = QueueSyncService._internal();
  factory QueueSyncService() => _instance;
  QueueSyncService._internal();

  final DatabaseService _databaseService = DatabaseService();
  final FirebaseService _firebaseService = FirebaseService.instance;
  
  final List<SyncOperation> _localAddQueue = [];
  final List<SyncOperation> _cloudDeleteQueue = [];
  
  Timer? _syncTimer;
  bool _isSyncing = false;
  
  /// Initialize the sync service
  Future<void> initialize() async {
    debugPrint('🔄 QueueSync: Initializing queue-based sync service');
    
    // Load pending operations from database
    await _loadPendingOperations();
    
    // Start periodic sync
    _startPeriodicSync();
  }

  /// Add a scan to local queue (when scanning offline/online)
  Future<void> queueLocalAdd({
    required String eventId,
    required String studentId,
    required DateTime timestamp,
    required Map<String, dynamic> scanData,
  }) async {
    debugPrint('🔄 QueueSync: Queuing local add for $studentId in event $eventId');
    
    final operation = SyncOperationExtension.localAdd(
      eventId: eventId,
      studentId: studentId,
      timestamp: timestamp,
      scanData: scanData,
    );
    
    _localAddQueue.add(operation);
    
    // Persist to database
    await _savePendingOperation(operation);
    
    // Try immediate sync if online
    if (!_isSyncing) {
      _triggerSync();
    }
  }

  /// Get resolved scans for an event (applies queue operations)
  Future<List<Scan>> getResolvedScansForEvent(String eventId) async {
    debugPrint('🔄 QueueSync: Getting resolved scans for event $eventId');
    
    // Get base scans from Firebase
    List<ScanRecord> firebaseScans = [];
    try {
      firebaseScans = await _firebaseService.getScanRecordsOnce(eventId: eventId);
      debugPrint('🔄 QueueSync: Got ${firebaseScans.length} scans from Firebase');
    } catch (e) {
      debugPrint('🔄 QueueSync: Failed to get Firebase scans: $e');
    }
    
    // Get pending local adds for this event
    final localAdds = _localAddQueue
        .where((op) => op.eventId == eventId && op.type == SyncOperationType.add)
        .toList();
    
    // Get pending cloud deletes for this event  
    final cloudDeletes = _cloudDeleteQueue
        .where((op) => op.eventId == eventId && op.type == SyncOperationType.delete)
        .toList();
    
    debugPrint('🔄 QueueSync: Applying ${localAdds.length} local adds and ${cloudDeletes.length} cloud deletes');
    
    // Create a map of final scans with timestamp-based resolution
    final Map<String, ScanRecord> finalScans = {};
    
    // Start with Firebase scans
    for (final scan in firebaseScans) {
      finalScans[scan.studentId] = scan;
    }
    
    // Apply local adds (if timestamp is newer or scan doesn't exist)
    for (final addOp in localAdds) {
      final existing = finalScans[addOp.studentId];
      
      if (existing == null || addOp.timestamp.isAfter(existing.timestamp)) {
        // Add the local scan
        finalScans[addOp.studentId] = ScanRecord(
          id: addOp.id,
          code: addOp.studentId,
          studentId: addOp.studentId,
          timestamp: addOp.timestamp,
          listId: addOp.eventId,
          eventId: addOp.eventId,
          deviceId: addOp.data?['deviceId'] ?? '',
          symbology: addOp.data?['symbology'] ?? '',
          synced: false,
        );
        debugPrint('🔄 QueueSync: Applied local add for ${addOp.studentId}');
      } else {
        debugPrint('🔄 QueueSync: Skipped local add for ${addOp.studentId} (older timestamp)');
      }
    }
    
    // Apply cloud deletes (remove if delete timestamp is newer than scan timestamp)
    for (final deleteOp in cloudDeletes) {
      final existing = finalScans[deleteOp.studentId];
      
      if (existing != null && deleteOp.timestamp.isAfter(existing.timestamp)) {
        finalScans.remove(deleteOp.studentId);
        debugPrint('🔄 QueueSync: Applied cloud delete for ${deleteOp.studentId}');
      } else {
        debugPrint('🔄 QueueSync: Skipped cloud delete for ${deleteOp.studentId} (older timestamp or not found)');
      }
    }
    
    // Convert to Scan objects
    final scans = finalScans.values.map((record) => Scan(
      studentId: record.studentId,
      timestamp: record.timestamp,
      studentName: '', // Will be enriched later
      studentEmail: '',
    )).toList();
    
    // Sort by timestamp descending
    scans.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    debugPrint('🔄 QueueSync: Resolved to ${scans.length} final scans');
    return scans;
  }

  /// Detect and queue cloud deletes by comparing current vs previous Firebase state
  Future<void> detectCloudDeletes(String eventId, List<ScanRecord> currentFirebaseScans) async {
    debugPrint('🔄 QueueSync: Detecting cloud deletes for event $eventId');
    
    // Get previous Firebase state from local cache/database
    final previousScans = await _databaseService.getScansForEvent(eventId);
    final previousIds = previousScans.map((s) => s.studentId).toSet();
    final currentIds = currentFirebaseScans.map((s) => s.studentId).toSet();
    
    // Find deleted IDs
    final deletedIds = previousIds.difference(currentIds);
    
    if (deletedIds.isNotEmpty) {
      debugPrint('🔄 QueueSync: Detected ${deletedIds.length} cloud deletes: $deletedIds');
      
      for (final deletedId in deletedIds) {
        final deleteOp = SyncOperationExtension.cloudDelete(
          eventId: eventId,
          studentId: deletedId,
          timestamp: DateTime.now(), // Use current time as delete timestamp
        );
        
        _cloudDeleteQueue.add(deleteOp);
        await _savePendingOperation(deleteOp);
      }
    }
  }

  /// Trigger immediate sync attempt
  void _triggerSync() {
    if (_isSyncing) return;
    
    Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      timer.cancel();
      await _performSync();
    });
  }

  /// Perform the actual sync operations
  Future<void> _performSync() async {
    if (_isSyncing) return;
    
    _isSyncing = true;
    debugPrint('🔄 QueueSync: Starting sync process');
    
    try {
      // Sync local adds to Firebase
      await _syncLocalAdds();
      
      // Clean up completed operations
      await _cleanupCompletedOperations();
      
    } catch (e) {
      debugPrint('🔄 QueueSync: Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync pending local adds to Firebase
  Future<void> _syncLocalAdds() async {
    final pendingAdds = _localAddQueue.where((op) => !op.synced).toList();
    
    if (pendingAdds.isEmpty) {
      debugPrint('🔄 QueueSync: No pending local adds to sync');
      return;
    }
    
    debugPrint('🔄 QueueSync: Syncing ${pendingAdds.length} local adds to Firebase');
    
    for (final addOp in pendingAdds) {
      try {
        // Create scan record from operation
        final scanRecord = ScanRecord(
          id: addOp.id,
          code: addOp.studentId,
          studentId: addOp.studentId,
          timestamp: addOp.timestamp,
          listId: addOp.eventId,
          eventId: addOp.eventId,
          deviceId: addOp.data?['deviceId'] ?? '',
          symbology: addOp.data?['symbology'] ?? '',
          synced: false,
        );
        
        // Upload to Firebase
        await _firebaseService.saveScanRecord(scanRecord);
        
        // Mark as synced
        final syncedOp = addOp.copyWith(synced: true);
        final index = _localAddQueue.indexOf(addOp);
        if (index != -1) {
          _localAddQueue[index] = syncedOp;
        }
        
        await _updatePendingOperation(syncedOp);
        
        debugPrint('🔄 QueueSync: Synced local add for ${addOp.studentId}');
        
      } catch (e) {
        debugPrint('🔄 QueueSync: Failed to sync add for ${addOp.studentId}: $e');
      }
    }
  }

  /// Load pending operations from database on startup
  Future<void> _loadPendingOperations() async {
    // Implementation would load from a sync_operations table
    debugPrint('🔄 QueueSync: Loading pending operations from database');
    // TODO: Implement database loading
  }

  /// Save a pending operation to database
  Future<void> _savePendingOperation(SyncOperation operation) async {
    debugPrint('🔄 QueueSync: Saving pending operation: ${operation.id}');
    // TODO: Implement database saving
  }

  /// Update a pending operation in database
  Future<void> _updatePendingOperation(SyncOperation operation) async {
    debugPrint('🔄 QueueSync: Updating pending operation: ${operation.id}');
    // TODO: Implement database updating
  }

  /// Clean up completed operations from queues and database
  Future<void> _cleanupCompletedOperations() async {
    debugPrint('🔄 QueueSync: Cleaning up completed operations');
    
    // Remove synced local adds
    _localAddQueue.removeWhere((op) => op.synced);
    
    // Remove old cloud deletes (older than 24 hours)
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    _cloudDeleteQueue.removeWhere((op) => op.timestamp.isBefore(cutoff));
    
    // TODO: Clean up database
  }

  /// Start periodic sync timer
  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!_isSyncing) {
        _performSync();
      }
    });
  }

  /// Dispose resources
  void dispose() {
    _syncTimer?.cancel();
  }
}