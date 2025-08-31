// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Event _$EventFromJson(Map<String, dynamic> json) => Event(
      id: json['id'] as String,
      eventNumber: (json['eventNumber'] as num).toInt(),
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      date: DateTime.parse(json['date'] as String),
      location: json['location'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? true,
      isCompleted: json['isCompleted'] as bool? ?? false,
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      createdBy: json['createdBy'] as String? ?? '',
      customColumns: (json['customColumns'] as List<dynamic>?)
              ?.map((e) => EventColumn.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      staticValues: (json['staticValues'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          const {},
      exportFormat:
          $enumDecodeNullable(_$ExportFormatEnumMap, json['exportFormat']) ??
              ExportFormat.textDelimited,
    );

Map<String, dynamic> _$EventToJson(Event instance) => <String, dynamic>{
      'id': instance.id,
      'eventNumber': instance.eventNumber,
      'name': instance.name,
      'description': instance.description,
      'date': instance.date.toIso8601String(),
      'location': instance.location,
      'isActive': instance.isActive,
      'isCompleted': instance.isCompleted,
      'completedAt': instance.completedAt?.toIso8601String(),
      'createdAt': instance.createdAt.toIso8601String(),
      'createdBy': instance.createdBy,
      'customColumns': instance.customColumns,
      'staticValues': instance.staticValues,
      'exportFormat': _$ExportFormatEnumMap[instance.exportFormat]!,
    };

const _$ExportFormatEnumMap = {
  ExportFormat.csv: 'CSV',
  ExportFormat.fixedWidth: 'FIXED_WIDTH',
  ExportFormat.xlsx: 'XLSX',
  ExportFormat.textDelimited: 'TEXT_DELIMITED',
};

EventColumn _$EventColumnFromJson(Map<String, dynamic> json) => EventColumn(
      id: json['id'] as String,
      name: json['name'] as String,
      displayName: json['displayName'] as String,
      dataType: $enumDecode(_$ColumnDataTypeEnumMap, json['dataType']),
      maxLength: (json['maxLength'] as num?)?.toInt() ?? 50,
      isRequired: json['isRequired'] as bool? ?? false,
      defaultValue: json['defaultValue'] as String? ?? '',
      order: (json['order'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$EventColumnToJson(EventColumn instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'displayName': instance.displayName,
      'dataType': _$ColumnDataTypeEnumMap[instance.dataType]!,
      'maxLength': instance.maxLength,
      'isRequired': instance.isRequired,
      'defaultValue': instance.defaultValue,
      'order': instance.order,
    };

const _$ColumnDataTypeEnumMap = {
  ColumnDataType.text: 'TEXT',
  ColumnDataType.number: 'NUMBER',
  ColumnDataType.datetime: 'DATETIME',
  ColumnDataType.boolean: 'BOOLEAN',
  ColumnDataType.custom: 'CUSTOM',
};

EventAttendee _$EventAttendeeFromJson(Map<String, dynamic> json) =>
    EventAttendee(
      id: json['id'] as String,
      eventId: json['eventId'] as String,
      studentId: json['studentId'] as String,
      student: json['student'] == null
          ? null
          : Student.fromJson(json['student'] as Map<String, dynamic>),
      scannedAt: DateTime.parse(json['scannedAt'] as String),
      deviceId: json['deviceId'] as String,
      customFieldValues:
          (json['customFieldValues'] as Map<String, dynamic>?)?.map(
                (k, e) => MapEntry(k, e as String),
              ) ??
              const {},
      uniqueEventValue: json['uniqueEventValue'] as String,
      verified: json['verified'] as bool? ?? false,
    );

Map<String, dynamic> _$EventAttendeeToJson(EventAttendee instance) =>
    <String, dynamic>{
      'id': instance.id,
      'eventId': instance.eventId,
      'studentId': instance.studentId,
      'student': instance.student,
      'scannedAt': instance.scannedAt.toIso8601String(),
      'deviceId': instance.deviceId,
      'customFieldValues': instance.customFieldValues,
      'uniqueEventValue': instance.uniqueEventValue,
      'verified': instance.verified,
    };
