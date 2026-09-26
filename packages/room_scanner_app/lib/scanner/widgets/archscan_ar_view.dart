import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ar/archscan_ar_session.dart';

typedef ArchScanArViewCreatedCallback =
    void Function(ArchScanArSession session);

/// Thin platform-view bridge that exposes the native view id.
///
/// `ar_flutter_plugin_2` hides this id, although Android's camera-pose channel
/// needs it. Camera permissions remain owned by the existing scanner flow.
/// Plugin types stay inside this file and [ArchScanArSession].
class ArchScanArView extends StatelessWidget {
  final ArchScanArViewCreatedCallback onCreated;
  final ArchScanPlaneDetection planeDetection;

  const ArchScanArView({
    super.key,
    required this.onCreated,
    this.planeDetection = ArchScanPlaneDetection.none,
  });

  static PlaneDetectionConfig _toPluginConfig(ArchScanPlaneDetection value) {
    switch (value) {
      case ArchScanPlaneDetection.none:
        return PlaneDetectionConfig.none;
      case ArchScanPlaneDetection.horizontal:
        return PlaneDetectionConfig.horizontal;
      case ArchScanPlaneDetection.vertical:
        return PlaneDetectionConfig.vertical;
      case ArchScanPlaneDetection.horizontalAndVertical:
        return PlaneDetectionConfig.horizontalAndVertical;
    }
  }

  @override
  Widget build(BuildContext context) {
    void created(int id) {
      onCreated(
        ArchScanArSession(
          viewId: id,
          sessionManager: ARSessionManager(
            id,
            context,
            _toPluginConfig(planeDetection),
          ),
          objectManager: ARObjectManager(id),
          anchorManager: ARAnchorManager(id),
          locationManager: ARLocationManager(),
        ),
      );
    }

    const creationParams = <String, dynamic>{};
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidView(
          viewType: 'ar_flutter_plugin_2',
          layoutDirection: TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: created,
        );
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: 'ar_flutter_plugin_2',
          layoutDirection: TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: created,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
