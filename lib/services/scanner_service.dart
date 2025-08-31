import 'dart:async';
import 'package:mobile_scanner/mobile_scanner.dart';

// Scan Result class
class ScanResult {
  final String code;
  final String? symbology;
  final DateTime timestamp;

  ScanResult({
    required this.code,
    this.symbology,
    required this.timestamp,
  });
}

class ScannerService {
  MobileScannerController? _controller;
  bool _isInitialized = false;

  Future<void> initialize() async {
    try {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
        torchEnabled: false,
      );
      _isInitialized = true;
    } catch (e) {
      throw Exception('Failed to initialize scanner: $e');
    }
  }

  Future<ScanResult> scan() async {
    if (!_isInitialized || _controller == null) {
      throw Exception('Scanner not initialized');
    }

    final completer = Completer<ScanResult>();
    StreamSubscription? subscription;

    try {
      subscription = _controller!.barcodes.listen((capture) {
        final List<Barcode> barcodes = capture.barcodes;
        if (barcodes.isNotEmpty) {
          final barcode = barcodes.first;
          final result = ScanResult(
            code: barcode.rawValue ?? '',
            symbology: barcode.type.name,
            timestamp: DateTime.now(),
          );
          
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        }
      });

      // Start scanning
      _controller!.start();

      // Wait for scan result with timeout
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Scan timeout');
        },
      );
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
      rethrow;
    } finally {
      subscription?.cancel();
      try {
        _controller?.stop();
      } catch (e) {
        // Ignore stop errors
      }
    }
  }

  Future<void> dispose() async {
    try {
      _controller?.dispose();
    } catch (e) {
      // Ignore dispose errors
    }
    _controller = null;
    _isInitialized = false;
  }

  bool get isInitialized => _isInitialized;

  MobileScannerController? get controller => _controller;
}

// Mock scanner for testing without camera
class MockScannerService extends ScannerService {
  final List<String> _mockCodes = [
    '1234567890123',
    'MOCK_QR_CODE',
    'TEST_CODE_128',
    'SAMPLE_BARCODE',
    'STUDENT_ID_001',
    'STUDENT_ID_002',
    'STUDENT_ID_003',
  ];

  @override
  Future<void> initialize() async {
    _isInitialized = true;
  }

  @override
  Future<ScanResult> scan() async {
    if (!_isInitialized) {
      throw Exception('Mock scanner not initialized');
    }

    // Simulate scanning delay
    await Future.delayed(const Duration(milliseconds: 1500));

    // Return random mock scan result
    final code = _mockCodes[DateTime.now().millisecond % _mockCodes.length];
    
    return ScanResult(
      code: code,
      symbology: 'CODE_128',
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;
  }
}
