import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

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

class _CameraPreviewScreenState extends State<CameraPreviewScreen>
    with WidgetsBindingObserver {
  MobileScannerController? _controller;
  bool _isInitialized = false;
  bool _hasPermission = false;
  bool _isFlashOn = false;
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_isInitialized) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _controller!.start();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _controller!.stop();
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _initializeCamera() async {
    try {
      // Request camera permission
      final permission = await Permission.camera.request();
      if (permission != PermissionStatus.granted) {
        setState(() {
          _errorMessage = 'Camera permission is required to scan barcodes';
        });
        return;
      }

      setState(() {
        _hasPermission = true;
      });

      // Initialize the scanner controller
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
        torchEnabled: false,
      );

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize camera: $e';
      });
    }
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final barcode = barcodes.first;
      final code = barcode.rawValue;

      if (code != null && code.isNotEmpty) {
        setState(() {
          _isProcessing = true;
        });

        // Provide haptic feedback
        HapticFeedback.mediumImpact();

        // Call the callback with the scanned code
        widget.onBarcodeScanned(code);

        // Close the camera screen after a short delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    }
  }

  void _toggleFlash() async {
    if (_controller != null) {
      await _controller!.toggleTorch();
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
    }
  }

  void _switchCamera() async {
    if (_controller != null) {
      await _controller!.switchCamera();
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
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () {
            widget.onClose?.call();
            Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'Scan Barcode',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          if (_isInitialized) ...[
            IconButton(
              icon: Icon(
                _isFlashOn ? Icons.flash_on : Icons.flash_off,
                color: Colors.white,
              ),
              onPressed: _toggleFlash,
            ),
            IconButton(
              icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
              onPressed: _switchCamera,
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return _buildErrorView();
    }

    if (!_hasPermission) {
      return _buildPermissionView();
    }

    if (!_isInitialized || _controller == null) {
      return _buildLoadingView();
    }

    return Stack(
      children: [
        // Camera preview
        MobileScanner(
          controller: _controller!,
          onDetect: _onBarcodeDetected,
        ),

        // Overlay with scanning frame
        _buildScanningOverlay(),

        // Processing indicator
        if (_isProcessing) _buildProcessingOverlay(),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            Text(
              'Camera Error',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                });
                _initializeCamera();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.camera_alt_outlined,
              size: 64,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            Text(
              'Camera Permission Required',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please grant camera permission to scan barcodes',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                final permission = await Permission.camera.request();
                if (permission == PermissionStatus.granted) {
                  _initializeCamera();
                } else {
                  // Open app settings if permission is permanently denied
                  await openAppSettings();
                }
              },
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text(
            'Initializing Camera...',
            style: TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningOverlay() {
    return CustomPaint(
      painter: ScanningOverlayPainter(),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: 100),
            child: Text(
              'Position the barcode within the frame',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black54,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Processing...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScanningOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;

    final framePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final cornerPaint = Paint()
      ..color = const Color(0xFF1976D2) // Charleston Law blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    // Calculate frame dimensions
    final frameWidth = size.width * 0.8;
    final frameHeight = frameWidth * 0.6;
    final frameLeft = (size.width - frameWidth) / 2;
    final frameTop = (size.height - frameHeight) / 2;
    final frameRight = frameLeft + frameWidth;
    final frameBottom = frameTop + frameHeight;

    // Draw overlay (darkened areas outside the frame)
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(Rect.fromLTWH(frameLeft, frameTop, frameWidth, frameHeight))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Draw frame border
    canvas.drawRect(
      Rect.fromLTWH(frameLeft, frameTop, frameWidth, frameHeight),
      framePaint,
    );

    // Draw corner indicators
    const cornerLength = 20.0;

    // Top-left corner
    canvas.drawLine(
      Offset(frameLeft, frameTop + cornerLength),
      Offset(frameLeft, frameTop),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(frameLeft, frameTop),
      Offset(frameLeft + cornerLength, frameTop),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(frameRight - cornerLength, frameTop),
      Offset(frameRight, frameTop),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(frameRight, frameTop),
      Offset(frameRight, frameTop + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(frameLeft, frameBottom - cornerLength),
      Offset(frameLeft, frameBottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(frameLeft, frameBottom),
      Offset(frameLeft + cornerLength, frameBottom),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(frameRight - cornerLength, frameBottom),
      Offset(frameRight, frameBottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(frameRight, frameBottom - cornerLength),
      Offset(frameRight, frameBottom),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

// Navigation service for accessing context in static methods
class NavigationService {
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}
