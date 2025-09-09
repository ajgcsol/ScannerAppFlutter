class SyncOperation {
  final String id;
  final String eventId;
  final String studentId;
  final SyncOperationType type;
  final DateTime timestamp;
  final String source; // 'local' or 'cloud'
  final bool synced;
  final Map<String, dynamic>? data; // Additional data for add operations

  const SyncOperation({
    required this.id,
    required this.eventId,
    required this.studentId,
    required this.type,
    required this.timestamp,
    required this.source,
    this.synced = false,
    this.data,
  });

  SyncOperation copyWith({
    String? id,
    String? eventId,
    String? studentId,
    SyncOperationType? type,
    DateTime? timestamp,
    String? source,
    bool? synced,
    Map<String, dynamic>? data,
  }) {
    return SyncOperation(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      studentId: studentId ?? this.studentId,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
      synced: synced ?? this.synced,
      data: data ?? this.data,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'eventId': eventId,
      'studentId': studentId,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'source': source,
      'synced': synced,
      'data': data,
    };
  }

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    return SyncOperation(
      id: json['id'],
      eventId: json['eventId'],
      studentId: json['studentId'],
      type: SyncOperationType.values.firstWhere(
        (e) => e.name == json['type'],
      ),
      timestamp: DateTime.parse(json['timestamp']),
      source: json['source'],
      synced: json['synced'] ?? false,
      data: json['data'],
    );
  }
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