import 'package:flutter/material.dart';
import '../models/scan_record.dart';

class ScanItem extends StatelessWidget {
  final ScanRecord scan;

  const ScanItem({
    super.key,
    required this.scan,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.qr_code_2,
              color: Theme.of(context).primaryColor,
              size: 20,
            ),
            
            const SizedBox(width: 12),
            
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scan.code,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const SizedBox(height: 2),
                  
                  Row(
                    children: [
                      Text(
                        scan.symbology ?? 'Unknown',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      
                      Text(
                        ' • ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      
                      Text(
                        scan.formattedTimestamp,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Sync status indicator
            if (scan.synced)
              const Icon(
                Icons.cloud_done,
                color: Colors.green,
                size: 16,
              )
            else
              const Icon(
                Icons.cloud_off,
                color: Colors.orange,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }
}
