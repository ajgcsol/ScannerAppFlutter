import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraPreviewScreen extends StatefulWidget {
  final Function(String) onBarcodeScanned;
  final VoidCallback? onClose;

  const CameraPreviewScreen({
    super.key,
    required this.onBarcodeScanned,
    this.onClose,
  });

  @override
  State<CameraPreviewScreen> createState() => _CameraPreviewScreenState();
}

class _CameraPreviewScreenState extends State<CameraPreviewScreen> {
  MobileScannerController? _controller;
  bool _isFlashOn = false;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanning) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final barcode = barcodes.first;
      final String code = barcode.rawValue ?? '';
      
      if (code.isNotEmpty) {
        if (kDebugMode) {
          print('✅ Barcode scanned: $code');
        }
        
        setState(() {
          _isScanning = true;
        });
        
        // Call the callback with the scanned code
        widget.onBarcodeScanned(code);
        
        // Close this screen
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    
    try {
      await _controller!.toggleTorch();
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error toggling flash: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            widget.onClose?.call();
            Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'Scan Barcode',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isFlashOn ? Icons.flash_on : Icons.flash_off,
              color: Colors.white,
            ),
            onPressed: _toggleFlash,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera preview - full screen
          if (_controller != null)
            MobileScanner(
              controller: _controller!,
              onDetect: _onDetect,
            ),
          
          // Scanning overlay UI
          _buildScannerOverlay(),
          
          // Instructions
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Point your camera at a barcode or QR code',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          
          // Cancel button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: OutlinedButton(
                onPressed: () {
                  widget.onClose?.call();
                  Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white, width: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerOverlay() {
    return CustomPaint(
      painter: ScannerOverlayPainter(),
      child: Container(),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    // Calculate scan area - centered square
    final double scanSize = size.width * 0.7;
    final double left = (size.width - scanSize) / 2;
    final double top = (size.height - scanSize) / 2;

    // Draw overlay with transparent center
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(Rect.fromLTWH(left, top, scanSize, scanSize))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Draw corner brackets
    final cornerPaint = Paint()
      ..color = const Color(0xFF1976D2)  // Charleston Law blue
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final double cornerLength = 25;

    // Top-left
    canvas.drawLine(
      Offset(left, top),
      Offset(left + cornerLength, top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left, top),
      Offset(left, top + cornerLength),
      cornerPaint,
    );

    // Top-right
    canvas.drawLine(
      Offset(left + scanSize, top),
      Offset(left + scanSize - cornerLength, top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + scanSize, top),
      Offset(left + scanSize, top + cornerLength),
      cornerPaint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(left, top + scanSize),
      Offset(left + cornerLength, top + scanSize),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left, top + scanSize),
      Offset(left, top + scanSize - cornerLength),
      cornerPaint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(left + scanSize, top + scanSize),
      Offset(left + scanSize - cornerLength, top + scanSize),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + scanSize, top + scanSize),
      Offset(left + scanSize, top + scanSize - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
