import 'package:json_annotation/json_annotation.dart';
import 'student.dart';

part 'event.g.dart';

@JsonSerializable()
class Event {
  final String id;
  final int eventNumber;
  final String name;
  final String description;
  final DateTime date;
  final String location;
  final bool isActive;
  final bool isCompleted;
  final DateTime? completedAt;
  final DateTime createdAt;
  final String createdBy;
  final List<EventColumn> customColumns;
  final Map<String, String> staticValues;
  final ExportFormat exportFormat;

  const Event({
    required this.id,
    required this.eventNumber,
    required this.name,
    this.description = '',
    required this.date,
    this.location = '',
    this.isActive = true,
    this.isCompleted = false,
    this.completedAt,
    required this.createdAt,
    this.createdBy = '',
    this.customColumns = const [],
    this.staticValues = const {},
    this.exportFormat = ExportFormat.textDelimited,
  });

  factory Event.fromJson(Map<String, dynamic> json) => _$EventFromJson(json);
  Map<String, dynamic> toJson() => _$EventToJson(this);

  String get formattedDate {
    return '${_monthName(date.month)} ${date.day}, ${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String get shortDate {
    return '${_monthName(date.month)} ${date.day}';
  }

  EventStatus get status {
    if (isCompleted) return EventStatus.completed;
    if (isActive) return EventStatus.active;
    return EventStatus.inactive;
  }

  String get exportFilename {
    final now = DateTime.now();
    final dateString = '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.year.toString().substring(2)}';
    return 'Event_${eventNumber}_$dateString.txt';
  }

  static String _monthName(int month) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month];
  }

  factory Event.createNew({
    required int eventNumber,
    required String name,
    String description = '',
    DateTime? date,
    String location = '',
  }) {
    return Event(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      eventNumber: eventNumber,
      name: name,
      description: description,
      date: date ?? DateTime.now(),
      location: location,
      createdAt: DateTime.now(),
    );
  }

  Event copyWith({
    String? id,
    int? eventNumber,
    String? name,
    String? description,
    DateTime? date,
    String? location,
    bool? isActive,
    bool? isCompleted,
    DateTime? completedAt,
    DateTime? createdAt,
    String? createdBy,
    List<EventColumn>? customColumns,
    Map<String, String>? staticValues,
    ExportFormat? exportFormat,
  }) {
    return Event(
      id: id ?? this.id,
      eventNumber: eventNumber ?? this.eventNumber,
      name: name ?? this.name,
      description: description ?? this.description,
      date: date ?? this.date,
      location: location ?? this.location,
      isActive: isActive ?? this.isActive,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      customColumns: customColumns ?? this.customColumns,
      staticValues: staticValues ?? this.staticValues,
      exportFormat: exportFormat ?? this.exportFormat,
    );
  }
}

@JsonSerializable()
class EventColumn {
  final String id;
  final String name;
  final String displayName;
  final ColumnDataType dataType;
  final int maxLength;
  final bool isRequired;
  final String defaultValue;
  final int order;

  const EventColumn({
    required this.id,
    required this.name,
    required this.displayName,
    required this.dataType,
    this.maxLength = 50,
    this.isRequired = false,
    this.defaultValue = '',
    this.order = 0,
  });

  factory EventColumn.fromJson(Map<String, dynamic> json) => _$EventColumnFromJson(json);
  Map<String, dynamic> toJson() => _$EventColumnToJson(this);

  static List<EventColumn> standardColumns() {
    return [
      const EventColumn(
        id: 'student_id',
        name: 'student_id',
        displayName: 'Student ID',
        dataType: ColumnDataType.text,
        maxLength: 20,
        isRequired: true,
        order: 0,
      ),
      const EventColumn(
        id: 'first_name',
        name: 'first_name',
        displayName: 'First Name',
        dataType: ColumnDataType.text,
        maxLength: 30,
        isRequired: true,
        order: 1,
      ),
      const EventColumn(
        id: 'last_name',
        name: 'last_name',
        displayName: 'Last Name',
        dataType: ColumnDataType.text,
        maxLength: 30,
        isRequired: true,
        order: 2,
      ),
      const EventColumn(
        id: 'email',
        name: 'email',
        displayName: 'Email',
        dataType: ColumnDataType.text,
        maxLength: 50,
        isRequired: false,
        order: 3,
      ),
      const EventColumn(
        id: 'scan_timestamp',
        name: 'scan_timestamp',
        displayName: 'Scan Time',
        dataType: ColumnDataType.datetime,
        maxLength: 19,
        isRequired: true,
        order: 4,
      ),
    ];
  }
}

@JsonSerializable()
class EventAttendee {
  final String id;
  final String eventId;
  final String studentId;
  final Student? student;
  final DateTime scannedAt;
  final String deviceId;
  final Map<String, String> customFieldValues;
  final String uniqueEventValue;
  final bool verified;

  const EventAttendee({
    required this.id,
    required this.eventId,
    required this.studentId,
    this.student,
    required this.scannedAt,
    required this.deviceId,
    this.customFieldValues = const {},
    required this.uniqueEventValue,
    this.verified = false,
  });

  factory EventAttendee.fromJson(Map<String, dynamic> json) => _$EventAttendeeFromJson(json);
  Map<String, dynamic> toJson() => _$EventAttendeeToJson(this);

  String get formattedScanTime {
    return '${scannedAt.year}-${scannedAt.month.toString().padLeft(2, '0')}-${scannedAt.day.toString().padLeft(2, '0')} ${scannedAt.hour.toString().padLeft(2, '0')}:${scannedAt.minute.toString().padLeft(2, '0')}:${scannedAt.second.toString().padLeft(2, '0')}';
  }

  factory EventAttendee.create({
    required String eventId,
    required String studentId,
    Student? student,
    required String deviceId,
    Map<String, String> customValues = const {},
  }) {
    return EventAttendee(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      eventId: eventId,
      studentId: studentId,
      student: student,
      scannedAt: DateTime.now(),
      deviceId: deviceId,
      customFieldValues: customValues,
      uniqueEventValue: _generateUniqueValue(),
      verified: student != null,
    );
  }

  static String _generateUniqueValue() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    return List.generate(8, (index) => chars[(random + index) % chars.length]).join();
  }
}

enum ColumnDataType {
  @JsonValue('TEXT')
  text,
  @JsonValue('NUMBER')
  number,
  @JsonValue('DATETIME')
  datetime,
  @JsonValue('BOOLEAN')
  boolean,
  @JsonValue('CUSTOM')
  custom,
}

enum ExportFormat {
  @JsonValue('CSV')
  csv,
  @JsonValue('FIXED_WIDTH')
  fixedWidth,
  @JsonValue('XLSX')
  xlsx,
  @JsonValue('TEXT_DELIMITED')
  textDelimited,
}

enum EventStatus {
  @JsonValue('ACTIVE')
  active,
  @JsonValue('INACTIVE')
  inactive,
  @JsonValue('COMPLETED')
  completed,
}
