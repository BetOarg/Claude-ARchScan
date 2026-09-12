import 'dart:async';
import 'dart:convert';

import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

import '../l10n/generated/app_localizations.dart';
import '../l10n/room_type_localization.dart';
import '../providers/floor_plan_provider.dart';
import '../providers/measurement_settings_provider.dart';
import '../providers/scanner_provider.dart';
import '../services/permission_service.dart';
import '../services/resume_room_calibration.dart';
import '../services/scan_draft_service.dart';
import '../widgets/room_name_dialog.dart';
import '../widgets/room_completion_dialog.dart';
import '../widgets/opening_placement_dialog.dart' show showOpeningPlacementDialog;
import '../widgets/scanner_plan_opening_hint.dart';
import '../widgets/scanner_guide_painter.dart';
import '../scanner/adapters/ar_scanner_adapter.dart';
import '../scanner/widgets/archscan_ar_view.dart';
import 'basic_scanner_screen.dart';
import 'floor_plan_viewer_screen.dart';

enum AppMode {
  wall,
  door,
  window,
}

class ARScannerScreen extends StatefulWidget {
  /// UUID del proyecto Isar al que pertenece este escaneo.
  final String projectUuid;

  final String projectName;

  /// Abertura global seleccionada en el plano 2D para continuar el escaneo.
  ///
  /// En ARCore/ARKit sus extremos se utilizarán como destino global después
  /// de que el usuario vuelva a marcar la abertura en la nueva sesión AR.
  final ScanContinuationReference? continuationReference;

  /// Ambiente abierto existente que se reemplazará al finalizar.
  final RoomModel? resumeRoom;

  const ARScannerScreen({
    super.key,
    required this.projectUuid,
    required this.projectName,
    this.continuationReference,
    this.resumeRoom,
  });

  @override
  State<ARScannerScreen> createState() => _ARScannerScreenState();
}

