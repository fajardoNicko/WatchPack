import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/linking.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

/// Camera that reads the QR on the WatchPack's sticker or on another parent's
/// invite screen. Pops with the 8-character code, or null.
class ScanCodeScreen extends StatefulWidget {
  const ScanCodeScreen({super.key});

  static Future<String?> open(BuildContext context) => Navigator.of(context)
      .push<String>(MaterialPageRoute(builder: (_) => const ScanCodeScreen(), fullscreenDialog: true));

  @override
  State<ScanCodeScreen> createState() => _ScanCodeScreenState();
}

class _ScanCodeScreenState extends State<ScanCodeScreen> {
  final _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  bool _foreign = false;                  // saw a QR code that isn't ours

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final code = b.rawValue == null ? null : codeFromScan(b.rawValue!);
      if (code != null) {
        _done = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
    if (!_foreign && capture.barcodes.isNotEmpty) setState(() => _foreign = true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: WpHeader(
          title: 'Scan a code',
          subtitle: 'The WatchPack\'s sticker, or a parent\'s invite',
          back: true,
          trailing: IconButton(
            tooltip: 'Torch',
            onPressed: _camera.toggleTorch,
            icon: const Icon(Symbols.flashlight_on_rounded, color: Colors.white),
          ),
        ),
        body: Stack(fit: StackFit.expand, children: [
          MobileScanner(controller: _camera, onDetect: _onDetect, errorBuilder: (_, e) => _CameraError(e)),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: WpColors.cyan, width: 3),
                  borderRadius: BorderRadius.circular(WpRadius.card),
                ),
              ),
            ),
          ),
          Positioned(
            left: WpSpace.xl,
            right: WpSpace.xl,
            bottom: WpSpace.xxl,
            child: Text(
              _foreign ? 'That QR code isn\'t a WatchPack code.' : 'Point the camera at the QR code.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium!.copyWith(color: Colors.white),
            ),
          ),
        ]),
      );
}

class _CameraError extends StatelessWidget {
  const _CameraError(this.e);
  final MobileScannerException e;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(WpSpace.xl),
            child: Text(
              e.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'WatchPack needs the camera to read the code. Allow it in the phone\'s settings, or type the code instead.'
                  : 'The camera isn\'t available right now. Type the code instead.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium!.copyWith(color: Colors.white),
            ),
          ),
        ),
      );
}
