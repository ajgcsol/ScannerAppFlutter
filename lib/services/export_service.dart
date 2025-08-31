import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import '../models/event.dart';
import '../models/scan_record.dart';
import '../models/student.dart';

class ExportService {
  static ExportService? _instance;
  static ExportService get instance => _instance ??= ExportService._();

  ExportService._();

  /// Export event data in the specified format
  Future<String?> exportEventData({
    required Event event,
    required List<ScanRecord> scanRecords,
    required List<Student> students,
    ExportFormat format = ExportFormat.textDelimited,
  }) async {
    try {
      switch (format) {
        case ExportFormat.csv:
          return await _exportToCsv(event, scanRecords, students);
        case ExportFormat.xlsx:
          return await _exportToExcel(event, scanRecords, students);
        case ExportFormat.textDelimited:
          return await _exportToTextDelimited(event, scanRecords, students);
        case ExportFormat.fixedWidth:
          return await _exportToFixedWidth(event, scanRecords, students);
      }
    } catch (e) {
      debugPrint('Export failed: $e');
      return null;
    }
  }

  /// Share exported file
  Future<void> shareExportedFile(String filePath, String eventName) async {
    try {
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Event data export for: $eventName',
        subject: 'Event Export - $eventName',
      );
    } catch (e) {
      debugPrint('Share failed: $e');
    }
  }

  /// Export to CSV format
  Future<String> _exportToCsv(
    Event event,
    List<ScanRecord> scanRecords,
    List<Student> students,
  ) async {
    final List<List<String>> csvData = [];

    // Header row
    csvData.add([
      'Event ID',
      'Event Name',
      'Event Number',
      'Student ID',
      'First Name',
      'Last Name',
      'Email',
      'Scan Time',
      'Status',
    ]);

    // Create student lookup map
    final studentMap = {for (var s in students) s.studentId: s};

    // Data rows
    for (final scan in scanRecords) {
      final student = studentMap[scan.studentId];
      csvData.add([
        event.id,
        event.name,
        event.eventNumber.toString(),
        scan.studentId ?? 'Unknown',
        student?.firstName ?? 'Unknown',
        student?.lastName ?? 'Unknown',
        student?.email ?? 'Unknown',
        scan.timestamp.toIso8601String(),
        scan.synced ? 'Synced' : 'Local',
      ]);
    }

    // Convert to CSV string
    final csvString = const ListToCsvConverter().convert(csvData);

    // Save to file
    final directory = await _getExportDirectory();
    final fileName = '${event.exportFilename}.csv';
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(csvString);

    debugPrint('CSV export saved: ${file.path}');
    return file.path;
  }

  /// Export to Excel format
  Future<String> _exportToExcel(
    Event event,
    List<ScanRecord> scanRecords,
    List<Student> students,
  ) async {
    final excel = Excel.createExcel();
    final sheet = excel['Event_${event.eventNumber}'];

    // Create student lookup map
    final studentMap = {for (var s in students) s.studentId: s};

    // Header row
    final headers = [
      'Event ID',
      'Event Name',
      'Event Number',
      'Student ID',
      'First Name',
      'Last Name',
      'Email',
      'Scan Time',
      'Status',
    ];

    for (int i = 0; i < headers.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(headers[i]);
    }

    // Data rows
    for (int i = 0; i < scanRecords.length; i++) {
      final scan = scanRecords[i];
      final student = studentMap[scan.studentId];
      final rowIndex = i + 1;

      final rowData = [
        event.id,
        event.name,
        event.eventNumber.toString(),
        scan.studentId ?? 'Unknown',
        student?.firstName ?? 'Unknown',
        student?.lastName ?? 'Unknown',
        student?.email ?? 'Unknown',
        scan.timestamp.toIso8601String(),
        scan.synced ? 'Synced' : 'Local',
      ];

      for (int j = 0; j < rowData.length; j++) {
        sheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: j, rowIndex: rowIndex))
            .value = TextCellValue(rowData[j]);
      }
    }

    // Save to file
    final directory = await _getExportDirectory();
    final fileName = '${event.exportFilename}.xlsx';
    final file = File('${directory.path}/$fileName');
    final bytes = excel.encode();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    }

    debugPrint('Excel export saved: ${file.path}');
    return file.path;
  }

  /// Export to text delimited format (pipe-separated)
  Future<String> _exportToTextDelimited(
    Event event,
    List<ScanRecord> scanRecords,
    List<Student> students,
  ) async {
    final buffer = StringBuffer();

    // Create student lookup map
    final studentMap = {for (var s in students) s.studentId: s};

    // Header
    buffer.writeln(
        'Event_ID|Event_Name|Event_Number|Student_ID|First_Name|Last_Name|Email|Scan_Time|Status');

    // Data rows
    for (final scan in scanRecords) {
      final student = studentMap[scan.studentId];
      buffer.writeln([
        event.id,
        event.name,
        event.eventNumber.toString(),
        scan.studentId ?? 'Unknown',
        student?.firstName ?? 'Unknown',
        student?.lastName ?? 'Unknown',
        student?.email ?? 'Unknown',
        scan.timestamp.toIso8601String(),
        scan.synced ? 'Synced' : 'Local',
      ].join('|'));
    }

    // Save to file
    final directory = await _getExportDirectory();
    final fileName = '${event.exportFilename}.txt';
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(buffer.toString());

    debugPrint('Text delimited export saved: ${file.path}');
    return file.path;
  }

  /// Export to fixed width format
  Future<String> _exportToFixedWidth(
    Event event,
    List<ScanRecord> scanRecords,
    List<Student> students,
  ) async {
    final buffer = StringBuffer();

    // Create student lookup map
    final studentMap = {for (var s in students) s.studentId: s};

    // Header with fixed widths
    buffer.writeln('${'Event_ID'.padRight(20)}'
        '${'Event_Name'.padRight(30)}'
        '${'Event_Number'.padRight(15)}'
        '${'Student_ID'.padRight(15)}'
        '${'First_Name'.padRight(20)}'
        '${'Last_Name'.padRight(20)}'
        '${'Email'.padRight(40)}'
        '${'Scan_Time'.padRight(25)}'
        '${'Status'.padRight(10)}');

    // Separator line
    buffer.writeln('=' * 195);

    // Data rows with fixed widths
    for (final scan in scanRecords) {
      final student = studentMap[scan.studentId];
      buffer.writeln('${event.id.padRight(20)}'
          '${event.name.padRight(30)}'
          '${event.eventNumber.toString().padRight(15)}'
          '${(scan.studentId ?? 'Unknown').padRight(15)}'
          '${(student?.firstName ?? 'Unknown').padRight(20)}'
          '${(student?.lastName ?? 'Unknown').padRight(20)}'
          '${(student?.email ?? 'Unknown').padRight(40)}'
          '${scan.timestamp.toIso8601String().padRight(25)}'
          '${(scan.synced ? 'Synced' : 'Local').padRight(10)}');
    }

    // Save to file
    final directory = await _getExportDirectory();
    final fileName = '${event.exportFilename}.txt';
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(buffer.toString());

    debugPrint('Fixed width export saved: ${file.path}');
    return file.path;
  }

  /// Get export directory
  Future<Directory> _getExportDirectory() async {
    Directory directory;

    if (kIsWeb) {
      // For web, use a temporary directory
      directory = Directory.systemTemp;
    } else {
      // For mobile/desktop, use documents directory
      directory = await getApplicationDocumentsDirectory();
    }

    // Create exports subdirectory
    final exportDir = Directory('${directory.path}/exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    return exportDir;
  }

  /// Get export statistics
  Map<String, dynamic> getExportStats(
    Event event,
    List<ScanRecord> scanRecords,
    List<Student> students,
  ) {
    final studentMap = {for (var s in students) s.studentId: s};
    final knownStudents = scanRecords
        .where((scan) => studentMap.containsKey(scan.studentId))
        .length;
    final unknownStudents = scanRecords.length - knownStudents;
    final syncedScans = scanRecords.where((scan) => scan.synced).length;
    final localScans = scanRecords.length - syncedScans;

    return {
      'eventName': event.name,
      'eventNumber': event.eventNumber,
      'totalScans': scanRecords.length,
      'knownStudents': knownStudents,
      'unknownStudents': unknownStudents,
      'syncedScans': syncedScans,
      'localScans': localScans,
      'exportDate': DateTime.now().toIso8601String(),
    };
  }

  /// Preview export data (first 10 rows)
  List<Map<String, String>> previewExportData(
    Event event,
    List<ScanRecord> scanRecords,
    List<Student> students, {
    int limit = 10,
  }) {
    final studentMap = {for (var s in students) s.studentId: s};
    final preview = <Map<String, String>>[];

    for (int i = 0; i < scanRecords.length && i < limit; i++) {
      final scan = scanRecords[i];
      final student = studentMap[scan.studentId];

      preview.add({
        'Event ID': event.id,
        'Event Name': event.name,
        'Event Number': event.eventNumber.toString(),
        'Student ID': scan.studentId ?? 'Unknown',
        'First Name': student?.firstName ?? 'Unknown',
        'Last Name': student?.lastName ?? 'Unknown',
        'Email': student?.email ?? 'Unknown',
        'Scan Time': scan.timestamp.toIso8601String(),
        'Status': scan.synced ? 'Synced' : 'Local',
      });
    }

    return preview;
  }
}
