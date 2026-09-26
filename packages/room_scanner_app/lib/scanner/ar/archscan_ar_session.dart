import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';

/// Detección de planos solicitada a la sesión AR nativa.
enum ArchScanPlaneDetection {
  none,
  horizontal,
  vertical,
  horizontalAndVertical,
}

/// Sesión AR nativa creada por `ArchScanArView`.
///
/// Es el único tipo que transporta los managers de `ar_flutter_plugin_2`
/// entre la vista nativa y `ARScannerAdapter`. Las pantallas lo reciben como
/// un handle opaco, de modo que reemplazar el plugin no obliga a tocar la UI.
class ArchScanArSession {
  final int viewId;
  final ARSessionManager sessionManager;
  final ARObjectManager objectManager;
  final ARAnchorManager anchorManager;
  final ARLocationManager locationManager;

  const ArchScanArSession({
    required this.viewId,
    required this.sessionManager,
    required this.objectManager,
    required this.anchorManager,
    required this.locationManager,
  });

  /// Libera la sesión nativa.
  void dispose() {
    sessionManager.dispose();
  }
}
