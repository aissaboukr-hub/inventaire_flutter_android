import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage>
    with WidgetsBindingObserver {
  late final MobileScannerController controller;
  bool _isScanned = false;
  bool _isStarting = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Le démarrage est contrôlé ici, et non simultanément par le widget
    // MobileScanner (autoStart:false), afin d'éviter les doubles démarrages.
    controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
      returnImage: false,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScanner();
    });
  }

  Future<void> _startScanner() async {
    if (!mounted || _isScanned || _isStarting || controller.value.isRunning) {
      return;
    }

    _isStarting = true;
    if (mounted) {
      setState(() => _cameraError = null);
    }

    try {
      await controller.start();
    } catch (_) {
      if (mounted) {
        setState(() {
          _cameraError =
              'Impossible d’ouvrir la caméra. Vérifiez son autorisation dans les paramètres de votre téléphone, puis réessayez.';
        });
      }
    } finally {
      _isStarting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startScanner();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      controller.stop();
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isScanned || !mounted) return;

    final rawValue = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    if (rawValue.isEmpty) return;

    // Verrouiller immédiatement pour éviter plusieurs retours du même scan.
    _isScanned = true;

    try {
      await controller.stop();
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {
      // Le résultat du code-barres reste valable même si l'arrêt de la
      // caméra ou le son échoue.
    }

    if (mounted) {
      context.pop(rawValue);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left,
            size: 28,
            color: Theme.of(context).primaryColor,
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Scanner un code-barres',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: controller,
              onDetect: _onDetect,
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [_corner(), _corner()],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [_corner(), _corner()],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              'Alignez le code-barres dans le cadre',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          if (_cameraError != null)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.78),
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.no_photography,
                        color: Colors.white,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _cameraError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _startScanner,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _corner() {
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }
}
