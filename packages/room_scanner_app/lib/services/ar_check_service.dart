import 'package:flutter/material.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

import '../l10n/generated/app_localizations.dart';
import '../scanner/engine/scanner_capabilities.dart';
import '../scanner/engine/scanner_mode_resolver.dart';
import '../scanner/factories/scanner_factory.dart';
import '../scanner/navigation/scanner_launch_request.dart';
import '../scanner/services/device_capabilities_service.dart';

class ArCheckService {
  ArCheckService._();

  static ScannerFactory? _scannerFactory;

  static void configure({required ScannerFactory scannerFactory}) {
    _scannerFactory = scannerFactory;
  }

  /// Selecciona automáticamente el mejor scanner disponible.
  ///
  /// Prioridad:
  ///
  /// 1. ARCore / ARKit
  /// 2. Cámara básica
  /// 3. Aviso de dispositivo no compatible
  static Future<void> abrirEscanerConValidacion(
    BuildContext context, {
    required String projectUuid,
    required String projectName,
    ScanContinuationReference? continuationReference,
    RoomModel? resumeRoom,
  }) async {
    try {
      final capabilities =
          await DeviceCapabilitiesService.detect();

      if (!context.mounted) return;

      final scannerMode =
          const ScannerModeResolver().resolve(capabilities);
      final scannerScreen = _scannerFactory?.createScreen(
        mode: scannerMode,
        request: ScannerLaunchRequest(
          projectUuid: projectUuid,
          projectName: projectName,
          continuationReference: continuationReference,
          resumeRoom: resumeRoom,
        ),
      );

      if (scannerScreen == null) {
        _mostrarAvisoNoSoportado(
          context,
          capabilities,
        );
        return;
      }

      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => scannerScreen,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;

      _mostrarAvisoNoSoportado(
        context,
        const ScannerCapabilities(),
      );
    }
  }

  static void _mostrarAvisoNoSoportado(
    BuildContext context,
    ScannerCapabilities capabilities,
  ) {
    final localizations = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        return AlertDialog(
          scrollable: true,
          insetPadding: EdgeInsets.symmetric(
            horizontal: size.width < 400 ? 12 : 40,
            vertical: 12,
          ),
          actionsOverflowAlignment: OverflowBarAlignment.end,
          actionsOverflowButtonSpacing: 8,
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  localizations.scannerUnavailable,
                ),
              ),
            ],
          ),
          content: Text(
            capabilities.hasCamera
                ? localizations.basicScannerInitializationFailed
                : localizations.deviceCameraUnavailable,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child:
                  Text(localizations.understood),
            ),
          ],
        );
      },
    );
  }
}
