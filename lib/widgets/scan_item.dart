import 'package:flutter/material.dart';
import '../models/scan.dart';

class ScanItem extends StatelessWidget {
  final Scan scan;

  const ScanItem({
    super.key,
    required this.scan,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(scan.studentId),
        subtitle: Text(scan.timestamp.toIso8601String()),
      ),
    );
  }
}
