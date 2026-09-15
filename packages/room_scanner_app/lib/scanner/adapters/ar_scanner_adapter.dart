import 'dart:io';

import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

import '../engine/scanner_adapter.dart';
import '../models/scanner_mode.dart';
import '../models/scanner_point.dart';

/// Adapter del motor AR.
///
/// Encapsula toda la interacción con ar_flutter_plugin_2.
///
/// IMPORTANTE:
/// - No contiene lógica de RoomModel.
/// - No contiene lógica de ScannerProvider.
/// - No contiene UI.
/// - No decide cuándo guardar una habitación.
/// - Solamente administra la sesión AR y entrega ScannerPoint.
class ARScannerAdapter implements ScannerAdapter {
  ARSessionManager? _sessionManager;
  ARObjectManager? _objectManager;
  MethodChannel? _androidSessionChannel;

  bool _initialized = false;
  bool _tracking = false;

  vector.Vector3? _lastPosition;

  @override
  ScannerMode get mode => ScannerMode.ar;

  @override
  bool get isAvailable => _sessionManager != null;

  @override
  bool get isTracking => _tracking;

  /// El adapter AR necesita recibir los managers creados por ARView.
  ///
  /// ARView sigue perteneciendo a la UI.
  void attachARSession({
    required int viewId,
    required ARSessionManager sessionManager,
    required ARObjectManager objectManager,
  }) {
    _sessionManager = sessionManager;
    _objectManager = objectManager;
    _androidSessionChannel = MethodChannel('arsession_$viewId');

    _initializeManagers();
  }

  void _initializeManagers() {
    final session = _sessionManager;
    final objects = _objectManager;

    if (session == null || objects == null) {
      return;
    }

    session.onInitialize(
      showFeaturePoints: false,
      showPlanes: true,
      customPlaneTexturePath: null,
      showWorldOrigin: false,
      handleTaps: false,
    );

    objects.onInitialize();

    _initialized = true;
    _tracking = true;
  }

  @override
  Future<void> initialize() async {
    if (_sessionManager == null) {
      throw StateError(
        'ARScannerAdapter necesita una ARSessionManager. '
        'Conecta primero ARView mediante attachARSession().',
      );
    }

    if (!_initialized) {
      _initializeManagers();
    }
  }

  /// Obtiene la posición actual de la cámara y la transforma en
  /// ScannerPoint.
  ///
  /// Nunca devuelve una posición artificial como (0,0,0).
  @override
  Future<ScannerPoint?> capturePoint() async {
    final session = _sessionManager;

    if (session == null || !_initialized) {
      return null;
    }

    final translation = Platform.isAndroid
        ? await _getAndroidCameraTranslation(session)
        : (await session.getCameraPose())?.getTranslation();

    if (translation == null) {
      return null;
    }

    _lastPosition = translation;

    // Cada llamada representa una esquina distinta, no muestras sucesivas de
    // una misma posición. Aplicar un EMA entre capturas reduce artificialmente
    // la pared (con alpha 0.3, 1.10 m se convertía en 0.33 m).
    return scannerPointFromTranslation(translation);
  }

  static ScannerPoint scannerPointFromTranslation(vector.Vector3 translation) {
    return ScannerPoint(
      x: translation.x,
      y: translation.y,
      z: translation.z,
      accuracy: 0.0,
      source: PointSource.ar,
    );
  }

  Future<vector.Vector3?> _getAndroidCameraTranslation(
    ARSessionManager session,
  ) async {
    try {
      final raw = await _androidSessionChannel
          ?.invokeMethod<dynamic>('getCameraPose', const <String, dynamic>{});
      final decoded = decodeAndroidCameraTranslation(raw);
      if (decoded != null) return decoded;
    } on PlatformException {
      // Fall through to the plugin API for forwards compatibility.
    }
    return (await session.getCameraPose())?.getTranslation();
  }

  static vector.Vector3? decodeAndroidCameraTranslation(dynamic raw) {
    if (raw is! Map) return null;
    final position = raw['position'];
    if (position is! Map) return null;
    final x = position['x'];
    final y = position['y'];
    final z = position['z'];
    if (x is! num || y is! num || z is! num) return null;
    return vector.Vector3(x.toDouble(), y.toDouble(), z.toDouble());
  }

  vector.Vector3? get lastPosition => _lastPosition;

  /// Notifica al adapter que el tracking se encuentra operativo.
  void setTrackingStatus(bool tracking) {
    _tracking = tracking;
  }

  @override
  Future<void> dispose() async {
    _tracking = false;
    _initialized = false;
    _lastPosition = null;

    final session = _sessionManager;

    _sessionManager = null;
    _objectManager = null;
    _androidSessionChannel = null;

    await session?.dispose();
  }
}
