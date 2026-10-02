import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Solicita el permiso de cámara necesario para escanear.
  static Future<bool> requestScannerPermissions() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Verifica si el permiso de cámara ya fue concedido.
  static Future<bool> hasBasicPermissions() {
    return Permission.camera.isGranted;
  }

  /// Indica si el sistema ya no permite volver a solicitar el permiso.
  static Future<bool> isScannerPermissionPermanentlyDenied() {
    return Permission.camera.isPermanentlyDenied;
  }

  /// Abre los ajustes del sistema para recuperar un permiso bloqueado.
  static Future<bool> openScannerSettings() {
    return openAppSettings();
  }
}
