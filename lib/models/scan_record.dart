import 'package:json_annotation/json_annotation.dart';

part 'scan_record.g.dart';

@JsonSerializable()
class ScanRecord {
  final String id;
  final String code;
  final String? symbology;
  final DateTime timestamp;
  final String? eventId;
  final String? studentId;
  final String deviceId;
  final bool processed;
  final bool synced;
  final Map<String, dynamic> metadata;

  const ScanRecord({
    required this.id,
    required this.code,
    this.symbology,
    required this.timestamp,
    this.eventId,
    this.studentId,
    this.deviceId = '',
    this.processed = false,
    this.synced = false,
    this.metadata = const {},
  });

  factory ScanRecord.fromJson(Map<String, dynamic> json) => _$ScanRecordFromJson(json);
  Map<String, dynamic> toJson() => _$ScanRecordToJson(this);

  factory ScanRecord.create({
    required String code,
    String? symbology,
    String? eventId,
    String? studentId,
    Map<String, dynamic> metadata = const {},
  }) {
    return ScanRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      code: code,
      symbology: symbology,
      timestamp: DateTime.now(),
      eventId: eventId,
      studentId: studentId,
      metadata: metadata,
    );
  }

  String get formattedTimestamp {
    return '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  String get shortTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  ScanRecord copyWith({
    String? id,
    String? code,
    String? symbology,
    DateTime? timestamp,
    String? eventId,
    String? studentId,
    String? deviceId,
    bool? processed,
    bool? synced,
    Map<String, dynamic>? metadata,
  }) {
    return ScanRecord(
      id: id ?? this.id,
      code: code ?? this.code,
      symbology: symbology ?? this.symbology,
      timestamp: timestamp ?? this.timestamp,
      eventId: eventId ?? this.eventId,
      studentId: studentId ?? this.studentId,
      deviceId: deviceId ?? this.deviceId,
      processed: processed ?? this.processed,
      synced: synced ?? this.synced,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScanRecord && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ScanRecord(id: $id, code: $code, symbology: $symbology, timestamp: $formattedTimestamp)';
  }
}

@JsonSerializable()
class ErrorRecord {
  final String id;
  final String scannedId;
  final String studentEmail;
  final String eventId;
  final String eventName;
  final String eventDate;
  final DateTime timestamp;
  final bool resolved;
  final bool synced;

  const ErrorRecord({
    required this.id,
    required this.scannedId,
    required this.studentEmail,
    required this.eventId,
    required this.eventName,
    required this.eventDate,
    required this.timestamp,
    this.resolved = false,
    this.synced = false,
  });

  factory ErrorRecord.fromJson(Map<String, dynamic> json) => _$ErrorRecordFromJson(json);
  Map<String, dynamic> toJson() => _$ErrorRecordToJson(this);

  factory ErrorRecord.create({
    required String scannedId,
    required String studentEmail,
    required String eventId,
    required String eventName,
    required String eventDate,
  }) {
    return ErrorRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      scannedId: scannedId,
      studentEmail: studentEmail,
      eventId: eventId,
      eventName: eventName,
      eventDate: eventDate,
      timestamp: DateTime.now(),
    );
  }

  ErrorRecord copyWith({
    String? id,
    String? scannedId,
    String? studentEmail,
    String? eventId,
    String? eventName,
    String? eventDate,
    DateTime? timestamp,
    bool? resolved,
    bool? synced,
  }) {
    return ErrorRecord(
      id: id ?? this.id,
      scannedId: scannedId ?? this.scannedId,
      studentEmail: studentEmail ?? this.studentEmail,
      eventId: eventId ?? this.eventId,
      eventName: eventName ?? this.eventName,
      eventDate: eventDate ?? this.eventDate,
      timestamp: timestamp ?? this.timestamp,
      resolved: resolved ?? this.resolved,
      synced: synced ?? this.synced,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ErrorRecord && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