class _ARScannerScreenState extends State<ARScannerScreen>
    with WidgetsBindingObserver {
  static const ScanDraftService _scanDraftService = ScanDraftService();

  final AppMode _currentMode = AppMode.wall;
  bool _placingOpening = false;
  ScanContinuationReference? _activeContinuationReference;
  ScannerProvider? _draftProvider;
  Timer? _draftSaveTimer;
  String? _lastDraftFingerprint;

  ARPoint? _pendingFeatureStart;
  AppMode? _pendingFeatureMode;

  vector.Vector3? _continuationSessionStart;
  vector.Vector3? _continuationSessionEnd;

  bool get _requiresContinuationCalibration =>
      _activeContinuationReference != null || widget.resumeRoom != null;

  bool get _isContinuationCalibrated =>
      !_requiresContinuationCalibration ||
      (_continuationSessionStart != null &&
          _continuationSessionEnd != null);

  // ================================================================
  // CONTROLADORES AR
  // ================================================================

  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;
  static const Duration _arInitializationTimeout =
      Duration(seconds: 15);
  Future<void> _arLifecycleTask = Future<void>.value();
  Timer? _arInitializationTimer;
  bool _appIsResumed = true;
  bool _arSessionReady = false;
  bool _arInitializationFailed = false;
  int _arViewGeneration = 0;

  // ================================================================
  // SCANNER ENGINE
  // ================================================================

  /// Adapter responsable de encapsular la interacción con ARCore/ARKit.
  ///
  /// La pantalla no obtiene directamente la pose de la cámara.
  /// Eso ahora pertenece al Scanner Engine.
  final ARScannerAdapter _arScannerAdapter = ARScannerAdapter();

  // Posición actual estimada del dispositivo/cámara.
  vector.Vector3 _currentCameraPosition = vector.Vector3(0, 0, 0);

  bool _permissionsGranted = false;
  bool _checkingPermissions = true;

  // ================================================================
  // CICLO DE VIDA
  // ================================================================

  @override
  void initState() {
    super.initState();

    _activeContinuationReference = widget.continuationReference;
    _appIsResumed =
        WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed;

    WidgetsBinding.instance
        .addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Permisos del modo AR actual.
      final granted =
          await PermissionService.requestScannerPermissions();

      if (!mounted) return;

      setState(() {
        _permissionsGranted = granted;
        _checkingPermissions = false;
      });

      if (granted) {
        _startArInitializationWatchdog();
      }

      if (!granted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.cameraLocationPermissionsDenied),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );

        return;
      }

      if (!mounted) return;

      final provider = context.read<ScannerProvider>();
      await _restoreOrStartRoom(provider);
      _attachDraftListener(provider);
    });
  }

  Future<void> _restoreOrStartRoom(ScannerProvider provider) async {
    final resumeRoom = widget.resumeRoom;
    if (resumeRoom != null) {
      provider.restoreCurrentRoom(resumeRoom);
      return;
    }

    final draft = await _scanDraftService.load(widget.projectUuid);
    if (!mounted) return;

    if (draft == null) {
      provider.startNewRoom();
      return;
    }

    final draftRoomWasClosed = context
        .read<FloorPlanProvider>()
        .completedRooms
        .any((room) => room.id == draft.room.id && room.isClosed);
    if (draftRoomWasClosed) {
      await _scanDraftService.clear(widget.projectUuid);
      if (!mounted) return;
      _lastDraftFingerprint = null;
      provider.startNewRoom();
      return;
    }

    final continueDraft = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(l10n.unfinishedScan),
          content: Text(l10n.unfinishedScanFound),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.discardScan),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.continueScan),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (continueDraft == true) {
      _activeContinuationReference = draft.continuationReference;
      provider.restoreCurrentRoom(draft.room);
      return;
    }

    await _scanDraftService.clear(widget.projectUuid);
    _lastDraftFingerprint = null;
    provider.startNewRoom();
  }

  void _attachDraftListener(ScannerProvider provider) {
    _draftProvider?.removeListener(_onScannerDraftChanged);
    _draftProvider = provider;
    provider.addListener(_onScannerDraftChanged);
    _onScannerDraftChanged();
  }

  void _onScannerDraftChanged() {
    final room = _draftProvider?.currentRoom;
    if (room == null || (room.points.isEmpty && room.features.isEmpty)) {
      return;
    }

    final fingerprint = jsonEncode(<String, dynamic>{
      'room': room.toJson(),
      'continuation': _activeContinuationReference?.featureId,
    });
    if (fingerprint == _lastDraftFingerprint) return;

    _lastDraftFingerprint = fingerprint;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 250), () {
      _scanDraftService.save(
        projectUuid: widget.projectUuid,
        room: room,
        continuationReference: _activeContinuationReference,
      );
    });
  }

  Future<void> _flushDraft() async {
    _draftSaveTimer?.cancel();
    final room = _draftProvider?.currentRoom;
    if (room == null || (room.points.isEmpty && room.features.isEmpty)) return;

    await _scanDraftService.save(
      projectUuid: widget.projectUuid,
      room: room,
      continuationReference: _activeContinuationReference,
    );
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (!_appIsResumed) {
        return;
      }

      _appIsResumed = false;
      _flushDraft();
      _pendingFeatureStart = null;
      _pendingFeatureMode = null;

      if (_requiresContinuationCalibration) {
        _continuationSessionStart = null;
        _continuationSessionEnd = null;
      }

      _queueArLifecycle(_suspendArSession);
      return;
    }

    if (state == AppLifecycleState.resumed) {
      if (_appIsResumed) {
        return;
      }

      _appIsResumed = true;
      _queueArLifecycle(_restartArView);
    }
  }

  void _queueArLifecycle(
    Future<void> Function() operation,
  ) {
    _arLifecycleTask = _arLifecycleTask
        .then((_) => operation())
        .catchError((_) {
      if (mounted) {
        context
            .read<ScannerProvider>()
            .updateTrackingStatus(false);
      }
    });
  }

  Future<void> _suspendArSession() async {
    _arInitializationTimer?.cancel();
    _arSessionReady = false;

    if (mounted) {
      context
          .read<ScannerProvider>()
          .updateTrackingStatus(false);
    }

    _arSessionManager = null;
    _arObjectManager = null;
    await _arScannerAdapter.dispose();
  }

  Future<void> _restartArView() async {
    if (!mounted || !_appIsResumed) {
      return;
    }

    setState(() {
      _arSessionReady = false;
      _arInitializationFailed = false;
      _arViewGeneration++;
    });
    _startArInitializationWatchdog();
  }

  @override
  void dispose() {
    _flushDraft();
    _draftSaveTimer?.cancel();
    _draftProvider?.removeListener(_onScannerDraftChanged);
    _arInitializationTimer?.cancel();
    _appIsResumed = false;
    WidgetsBinding.instance
        .removeObserver(this);

    unawaited(_arScannerAdapter.dispose());

    _arSessionManager = null;
    _arObjectManager = null;

    super.dispose();
  }

  // ================================================================
  // AR VIEW
  // ================================================================

  void _onARViewCreated(
    int generation,
    int viewId,
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager,
  ) {
    if (!mounted ||
        !_appIsResumed ||
        generation != _arViewGeneration) {
      arSessionManager.dispose();
      return;
    }

    _arInitializationTimer?.cancel();
    _arSessionReady = true;
    _arInitializationFailed = false;
    _arSessionManager = arSessionManager;
    _arObjectManager = arObjectManager;

    _arScannerAdapter.attachARSession(
      viewId: viewId,
      sessionManager: arSessionManager,
      objectManager: arObjectManager,
    );

    context.read<ScannerProvider>().updateTrackingStatus(true);
  }

  void _startArInitializationWatchdog() {
    _arInitializationTimer?.cancel();

    if (!_appIsResumed || _arSessionReady) {
      return;
    }

    final watchedGeneration = _arViewGeneration;
    _arInitializationTimer = Timer(
      _arInitializationTimeout,
      () {
        if (!mounted ||
            !_appIsResumed ||
            _arSessionReady ||
            watchedGeneration != _arViewGeneration) {
          return;
        }

        _arSessionManager = null;
        _arObjectManager = null;
        unawaited(_arScannerAdapter.dispose());

        setState(() {
          _arInitializationFailed = true;
          _arViewGeneration++;
        });

        context
            .read<ScannerProvider>()
            .updateTrackingStatus(false);
      },
    );
  }

  Future<void> _retryArInitialization() async {
    _arInitializationTimer?.cancel();
    _arSessionManager = null;
    _arObjectManager = null;
    await _arScannerAdapter.dispose();

    if (!mounted || !_appIsResumed) {
      return;
    }

    setState(() {
      _arSessionReady = false;
      _arInitializationFailed = false;
      _arViewGeneration++;
    });
    _startArInitializationWatchdog();
  }

  void _openBasicScannerFallback() {
    _arInitializationTimer?.cancel();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BasicScannerScreen(
          projectUuid: widget.projectUuid,
          projectName: widget.projectName,
          continuationReference: _activeContinuationReference,
        ),
      ),
    );
  }

  Widget _buildArInitializationFallback(
    AppLocalizations l10n,
  ) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.view_in_ar_outlined,
                    size: 72,
                    color: Colors.orangeAccent,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.arInitializationFailedTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.arInitializationFailedMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _retryArInitialization,
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.retryArScanner),
                      ),
                      FilledButton.icon(
                        onPressed: _openBasicScannerFallback,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: Text(l10n.useBasicScanner),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ================================================================
  // POSICIÓN DE CÁMARA
  // ================================================================

  Future<vector.Vector3?> _getCurrentCameraPosition() async {
    final point = await _arScannerAdapter.capturePoint();

    if (point == null) {
      return null;
    }

    final position = vector.Vector3(
      point.x,
      point.y,
      point.z,
    );

    _currentCameraPosition = position;

    return position;
  }
  // ================================================================
  // BUILD
  // ================================================================

  @override  Widget build(BuildContext context) {
    final provider = context.watch<ScannerProvider>();
    final measurementSystem = context
        .watch<MeasurementSettingsProvider>()
        .system;
    final l10n = AppLocalizations.of(context)!;
    final arViewGeneration = _arViewGeneration;
    final narrowLayout = MediaQuery.sizeOf(context).width < 520;

    if (_checkingPermissions) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_permissionsGranted) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(l10n.permissionsRequired),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              l10n.cameraLocationPermissionsDenied,
              style: const TextStyle(
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_arInitializationFailed) {
      return _buildArInitializationFallback(l10n);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ============================================================
          // CAPA 1: VIEWPORT AR REAL
          // ============================================================

          ArchScanArView(
            key: ValueKey<int>(arViewGeneration),
            onCreated: (
              viewId,
              sessionManager,
              objectManager,
              anchorManager,
              locationManager,
            ) => _onARViewCreated(
              arViewGeneration,
              viewId,
              sessionManager,
              objectManager,
              anchorManager,
              locationManager,
            ),
            planeDetectionConfig:
                PlaneDetectionConfig.horizontalAndVertical,
          ),

          // ============================================================
          // CAPA 2: RETÍCULA CENTRAL
          // ============================================================

          if (_isContinuationCalibrated)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: ScannerGuidePainter(
                    points: provider.currentRoom?.points ?? const <ARPoint>[],
                    features: provider.currentRoom?.features ?? const <WallFeature>[],
                    previousRooms: _activeContinuationReference == null &&
                            widget.resumeRoom == null
                        ? const <RoomModel>[]
                        : context
                            .watch<FloorPlanProvider>()
                            .completedRooms
                            .toList(growable: false),
                    continuationReference: _activeContinuationReference,
                  ),
                ),
              ),
            ),

          Center(
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.black,
                  width: 2,
                ),
              ),
            ),
          ),

          // ============================================================
          // CAPA 3: HUD SUPERIOR DE ESTADO
          // ============================================================

          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: _buildAdaptiveTopHud(provider, l10n),
          ),

          // ============================================================
          // CAPA 4: CONTADOR DE PUNTOS
          // ============================================================

          if (provider.currentPointsCount > 0)
            Positioned(
              top: MediaQuery.of(context).padding.top +
                  (narrowLayout ? 112 : 70),
              left: 16,
              right: 16,
              child: Container(                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white24,
                  ),
                ),
                child: Text(
                  _scanRecommendation(
                    provider.currentPointsCount,
                    l10n,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
            ),

          if (_requiresContinuationCalibration)
            Positioned(
              top: MediaQuery.of(context).padding.top +
                  (narrowLayout ? 154 : 112),
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: _isContinuationCalibrated
                      ? Colors.green.withValues(alpha: 0.88)
                      : const Color(0xFFFF8A00).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isContinuationCalibrated
                          ? Icons.check_circle_outline
                          : Icons.center_focus_strong,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _continuationInstruction(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ============================================================
          // CAPA 5: CONTROLES INFERIORES
          // ============================================================

          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<MeasurementSystem>(
                  tooltip: l10n.measurementSystem,
                  initialValue: measurementSystem,
                  onSelected: (newSystem) {
                    context
                        .read<MeasurementSettingsProvider>()
                        .setSystem(newSystem);
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<MeasurementSystem>(
                      value: MeasurementSystem.metric,
                      child: ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.straighten,
                        ),
                        title: Text(
                          l10n.metricSystem,
                        ),
                      ),
                    ),
                    PopupMenuItem<MeasurementSystem>(
                      value: MeasurementSystem.imperial,
                      child: ListTile(
                        dense: true,
                        leading: const Icon(                          Icons.square_foot,
                        ),
                        title: Text(                          l10n.imperialSystem,                        ),
                      ),
                    ),
                  ],
                  child: Chip(
                    avatar: Icon(
                      measurementSystem ==
                              MeasurementSystem.metric
                          ? Icons.straighten
                          : Icons.square_foot,
                      size: 18,
                      color: Colors.white,
                    ),
                    label: Text(
                      measurementSystem ==
                              MeasurementSystem.metric
                          ? l10n.metricSystem
                          : l10n.imperialSystem,
                    ),
                    backgroundColor: Colors.black87,
                    labelStyle: const TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                const ScannerPlanOpeningHint(
                  scannerKey: ValueKey('ar-plan-opening-hint'),
                ),

                const SizedBox(height: 12),

                // ------------------------------------------------------
                // BOTONES PRINCIPALES DE ESCANEO
                // ------------------------------------------------------

                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed:
                          provider.canUndo && !_placingOpening
                              ? () {
                                  HapticFeedback
                                      .lightImpact();

                                  setState(() {
                                    _pendingFeatureStart = null;
                                    _pendingFeatureMode = null;
                                  });
                                  provider.undoEdit();
                                }
                              : null,
                      icon: const Icon(
                        Icons.undo,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            Colors.black87,
                        foregroundColor:
                            Colors.white,
                      ),
                    ),

                    IconButton(
                      tooltip: l10n.redoScanEdit,
                      onPressed: provider.canRedo && !_placingOpening ? () {
                        setState(() {
                          _pendingFeatureStart = null;
                          _pendingFeatureMode = null;
                        });
                        provider.redoEdit();
                      } : null,
                      icon: const Icon(Icons.redo),
                    ),
                    const SizedBox(width: 12),

                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            _onCapturePressed(                          provider,
                        ),
                        icon: Icon(
                          _currentMode ==
                                  AppMode.wall
                              ? Icons
                                  .add_location_alt_outlined
                              : _currentMode ==
                                      AppMode.door
                                  ? Icons
                                      .door_front_door
                                  : Icons.window,
                        ),
                        label: Text(
                          !_isContinuationCalibrated
                              ? _continuationCaptureLabel(l10n)
                              : _currentMode ==
                                  AppMode.wall
                              ? l10n.addCorner
                              : _pendingFeatureStart !=
                                      null
                                  ? l10n.markSecondEnd
                                  : _currentMode ==
                                          AppMode.door
                                      ? l10n.measureDoor
                                      : l10n.measureWindow,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        style:
                            ElevatedButton.styleFrom(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            vertical: 16,
                          ),
                          backgroundColor:
                              _modeColor(
                            _currentMode,
                          ),
                          foregroundColor:
                              Colors.white,
                          shape:
                              RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(
                              16,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    IconButton.filled(
                      onPressed:
                          provider.currentPointsCount >=
                                  3
                              ? () =>
                                  _onCloseRoomPressed(
                                    provider,
                                  )
                              : null,
                      icon: const Icon(
                        Icons.check,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            provider.currentPointsCount >=
                                    3
                                ? Colors.green
                                : Colors.grey,
                        foregroundColor:
                            Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _localizedRoomName(
    ScannerProvider provider,
    AppLocalizations l10n,
  ) {
    final room =
        provider.currentRoom;

    if (room == null) {
      return l10n.newRoom;
    }

    final defaultName =
        room.type.displayName;

    return room.name == defaultName
        ? room.type.localizedName(l10n)
        : room.name;
  }

  String _scanRecommendation(
    int cornerCount,
    AppLocalizations l10n,
  ) {
    if (cornerCount == 0) return l10n.markStartRecommendation;
    if (cornerCount < 3) return l10n.addNextCornerRecommendation;
    return l10n.closeSpaceRecommendation;
  }
  Future<void> _showCustomRoomNameDialog(
    ScannerProvider provider,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await showRoomNameDialog(
      context: context,
      initialName: provider.currentRoom?.name ??
          provider.selectedType.localizedName(l10n),
    );

    if (!mounted ||
        name == null ||
        name.trim().isEmpty) {
      return;
    }

    provider.setCurrentRoomName(
      name,
    );
  }
  Widget _buildAdaptiveTopHud(
    ScannerProvider provider,
    AppLocalizations l10n,
  ) {
    Widget roomNameChip() => ActionChip(
          tooltip: l10n.editRoomName,
          avatar: const Icon(
            Icons.edit_outlined,
            size: 16,
            color: Colors.white,
          ),
          label: Text(
            _localizedRoomName(provider, l10n),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: () => _showCustomRoomNameDialog(provider),
          backgroundColor: Colors.black87,
          labelStyle: const TextStyle(color: Colors.white),
        );

    final planButton = IconButton.filledTonal(
      tooltip: l10n.viewPlan,
      onPressed: _openFloorPlan,
      icon: const Icon(Icons.map_outlined),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
    );
    final trackingChip = Chip(
      avatar: Icon(
        Icons.circle,
        size: 10,
        color: provider.isTrackingOk
            ? Colors.greenAccent
            : Colors.orangeAccent,
      ),
      label: Text(
        provider.isTrackingOk
            ? l10n.arTrackingActive
            : l10n.arCalibrating,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      backgroundColor: Colors.black87,
      labelStyle: const TextStyle(color: Colors.white),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Expanded(child: roomNameChip()),
                  const SizedBox(width: 8),
                  planButton,
                ],
              ),
              const SizedBox(height: 6),
              trackingChip,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: roomNameChip()),
            const SizedBox(width: 8),
            planButton,
            const SizedBox(width: 8),
            Flexible(child: trackingChip),
          ],
        );
      },
    );
  }

  String _continuationInstruction() {
    final l10n = AppLocalizations.of(context)!;
    final resumesRoom = widget.resumeRoom != null;

    if (_continuationSessionStart == null) {
      return resumesRoom
          ? l10n.pointPreviousVertexInstruction
          : l10n.pointOpeningEndpointAInstruction;
    }

    if (_continuationSessionEnd == null) {
      return resumesRoom
          ? l10n.pointStartVertexInstruction
          : l10n.pointOpeningEndpointBInstruction;
    }

    return resumesRoom
        ? l10n.vertexReferenceAligned
        : l10n.openingReferenceAlignedInstruction;
  }

  String _continuationCaptureLabel(AppLocalizations l10n) {
    if (widget.resumeRoom != null) {
      return _continuationSessionStart == null
          ? l10n.markPreviousVertex
          : l10n.markStartVertex;
    }
    return _continuationSessionStart == null
        ? l10n.markOpeningEndpointA
        : l10n.markOpeningEndpointB;
  }

  Future<void> _captureContinuationEndpoint() async {
    final position = await _getCurrentCameraPosition();

    if (!mounted) return;

    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.invalidOpeningReferencePoint,
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_continuationSessionStart == null) {
      setState(() {
        _continuationSessionStart = position;
      });
      return;
    }

    final start = _continuationSessionStart!;
    final dx = position.x - start.x;
    final dz = position.z - start.z;
    final measuredWidth = vector.Vector2(dx, dz).length;

    if (measuredWidth < 0.20) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.openingReferenceEndpointsTooClose,
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (widget.resumeRoom != null) {
      final points = widget.resumeRoom!.points;
      final calibration = points.length < 2
          ? null
          : ResumeRoomCalibration.tryCreate(
              modelPrevious: points[points.length - 2],
              modelStart: points.last,
              sessionPrevious: ARPoint(
                x: start.x,
                y: start.y,
                z: start.z,
              ),
              sessionStart: ARPoint(
                x: position.x,
                y: position.y,
                z: position.z,
              ),
            );
      if (calibration == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!
                  .openingReferenceEndpointsTooClose,
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      setState(() {
        _continuationSessionEnd = position;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.vertexReferenceAligned,
          ),
        ),
      );
      return;
    }

    setState(() {
      _continuationSessionEnd = position;
    });

    final expectedWidth = _activeContinuationReference!.width;
    final difference = (measuredWidth - expectedWidth).abs();
    final measurementSystem = context
        .read<MeasurementSettingsProvider>()
        .system;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          difference > 0.15
              ? AppLocalizations.of(context)!.openingReferenceDifference(
                  _formatLength(difference, measurementSystem),
                )
              : AppLocalizations.of(context)!.openingReferenceAligned,
        ),
        backgroundColor:
            difference > 0.15 ? Colors.orange : Colors.green,
      ),
    );
  }

  String _formatLength(
    double meters,
    MeasurementSystem measurementSystem,
  ) {
    if (measurementSystem ==
        MeasurementSystem.metric) {
      return '${_formatDecimal(meters)} m';
    }

    final imperial =
        MeasurementUnits.metersToFeetAndInches(
      meters,
    );

    return '${imperial.feet}′ '
        '${_formatDecimal(imperial.inches)}″';
  }

  String _formatDecimal(
    double value,
  ) {
    var formatted = value.toStringAsFixed(2);

    if (Localizations.localeOf(context)
            .languageCode ==
        'es') {
      formatted = formatted.replaceAll('.', ',');
    }

    return formatted;
  }

  vector.Vector3 _toContinuationLocal(
    vector.Vector3 sessionPoint,
  ) {
    if (!_requiresContinuationCalibration ||
        !_isContinuationCalibrated) {
      return sessionPoint;
    }

    final start = _continuationSessionStart!;
    final end = _continuationSessionEnd!;

    if (widget.resumeRoom != null) {
      final points = widget.resumeRoom!.points;
      if (points.length < 2) return sessionPoint;
      final calibration = ResumeRoomCalibration.tryCreate(
        modelPrevious: points[points.length - 2],
        modelStart: points.last,
        sessionPrevious: ARPoint(x: start.x, y: start.y, z: start.z),
        sessionStart: ARPoint(x: end.x, y: end.y, z: end.z),
      );
      final transformed = calibration?.transform(
        ARPoint(
          x: sessionPoint.x,
          y: sessionPoint.y,
          z: sessionPoint.z,
        ),
      );
      return transformed == null
          ? sessionPoint
          : vector.Vector3(
              transformed.x,
              transformed.y,
              transformed.z,
            );
    }

    final reference = _activeContinuationReference!;
    final sessionOrigin = reference.startEndpoint ==
            ContinuationStartEndpoint.start
        ? start
        : end;
    final tangent = vector.Vector2(
      end.x - start.x,
      end.z - start.z,
    )..normalize();

    final forward = reference.side == OpeningConnectionSide.left
        ? vector.Vector2(-tangent.y, tangent.x)
        : vector.Vector2(tangent.y, -tangent.x);
    final right = vector.Vector2(forward.y, -forward.x);
    final relative = vector.Vector2(
      sessionPoint.x - sessionOrigin.x,
      sessionPoint.z - sessionOrigin.z,
    );

    return vector.Vector3(
      relative.dot(right),
      sessionPoint.y - sessionOrigin.y,
      relative.dot(forward),
    );
  }

  // ================================================================
  // Colores históricos del flujo de aberturas, conservados para no modificar
  // la lógica de proyectos anteriores. La captura visible queda fija en pared.
  // ================================================================

  Color _modeColor(
    AppMode mode,
  ) {
    switch (mode) {
      case AppMode.wall:        return const Color(
          0xFF448AFF,
        );
      case AppMode.door:
        return const Color(
          0xFFFF8A00,
        );

      case AppMode.window:
        return const Color(
          0xFFD500F9,
        );
    }
  }

  // ================================================================
  // CAPTURA DE PUNTOS / ABERTURAS
  // ================================================================

  Future<void> _onCapturePressed(
    ScannerProvider provider,
  ) async {
    if (_placingOpening) return;
    HapticFeedback.lightImpact();

    if (!_isContinuationCalibrated) {
      await _captureContinuationEndpoint();
      return;
    }

    final pos =
        await _getCurrentCameraPosition();

    if (!mounted) return;

    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.invalidCameraPosition,
          ),
          backgroundColor: Colors.orange,
        ),
      );

      return;
    }

    final resolvedPosition =        _toContinuationLocal(pos);

    switch (_currentMode) {
      case AppMode.wall:
        _handleWallPoint(provider, resolvedPosition);
        break;

      case AppMode.door:
      case AppMode.window:
        await _handleFeatureInsertion(          provider,
          _currentMode,
          resolvedPosition,
        );        break;
    }
  }

  void _handleWallPoint(
    ScannerProvider provider,
    vector.Vector3 pos,
  ) {    final ValidationResult result =
        provider.tryAddPoint(
      pos.x,
      pos.y,
      pos.z,
    );

    if (!result.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errorMessage ??
                AppLocalizations.of(context)!.invalidCorner,
          ),
          backgroundColor: Colors.redAccent,
        ),
      );

      return;
    }

    if (result.warningMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.warningMessage!,
          ),
          backgroundColor:
              Colors.amber.shade800,
          duration:
              const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleFeatureInsertion(
    ScannerProvider provider,
    AppMode mode,
    vector.Vector3 position,
  ) async {
    if (provider.currentPointsCount < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.needTwoCornersBeforeOpening,
          ),
          backgroundColor: Colors.orange,
        ),
      );

      return;
    }

    final currentPoint =
        ARPoint(
      x: position.x,
      y: position.y,
      z: position.z,
    );

    final l10n = AppLocalizations.of(context)!;
    final label =
        mode == AppMode.door
            ? l10n.door
            : l10n.window;

    final pendingStart =
        _pendingFeatureStart;

    if (pendingStart == null ||
        _pendingFeatureMode !=
            mode) {
      setState(() {
        _pendingFeatureStart =
            currentPoint;
        _pendingFeatureMode =
            mode;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l10n.featureStartRegistered(label),
            ),
            duration:
                const Duration(
              seconds: 3,
            ),
          ),
        );

      return;
    }

    final featureType =
        mode == AppMode.door
            ? FeatureType.door
            : FeatureType.window;

    // Keep the AR measurement as the initial width, then confirm the wall
    // and vertical dimensions through the same dialog used by Basic Scanner.
    await _placeFeatureByTouch(
      provider, type: featureType,
      measured: WallFeature(id: 'ar-measurement', type: featureType,
          start: pendingStart, end: currentPoint),
    );
  }

  Future<void> _placeFeatureByTouch(
    ScannerProvider provider, {
    required FeatureType type,
    WallFeature? measured,
  }) async {
    final room = provider.currentRoom;
    if (_placingOpening || !_isContinuationCalibrated ||
        room == null || room.points.length < 2) return;
    setState(() {
      _placingOpening = true;
      _pendingFeatureStart = null;
      _pendingFeatureMode = null;
    });
    try {
      final placement = await showOpeningPlacementDialog(
        context: context, room: room, type: type,
        system: context.read<MeasurementSettingsProvider>().system,
        reference: _activeContinuationReference,
        initialFeature: measured,
      );
      if (!mounted || placement == null || !identical(provider.currentRoom, room)) return;
      final result = provider.addFeatureToCurrentRoom(
        type, placement.location, widthMeters: placement.width,
        preferredWallIndex: placement.wallIndex,
        openingHeightMeters: placement.openingHeightMeters,
        sillHeightMeters: placement.sillHeightMeters,
      );
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(result.isValid ? l10n.openingUpdated
              : result.errorMessage ?? l10n.couldNotAttachOpening),
          backgroundColor: result.isValid ? null : Colors.redAccent,
        ));
    } finally {
      if (mounted) setState(() { _placingOpening = false; });
    }
  }

  // ================================================================
  // CIERRE Y PERSISTENCIA DE LA HABITACIÓN
  // ================================================================

  bool _closingRoom = false;

  Future<void> _onCloseRoomPressed(ScannerProvider provider) async {
    if (_closingRoom || _placingOpening) return;
    _closingRoom = true;
    try {
      await _closeRoomOnce(provider);
    } finally {
      _closingRoom = false;
    }
  }

  Future<void> _closeRoomOnce(
    ScannerProvider provider,
  ) async {
    HapticFeedback.mediumImpact();

    final l10n = AppLocalizations.of(context)!;
    final roomName = await showRoomNameDialog(
      context: context,
      initialName: provider.currentRoom?.name ??
          provider.selectedType.localizedName(l10n),
    );
    if (!mounted || roomName == null || roomName.trim().isEmpty) {
      return;
    }
    provider.setCurrentRoomName(roomName);

    final continuation = _activeContinuationReference;
    if (continuation != null) {
      final suggestion = ScanValidator.suggestOrthogonalClosurePoint(
        provider.currentRoom?.points ?? const <ARPoint>[],
      );
      if (suggestion != null) {
        final confirmed =
            await confirmOrthogonalContinuationClosure(context);
        if (!mounted || !confirmed) {
          return;
        }
        final addition = provider.tryAddPoint(
          suggestion.x,
          suggestion.y,
          suggestion.z,
        );
        if (!addition.isValid) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                addition.errorMessage ??
                    AppLocalizations.of(context)!.invalidCorner,
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
      }
    }


    final floorPlanProvider = context.read<FloorPlanProvider>();

    if (continuation != null) {
      final sourceFeature = floorPlanProvider.findFeature(
        roomId: continuation.sourceRoomId,
        featureId: continuation.featureId,
      );

      if (sourceFeature == null || sourceFeature.isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sourceFeature == null
                  ? l10n.referenceOpeningMissing
                  : l10n.openingAlreadyConnected,
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    final closedRoom =
        provider.closeCurrentRoom();

    if (!mounted) return;

    if (closedRoom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            provider.lastCloseError ??
                l10n.closeRoomFailed,
          ),
          backgroundColor:
              Colors.redAccent,
        ),
      );

      return;
    }

    final resumeRoom = widget.resumeRoom;
    final resumesExistingRoom = resumeRoom != null &&
        floorPlanProvider.completedRooms.any(
          (room) => room.id == resumeRoom.id,
        );
    final saved = resumesExistingRoom
        ? await floorPlanProvider.replaceCompletedRoom(
            closedRoom,
            expectedOpenRoom: resumeRoom,
          )
        : continuation == null
            ? await floorPlanProvider.addCompletedRoom(
                closedRoom, preservePlacement: resumeRoom != null)
            : await floorPlanProvider.addCompletedRoomFromContinuation(
            room: closedRoom,
            reference: continuation,
          );

    if (!saved) {
      provider.restoreCurrentRoom(closedRoom.copyWith(isClosed: false));
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.closeRoomFailed,
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    _draftSaveTimer?.cancel();
    await _scanDraftService.clear(widget.projectUuid);
    _lastDraftFingerprint = null;

    if (!mounted) return;

    final action = await showRoomCompletionDialog(context);
    if (!mounted || action == null) return;

    if (action == RoomCompletionAction.viewFullPlan) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const FloorPlanViewerScreen(),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const FloorPlanViewerScreen(
            selectContinuationOpening: true,
          ),
        ),
      );
    }
  }

  // ================================================================
  // PLANO
  // ================================================================

  void _openFloorPlan() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const FloorPlanViewerScreen(),
      ),
    );
  }
}
