// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scan_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ScanRecord _$ScanRecordFromJson(Map<String, dynamic> json) => ScanRecord(
      id: json['id'] as String,
      code: json['code'] as String,
      symbology: json['symbology'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      eventId: json['eventId'] as String?,
      studentId: json['studentId'] as String?,
      deviceId: json['deviceId'] as String? ?? '',
      processed: json['processed'] as bool? ?? false,
      synced: json['synced'] as bool? ?? false,
      metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
    );

Map<String, dynamic> _$ScanRecordToJson(ScanRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'code': instance.code,
      'symbology': instance.symbology,
      'timestamp': instance.timestamp.toIso8601String(),
      'eventId': instance.eventId,
      'studentId': instance.studentId,
      'deviceId': instance.deviceId,
      'processed': instance.processed,
      'synced': instance.synced,
      'metadata': instance.metadata,
    };

ErrorRecord _$ErrorRecordFromJson(Map<String, dynamic> json) => ErrorRecord(
      id: json['id'] as String,
      scannedId: json['scannedId'] as String,
      studentEmail: json['studentEmail'] as String,
      eventId: json['eventId'] as String,
      eventName: json['eventName'] as String,
      eventDate: json['eventDate'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      resolved: json['resolved'] as bool? ?? false,
      synced: json['synced'] as bool? ?? false,
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
      'synced': instance.synced,
    };
