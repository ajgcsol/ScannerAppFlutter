import 'package:json_annotation/json_annotation.dart';

part 'error_record.g.dart';

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

  const ErrorRecord({
    required this.id,
    required this.scannedId,
    required this.studentEmail,
    required this.eventId,
    required this.eventName,
    required this.eventDate,
    required this.timestamp,
    this.resolved = false,
  });

  factory ErrorRecord.fromJson(Map<String, dynamic> json) =>
      _$ErrorRecordFromJson(json);

  Map<String, dynamic> toJson() => _$ErrorRecordToJson(this);

  ErrorRecord copyWith({
    String? id,
    String? scannedId,
    String? studentEmail,
    String? eventId,
    String? eventName,
    String? eventDate,
    DateTime? timestamp,
    bool? resolved,
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
    );
  }

  static ErrorRecord create({
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
}
