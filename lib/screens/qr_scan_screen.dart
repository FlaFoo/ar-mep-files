import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _scanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.isEmpty) return;

    final parsed = _parse(value);
    if (parsed == null) return;

    _scanned = true;
    Navigator.pop(context, parsed);
  }

  /// Accepte :
  ///   arvision://CODE/PASS
  ///   CODE/PASS
  ///   {"code":"...","pass":"..."}
  ({String code, String pass})? _parse(String raw) {
    // Format URI arvision://CODE/PASS
    if (raw.startsWith('arvision://')) {
      final path = raw.substring('arvision://'.length);
      final parts = path.split('/');
      if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        return (code: parts[0].toUpperCase(), pass: parts[1].toUpperCase());
      }
    }
    // Format CODE/PASS
    if (raw.contains('/')) {
      final parts = raw.split('/');
      if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        return (code: parts[0].toUpperCase(), pass: parts[1].toUpperCase());
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Scanner le QR code', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: ArMepTheme.border),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          // Viseur centré
          Center(
            child: Builder(builder: (context) {
              final size = MediaQuery.of(context).size.shortestSide * 0.55;
              return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                border: Border.all(color: ArMepTheme.accentBlue, width: 2),
                borderRadius: BorderRadius.circular(ArMepTheme.radiusMD),
              ),
            );
            }),
          ),
          // Hint bas
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Text(
              'Pointez la caméra sur le QR code du chantier',
              textAlign: TextAlign.center,
              style: ArMepTheme.bodyText.copyWith(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
