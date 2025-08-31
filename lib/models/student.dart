import 'package:json_annotation/json_annotation.dart';

part 'student.g.dart';

@JsonSerializable()
class Student {
  final String studentId;
  final String firstName;
  final String lastName;
  final String email;
  final String program;
  final String year;
  final bool active;

  const Student({
    required this.studentId,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.program = '',
    this.year = '',
    this.active = true,
  });

  factory Student.fromJson(Map<String, dynamic> json) => _$StudentFromJson(json);
  Map<String, dynamic> toJson() => _$StudentToJson(this);

  String get fullName => '$firstName $lastName';

  String get displayInfo {
    final buffer = StringBuffer('$firstName $lastName');
    if (program.isNotEmpty) {
      buffer.write(' • $program');
    }
    if (year.isNotEmpty) {
      buffer.write(' • Year $year');
    }
    return buffer.toString();
  }

  factory Student.empty() {
    return const Student(
      studentId: '',
      firstName: '',
      lastName: '',
      email: '',
      program: '',
      year: '',
      active: false,
    );
  }

  Student copyWith({
    String? studentId,
    String? firstName,
    String? lastName,
    String? email,
    String? program,
    String? year,
    bool? active,
  }) {
    return Student(
      studentId: studentId ?? this.studentId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      program: program ?? this.program,
      year: year ?? this.year,
      active: active ?? this.active,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Student && other.studentId == studentId;
  }

  @override
  int get hashCode => studentId.hashCode;

  @override
  String toString() {
    return 'Student(studentId: $studentId, fullName: $fullName, email: $email)';
  }
}
