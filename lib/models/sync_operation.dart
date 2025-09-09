import 'package:freezed_annotation/freezed_annotation.dart';

part 'sync_operation.freezed.dart';
part 'sync_operation.g.dart';

@freezed
class SyncOperation with _$SyncOperation {
  const factory SyncOperation({
    required String id,
    required String eventId,
    required String studentId,
    required SyncOperationType type,
    required DateTime timestamp,
    required String source, // 'local' or 'cloud'
    @Default(false) bool synced,
    Map<String, dynamic>? data, // Additional data for add operations
  }) = _SyncOperation;

  factory SyncOperation.fromJson(Map<String, dynamic> json) =>
      _$SyncOperationFromJson(json);
}

enum SyncOperationType {
  add,
  delete,
}

// Extension for easier creation
extension SyncOperationExtension on SyncOperation {
  /// Create a local add operation for a new scan
  static SyncOperation localAdd({
    required String eventId,
    required String studentId,
    required DateTime timestamp,
    Map<String, dynamic>? scanData,
  }) {
    return SyncOperation(
      id: '${eventId}_${studentId}_${timestamp.millisecondsSinceEpoch}',
      eventId: eventId,
      studentId: studentId,
      type: SyncOperationType.add,
      timestamp: timestamp,
      source: 'local',
      data: scanData,
    );
  }

  /// Create a cloud delete operation from admin portal
  static SyncOperation cloudDelete({
    required String eventId,
    required String studentId,
    required DateTime timestamp,
  }) {
    return SyncOperation(
      id: '${eventId}_${studentId}_delete_${timestamp.millisecondsSinceEpoch}',
      eventId: eventId,
      studentId: studentId,
      type: SyncOperationType.delete,
      timestamp: timestamp,
      source: 'cloud',
    );
  }
}