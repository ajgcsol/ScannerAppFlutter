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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          child: Icon(
            Icons.person,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
        ),
        title: Text(
          scan.studentName.isNotEmpty ? scan.studentName : scan.studentId,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ID: ${scan.studentId}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
            Text(
              '${scan.timestamp.hour.toString().padLeft(2, '0')}:${scan.timestamp.minute.toString().padLeft(2, '0')}:${scan.timestamp.second.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (scan.studentEmail.isNotEmpty)
              Text(
                scan.studentEmail,
                style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
              ),
          ],
        ),
        trailing: Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 16,
        ),
        isThreeLine: scan.studentEmail.isNotEmpty,
      ),
    );
  }
}