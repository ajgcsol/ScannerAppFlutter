// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'error_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ErrorRecord _$ErrorRecordFromJson(Map<String, dynamic> json) => ErrorRecord(
      id: json['id'] as String,
      scannedId: json['scannedId'] as String,
      studentEmail: json['studentEmail'] as String,
      eventId: json['eventId'] as String,
      eventName: json['eventName'] as String,
      eventDate: json['eventDate'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      resolved: json['resolved'] as bool? ?? false,
    );

Map<String, dynamic> _$ErrorRecordToJson(ErrorRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'scannedId': instance.scannedId,
      'studentEmail': instance.studentEmail,
      'eventId': instance.eventId,
      'eventName': instance.eventName,
      'eventDate': instance.eventDate,
      'timestamp': instance.timestamp.toIso8601String(),
      'resolved': instance.resolved,
    };
