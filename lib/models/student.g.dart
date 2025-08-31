// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'student.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Student _$StudentFromJson(Map<String, dynamic> json) => Student(
      studentId: json['studentId'] as String,
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      email: json['email'] as String,
      program: json['program'] as String? ?? '',
      year: json['year'] as String? ?? '',
      active: json['active'] as bool? ?? true,
    );

Map<String, dynamic> _$StudentToJson(Student instance) => <String, dynamic>{
      'studentId': instance.studentId,
      'firstName': instance.firstName,
      'lastName': instance.lastName,
      'email': instance.email,
      'program': instance.program,
      'year': instance.year,
      'active': instance.active,
    };
