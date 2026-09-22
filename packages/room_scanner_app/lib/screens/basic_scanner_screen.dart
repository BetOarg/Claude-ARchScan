import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import '../services/continuation_display_frame.dart';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/validation_error_localization.dart';
import '../l10n/room_type_localization.dart';
import '../providers/floor_plan_provider.dart';
import '../providers/measurement_settings_provider.dart';
import '../providers/scanner_provider.dart';
import '../scanner/adapters/basic_scanner_adapter.dart';
import '../scanner/models/scanner_mode.dart';
import '../scanner/models/scanner_point.dart';
import '../scanner/services/scanner_permission_service.dart';
import '../services/scan_draft_service.dart';
import '../widgets/room_name_dialog.dart';
import '../widgets/opening_placement_dialog.dart';
import '../widgets/room_completion_dialog.dart';
import '../widgets/scanner_guide_painter.dart';
import '../widgets/scanner_plan_opening_hint.dart';
import 'floor_plan_viewer_screen.dart';

enum BasicAppMode {
  wall,
  door,
  window,
}

enum _CameraInitializationFailure {
  permissionDenied,
  unavailable,
}

class _CameraInitializationException implements Exception {
  const _CameraInitializationException(this.failure);

  final _CameraInitializationFailure failure;
}

class BasicScannerScreen extends StatefulWidget {
  final String projectUuid;
  final String projectName;
  final ScanContinuationReference? continuationReference;

  /// Ambiente abierto existente que debe continuar sin duplicarse.
  final RoomModel? resumeRoom;

  const BasicScannerScreen({
    super.key,
    required this.projectUuid,
    required this.projectName,
    this.continuationReference,
    this.resumeRoom,
  });

  @override
  State<BasicScannerScreen> createState() =>
      _BasicScannerScreenState();
}

class _BasicScannerScreenState
    extends State<BasicScannerScreen>
    with WidgetsBindingObserver {
  static const ScanDraftService _scanDraftService = ScanDraftService();
  static const Duration _cameraInitializationTimeout =
      Duration(seconds: 12);
  static const Duration _automaticRetryDelay =
      Duration(milliseconds: 800);

  CameraController? _cameraController;

  final BasicScannerAdapter _scannerAdapter =
      BasicScannerAdapter();

  final ScannerPermissionService
      _permissionService =
      const ScannerPermissionService();

  final BasicAppMode _currentMode =
      BasicAppMode.wall;
  bool _initializing = true;
  bool _cameraReady = false;
  bool _processing = false;
  bool _changingLifecycle = false;
  bool _cameraResumePending = false;
  bool _shouldResumeCamera = false;
  int _cameraLifecycleGeneration = 0;
  bool _initializationInProgress = false;
  bool _scannerInitialized = false;
  bool _roomStarted = false;
  ScanContinuationReference? _activeContinuationReference;
  RoomModel? _activeResumeRoom;
  ScannerProvider? _draftProvider;
  Timer? _draftSaveTimer;
  String? _lastDraftFingerprint;

  double _lastAngleDegrees = 90.0;

  String? _initializationError;

  @override
  void initState() {
    super.initState();

    _activeContinuationReference = widget.continuationReference;
    _activeResumeRoom = widget.resumeRoom;
    _shouldResumeCamera =
        WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed;

    WidgetsBinding.instance
        .addObserver(this);

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      _initialize();
    });
  }

  Future<void> _initialize({
    bool allowAutomaticRetry = true,
  }) async {
    if (_initializationInProgress ||
        !_shouldResumeCamera) {
      return;
    }

    final lifecycleGeneration =
        _cameraLifecycleGeneration;
    _initializationInProgress = true;

    if (mounted) {
      setState(() {
        _initializing = true;
        _cameraReady = false;
        _initializationError = null;
      });
    }

    CameraController? controller;

    try {
      final permissionGranted =
          await _permissionService
              .requestForMode(
        ScannerMode.basic,
      );

      if (!permissionGranted) {
        throw const _CameraInitializationException(
          _CameraInitializationFailure.permissionDenied,
        );
      }

      final maximumAttempts =
          allowAutomaticRetry ? 2 : 1;
      Object? lastError;

      for (var attempt = 0;
          attempt < maximumAttempts;
          attempt++) {
        try {
          controller =
              await _createInitializedCameraController();
          lastError = null;
          break;
        } catch (error) {
          lastError = error;

          if (attempt + 1 < maximumAttempts) {
            await Future<void>.delayed(
              _automaticRetryDelay,
            );
          }
        }
      }

      if (controller == null) {
        if (lastError != null) {
          throw lastError;
        }

        throw const _CameraInitializationException(
          _CameraInitializationFailure.unavailable,
        );
      }

      if (!mounted ||
          !_shouldResumeCamera ||
          lifecycleGeneration !=
              _cameraLifecycleGeneration) {
        await controller.dispose();
        return;
      }

      if (!_scannerInitialized) {
        await _scannerAdapter.initialize();
        _scannerInitialized = true;
      }

      if (!mounted ||
          !_shouldResumeCamera ||
          lifecycleGeneration !=
              _cameraLifecycleGeneration) {
        await controller.dispose();
        return;
      }

      final scannerProvider =
          context.read<ScannerProvider>();

      if (!_roomStarted) {
        await _restoreOrStartRoom(scannerProvider);
        _attachDraftListener(scannerProvider);
        _roomStarted = true;
      }

      if (!mounted ||
          !_shouldResumeCamera ||
          lifecycleGeneration !=
              _cameraLifecycleGeneration) {
        await controller.dispose();
        return;
      }

      scannerProvider.updateTrackingStatus(true);

      setState(() {
        _cameraController =
            controller;
        _cameraReady = true;
        _initializing = false;
        _initializationError = null;
      });
    } catch (error) {
      await controller?.dispose();

      if (!mounted ||
          !_shouldResumeCamera ||
          lifecycleGeneration !=
              _cameraLifecycleGeneration) {
        return;
      }

      setState(() {
        _initializing = false;
        _cameraReady = false;
        _initializationError =
            _cameraErrorMessage(error);
      });

      context
          .read<ScannerProvider>()
          .updateTrackingStatus(false);
    } finally {
      _initializationInProgress = false;

      if (mounted &&
          _shouldResumeCamera &&
          _cameraController == null &&
          lifecycleGeneration !=
              _cameraLifecycleGeneration) {
        unawaited(_resumeCamera());
      }
    }
  }

  Future<void> _restoreOrStartRoom(ScannerProvider provider) async {
    final resumeRoom = _activeResumeRoom;
    if (resumeRoom != null) {
      provider.restoreCurrentRoom(resumeRoom);
      _scannerAdapter.seedPath(
        resumeRoom.points
            .map(
              (point) => ScannerPoint(
                x: point.x,
                y: point.y,
                z: point.z,
                source: PointSource.manual,
              ),
            )
            .toList(),
      );
      return;
    }

    final draft = await _scanDraftService.load(widget.projectUuid);
    if (!mounted) return;

    if (draft == null) {
      _startScannerRoom(provider);
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
      _startScannerRoom(provider);
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
      _activeResumeRoom = draft.resumeRoom;
      provider.restoreCurrentRoom(draft.room);
      final history = draft.basicHistory.isNotEmpty
          ? draft.basicHistory
          : draft.room.points;
      _scannerAdapter.seedPath(
        history
            .map(
              (point) => ScannerPoint(
                x: point.x,
                y: point.y,
                z: point.z,
                source: PointSource.manual,
              ),
            )
            .toList(),
      );
      return;
    }

    await _scanDraftService.clear(widget.projectUuid);
    _lastDraftFingerprint = null;
    _startScannerRoom(provider);
  }

  void _attachDraftListener(ScannerProvider provider) {
    _draftProvider?.removeListener(_onScannerDraftChanged);
    _draftProvider = provider;
    provider.addListener(_onScannerDraftChanged);
    _onScannerDraftChanged();
  }

  List<ARPoint> _basicHistory() => _scannerAdapter.history
      .map(
        (point) => ARPoint(x: point.x, y: point.y, z: point.z),
      )
      .toList();

  void _onScannerDraftChanged() {
    final room = _draftProvider?.currentRoom;
    if (room == null || (room.points.isEmpty && room.features.isEmpty)) {
      return;
    }

    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 250), () {
      final history = _basicHistory();
      final fingerprint = jsonEncode(<String, dynamic>{
        'room': room.toJson(),
        'history': history.map((point) => point.toJson()).toList(),
        'continuation': _activeContinuationReference?.featureId,
      });
      if (fingerprint == _lastDraftFingerprint) return;

      _scanDraftService.save(
        projectUuid: widget.projectUuid,
        room: room,
        resumeRoom: _activeResumeRoom,
        continuationReference: _activeContinuationReference,
        basicHistory: history,
      ).then((_) {
        _lastDraftFingerprint = fingerprint;
      }).catchError((Object error) {
        _lastDraftFingerprint = null;
        debugPrint('No se pudo guardar el borrador: $error');
      });
    });
  }

  Future<void> _flushDraft() async {
    _draftSaveTimer?.cancel();
    final room = _draftProvider?.currentRoom;
    if (room == null || (room.points.isEmpty && room.features.isEmpty)) return;

    await _scanDraftService.save(
      projectUuid: widget.projectUuid,
      room: room,
      resumeRoom: _activeResumeRoom,
      continuationReference: _activeContinuationReference,
      basicHistory: _basicHistory(),
    );
  }

  Future<CameraController>
      _createInitializedCameraController() async {
    final cameras = await availableCameras().timeout(
      _cameraInitializationTimeout,
    );

    if (cameras.isEmpty) {
      throw const _CameraInitializationException(
        _CameraInitializationFailure.unavailable,
      );
    }

    final selectedCamera =
        cameras.firstWhere(
      (camera) =>
          camera.lensDirection ==
          CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller =
        CameraController(
      selectedCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await controller.initialize().timeout(
        _cameraInitializationTimeout,
      );
      return controller;
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
  }

  String _cameraErrorMessage(
    Object? error,
  ) {
    final l10n = AppLocalizations.of(context)!;

    if (error is TimeoutException) {
      return l10n.cameraTimeoutMessage;
    }

    if (error is _CameraInitializationException) {
      switch (error.failure) {
        case _CameraInitializationFailure.permissionDenied:
          return l10n.cameraPermissionRequired;
        case _CameraInitializationFailure.unavailable:
          return l10n.cameraUnavailable;
      }
    }

    return l10n.cameraStartFailed;
  }

  void _startScannerRoom(
    ScannerProvider provider,
  ) {
    final continuation =
        _activeContinuationReference;

    if (continuation == null) {
      provider.startNewRoom();
      return;
    }

    final width = continuation.width;
    final tangentSign =
        continuation.side == OpeningConnectionSide.left
            ? 1.0
            : -1.0;
    final otherX = continuation.startEndpoint ==
            ContinuationStartEndpoint.start
        ? tangentSign * width
        : -tangentSign * width;

    final other = ARPoint(
      x: otherX,
      y: 0.0,
      z: 0.0,
    );
    final origin = ARPoint(
      x: 0.0,
      y: 0.0,
      z: 0.0,
    );
    final sharedFeature = WallFeature(
      id: continuation.featureId,
      type: continuation.featureType,
      start: other,
      end: origin,
    );

    provider.startNewRoom(
      initialPoints: <ARPoint>[origin],
      initialFeatures: <WallFeature>[sharedFeature],
    );

    _scannerAdapter.seedPath(
      <ScannerPoint>[
        ScannerPoint(
          x: origin.x,
          y: origin.y,
          z: origin.z,
          source: PointSource.manual,
        ),
      ],
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
      if (!_shouldResumeCamera) {
        return;
      }

      _flushDraft();
      _shouldResumeCamera = false;
      _cameraResumePending = false;
      _cameraLifecycleGeneration++;
      unawaited(_pauseCamera());
      return;
    }

    if (state == AppLifecycleState.resumed) {
      if (_shouldResumeCamera) {
        return;
      }

      _shouldResumeCamera = true;
      _cameraResumePending = true;
      _cameraLifecycleGeneration++;
      unawaited(_resumeCamera());
    }
  }

  Future<void> _pauseCamera() async {
    if (_changingLifecycle) {
      return;
    }

    _changingLifecycle = true;

    final controller =
        _cameraController;

    _cameraController = null;

    if (mounted) {
      context
          .read<ScannerProvider>()
          .updateTrackingStatus(false);

      setState(() {
        _cameraReady = false;
        _initializing = true;
      });
    }

    try {
      await controller?.dispose();
    } finally {
      _changingLifecycle = false;

      if (mounted && _shouldResumeCamera) {
        _cameraResumePending = true;
        unawaited(_resumeCamera());
      }
    }
  }
  Future<void> _resumeCamera() async {
    if (!_shouldResumeCamera) {
      _cameraResumePending = false;
      return;
    }

    if (_cameraController != null) {
      _cameraResumePending = false;
      return;
    }

    if (_changingLifecycle || _initializationInProgress) {
      _cameraResumePending = true;
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (mounted && _shouldResumeCamera && _cameraController == null) {
          unawaited(_resumeCamera());
        }
      });
      return;
    }

    _cameraResumePending = false;

    final lifecycleGeneration =
        _cameraLifecycleGeneration;
    _changingLifecycle = true;

    try {
      final controller =
          await _createInitializedCameraController();

      if (!mounted ||
          !_shouldResumeCamera ||
          lifecycleGeneration !=
              _cameraLifecycleGeneration) {
        await controller.dispose();
        return;
      }

      _cameraController =
          controller;

      context
          .read<ScannerProvider>()
          .updateTrackingStatus(true);

      setState(() {
        _cameraReady = true;
        _initializing = false;
        _initializationError = null;
      });
    } catch (error) {
      if (!mounted ||
          !_shouldResumeCamera ||
          lifecycleGeneration !=
              _cameraLifecycleGeneration) {
        return;
      }

      setState(() {
        _cameraReady = false;
        _initializing = false;
        _initializationError =
            AppLocalizations.of(context)!
                .cameraResumeFailed(
              error.toString(),
            );
      });

      context
          .read<ScannerProvider>()
          .updateTrackingStatus(false);
    } finally {
      _changingLifecycle = false;
      if (mounted &&
          _cameraResumePending &&
          _shouldResumeCamera &&
          _cameraController == null) {
        unawaited(_resumeCamera());
      }
    }
  }

  @override
  void dispose() {
    _flushDraft();
    _draftSaveTimer?.cancel();
    _draftProvider?.removeListener(_onScannerDraftChanged);
    _shouldResumeCamera = false;
    _cameraLifecycleGeneration++;

    WidgetsBinding.instance
        .removeObserver(this);

    unawaited(_scannerAdapter.dispose());
    final cameraController = _cameraController;
    _cameraController = null;
    if (cameraController != null) {
      unawaited(cameraController.dispose());
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider =
        context.watch<ScannerProvider>();
    final completedRooms = context
        .watch<FloorPlanProvider>()
        .completedRooms;

    if (_initializing) {
      final l10n =
          AppLocalizations.of(context)!;

      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                l10n.preparingCamera,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.basicScanner,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_cameraReady) {
      return _buildInitializationError();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [          _buildCameraPreview(),          _buildScannerOverlay(            provider,
            completedRooms,
          ),          _buildTopHud(provider),
          _buildBottomPanel(provider),
        ],
      ),
    );
  }

  Widget _buildInitializationError() {
    final l10n =
        AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title:
            Text(l10n.basicScanner),
      ),
      body: Center(
        child: Padding(
          padding:
              const EdgeInsets.all(24),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                color: Colors.orange,
                size: 64,
              ),
              const SizedBox(
                height: 20,              ),              Text(
                l10n.cameraStartFailed,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight:
                      FontWeight.bold,
                ),
                textAlign:
                    TextAlign.center,
              ),
              const SizedBox(
                height: 12,
              ),
              Text(
                _initializationError ??
                    l10n.unknownError,
                style:
                    const TextStyle(
                  color: Colors.white70,
                ),
                textAlign:
                    TextAlign.center,
              ),
              const SizedBox(
                height: 24,
              ),
              ElevatedButton.icon(
                onPressed: () =>
                    _initialize(
                  allowAutomaticRetry: false,
                ),
                icon: const Icon(
                  Icons.refresh,
                ),
                label: Text(
                  l10n.retryCamera,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final controller =
        _cameraController;

    if (controller == null ||
        !controller.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
      );
    }

    return SizedBox.expand(
      child: FittedBox(        fit: BoxFit.cover,
        child: SizedBox(
          width:
              controller.value.previewSize?.height ??
                  MediaQuery.of(context)
                      .size                      .width,
          height:              controller.value.previewSize?.width ??
                  MediaQuery.of(context)                      .size                      .height,          child: CameraPreview(            controller,
          ),
        ),
      ),
    );
  }
  Widget _buildScannerOverlay(
    ScannerProvider provider,
    List<RoomModel> completedRooms,
  ) {
    final room = provider.currentRoom;
    final points =
        room?.points ?? const <ARPoint>[];    final features =        room?.features ?? const <WallFeature>[];

    return IgnorePointer(
      child: CustomPaint(
        painter:
            ScannerGuidePainter(
          points: points,
          features: features,
          previousRooms:
              _activeContinuationReference == null &&
                      _activeResumeRoom == null
                  ? const <RoomModel>[]
                  : completedRooms,
          continuationReference:
              _activeContinuationReference,
        ),
        size: Size.infinite,
      ),
    );
  }
  Widget _buildTopHud(    ScannerProvider provider,  ) {
    final l10n =
        AppLocalizations.of(context)!;

    final count =
        provider.currentPointsCount;

    final continuation =
        _activeContinuationReference;

    return Positioned(
      top:
          MediaQuery.of(context)
                  .padding
                  .top +
              10,
      left: 12,
      right: 12,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _hudCard(
                  icon:
                      Icons.architecture,
                  title:
                      _localizedRoomName(
                    provider,
                    l10n,
                  ),
                  subtitle: _scanRecommendation(count, l10n),
                  onTap: () =>
                      _showCustomRoomNameDialog(
                    provider,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _hudIconButton(
                icon:
                    Icons.map_outlined,
                tooltip:
                    l10n.viewPlan,
                onPressed:
                    _openFloorPlan,
              ),
            ],
          ),
          const SizedBox(
            height: 8,
          ),
          if (continuation != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8A00).withValues(
                  alpha: 0.88,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.add_road_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.continuationFromOpening,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
            decoration:
                BoxDecoration(
              color:
                  Colors.black.withValues(
                alpha: 0.78,
              ),
              borderRadius:
                  BorderRadius.circular(
                14,
              ),
              border: Border.all(
                color:
                    Colors.white24,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  continuation != null
                      ? Icons.navigation_outlined
                      : Icons.info_outline,
                  color:
                      Colors.white70,
                  size: 18,
                ),
                const SizedBox(
                  width: 9,
                ),
                Expanded(
                  child: Text(
                    count == 0
                        ? continuation != null
                            ? l10n.continuationFirstCornerInstruction
                            : l10n.markRoomStartingPoint
                        : l10n.measureNextCornerInstruction,
                    style:
                        const TextStyle(
                      color:
                          Colors.white,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
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

  Widget _hudCard({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(14),
        child: Container(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          decoration:
              BoxDecoration(
            color:
                Colors.black.withValues(
              alpha: 0.78,
            ),
            borderRadius:
                BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white24,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration:
                    BoxDecoration(
                  color: Colors.blueAccent
                      .withValues(
                    alpha: 0.25,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    10,
                  ),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style:
                          const TextStyle(
                        color: Colors.white,
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow:
                          TextOverflow.ellipsis,
                    ),
                    const SizedBox(
                      height: 2,
                    ),
                    Text(
                      subtitle,
                      style:
                          const TextStyle(                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.edit_outlined,
                  color: Colors.white60,
                  size: 19,
                ),
            ],
          ),
        ),
      ),
    );
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

  Future<void> _showRoomTypeSelector(
    ScannerProvider provider,
  ) async {
    final l10n =
        AppLocalizations.of(context)!;

    final selected =
        await showModalBottomSheet<            RoomType>(
      context: context,
      isScrollControlled: true,
      builder: (
        bottomSheetContext,
      ) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              24,
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(                  l10n.roomType,
                  style:                      TextStyle(
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 8,
                ),
                Flexible(
                  child:
                      ListView.builder(
                    shrinkWrap: true,
                    itemCount:
                        RoomType.values.length,
                    itemBuilder:
                        (
                      context,
                      index,
                    ) {
                      final type =
                          RoomType.values[
                            index
                          ];

                      final selected =
                          provider.selectedType ==
                              type;

                      return ListTile(
                        leading: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color:
                              selected
                                  ? Colors.blueAccent
                                  : null,
                        ),
                        title: Text(
                          type.localizedName(l10n),
                        ),
                        onTap: () {
                          Navigator.pop(
                            bottomSheetContext,
                            type,
                          );
                        },
                      );
                    },                  ),                ),
              ],
            ),
          ),        );
      },
    );
    if (selected == null ||        !mounted) {
      return;
    }

    provider.setRoomType(
      selected,
    );
  }
  Widget _hudIconButton({    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration:
          BoxDecoration(
        color:
            Colors.black.withValues(
          alpha: 0.78,
        ),
        borderRadius:
            BorderRadius.circular(
          14,
        ),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildBottomPanel(
    ScannerProvider provider,
  ) {
    final count =        provider.currentPointsCount;

    return Positioned(
      left: 10,
      right: 10,
      bottom: 6,
      child: SafeArea(
        top: false,
        child: Container(
          padding:
              const EdgeInsets.fromLTRB(
            8,
            8,
            8,
            8,
          ),
          decoration:
              BoxDecoration(
            color:
                Colors.black.withValues(
              alpha: 0.88,
            ),
            borderRadius:
                BorderRadius.circular(
              16,
            ),
            border: Border.all(
              color: Colors.white24,
            ),
          ),
          child: Column(
            children: [
              const ScannerPlanOpeningHint(
                scannerKey: ValueKey('basic-plan-opening-hint'),
              ),
              const SizedBox(
                height: 6,
              ),
              Row(
                children: [
                  _buildUndoButton(
                    provider,
                  ),
                  IconButton(
                    tooltip: AppLocalizations.of(context)!.redoScanEdit,
                    onPressed: !_processing && provider.canRedo
                        ? () {
                            provider.redoEdit();
                            _syncAdapterWithRoom(provider);
                          }
                        : null,
                    icon: const Icon(Icons.redo),
                    color: Colors.white,
                  ),
                  const SizedBox(                    width: 6,
                  ),
                  Expanded(
                    child:
                        _buildMainCaptureButton(
                      provider,
                    ),
                  ),
                  const SizedBox(
                    width: 6,
                  ),
                  _buildFinishButton(
                    provider,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  // La captura visible queda fija en pared. Los colores de abertura se
  // conservan con la lógica histórica, fuera de la interfaz de escaneo.
  Color _modeColor(
    BasicAppMode mode,
  ) {
    switch (mode) {
      case BasicAppMode.wall:
        return const Color(
          0xFF448AFF,
        );

      case BasicAppMode.door:
        return const Color(
          0xFFFF8A00,
        );

      case BasicAppMode.window:
        return const Color(
          0xFFD500F9,
        );
    }
  }

  Widget _buildProgressIndicator(
    int count,
  ) {
    final l10n =
        AppLocalizations.of(context)!;

    return Row(
      children: [
        const Icon(
          Icons.polyline,
          color: Colors.white70,
          size: 18,
        ),
        const SizedBox(
          width: 8,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                count == 0
                    ? l10n.traceStarted
                    : l10n.cornerRegistered(
                        count,
                      ),
                style:
                    const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
              const SizedBox(
                height: 3,
              ),
              Text(
                count < 3
                    ? l10n.needThreeCornersToClose
                    : l10n.canContinueOrClose,
                style:
                    const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUndoButton(
    ScannerProvider provider,
  ) => _buildHistoryUndoButton(provider);

  void _syncAdapterWithRoom(ScannerProvider provider) {
    _scannerAdapter.seedPath([
      for (final point in provider.currentRoom?.points ?? <ARPoint>[])
        ScannerPoint(x: point.x, y: point.y, z: point.z, source: PointSource.manual),
    ]);
  }

  Widget _buildHistoryUndoButton(
    ScannerProvider provider,
  ) {
    final l10n =
        AppLocalizations.of(context)!;

    final enabled = !_processing && provider.canUndo;

    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        tooltip: l10n.undoScanEdit,
        onPressed: enabled
            ? () {
                HapticFeedback
                    .lightImpact();

                provider.undoEdit();
                _syncAdapterWithRoom(provider);
              }
            : null,
        style:
            IconButton.styleFrom(
          backgroundColor:
              Colors.white10,
          foregroundColor:
              Colors.white,
          disabledForegroundColor:
              Colors.white24,
        ),
        icon: const Icon(
          Icons.undo,
          size: 21,
        ),
      ),
    );
  }

  Widget _buildMainCaptureButton(
    ScannerProvider provider,
  ) {
    final l10n =
        AppLocalizations.of(context)!;

    final count =
        provider.currentPointsCount;

    final String label;

    if (_processing) {
      label = l10n.calculating;
    } else if (count == 0) {
      label = _activeContinuationReference == null
          ? l10n.markStart
          : l10n.measureFirstCorner;
    } else if (_currentMode ==
        BasicAppMode.wall) {
      label = l10n.measureNextCorner;
    } else if (_currentMode ==
        BasicAppMode.door) {
      label = l10n.placeDoor;
    } else {
      label = l10n.placeWindow;
    }

    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: _processing
            ? null
            : () => _capturePressed(
                  provider,
                ),
        icon: Icon(
          count == 0
              ? Icons.location_on
              : Icons.straighten,
          size: 18,
        ),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style:
                const TextStyle(
              fontWeight:
                  FontWeight.bold,
              fontSize: 11,
            ),
          ),        ),
        style:
            ElevatedButton.styleFrom(
          backgroundColor:
              _modeColor(
            _currentMode,
          ),
          foregroundColor:
              Colors.white,
          disabledBackgroundColor:
              Colors.blueGrey,
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFinishButton(
    ScannerProvider provider,
  ) {
    final enabled =
        provider.currentPointsCount >= 3;

    return SizedBox(
      width: 48,
      height: 48,      child: IconButton(
        tooltip: AppLocalizations.of(context)!.closeRoom,
        onPressed: enabled && !_processing
            ? () => _closeRoom(
                  provider,
                )
            : null,
        style:
            IconButton.styleFrom(
          backgroundColor: enabled
              ? Colors.green
              : Colors.white10,
          foregroundColor:
              Colors.white,
          disabledForegroundColor:
              Colors.white24,
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              12,
            ),
          ),
        ),
        icon: const Icon(
          Icons.check,
          size: 22,
        ),
      ),
    );
  }
  Future<void> _capturePressed(
    ScannerProvider provider,
  ) async {
    final l10n =
        AppLocalizations.of(context)!;

    if (_processing) {
      return;    }
    HapticFeedback.lightImpact();

    if (provider.currentPointsCount == 0) {
      if (_activeContinuationReference != null) {
        if (_currentMode != BasicAppMode.wall) {
          _showMessage(
            l10n.measureFirstCornerBeforeFeatures,
          );
          return;
        }

        await _captureWallPoint(
          provider,
        );
        return;
      }

      final point =
          _scannerAdapter
              .captureInitialPoint();

      final result =
          provider.tryAddPoint(
        point.x,
        point.y,
        point.z,
      );

      if (!result.isValid) {
        _scannerAdapter
            .removeLastPoint();

        _showValidationError(
          validationErrorMessage(result, l10n, fallback: l10n.couldNotAddStart),
        );
        return;
      }

      _showMessage(
        l10n.startMarked,
      );

      return;
    }

    if (_currentMode !=
        BasicAppMode.wall) {      await _captureFeature(
        provider,
      );
      return;
    }
    await _captureWallPoint(      provider,
    );  }

  Future<void> _captureWallPoint(
    ScannerProvider provider,
  ) async {
    final l10n =
        AppLocalizations.of(context)!;

    final isFirstContinuationCorner =
        _activeContinuationReference != null &&
            provider.currentPointsCount == 0;

    final measurement =
        await _showMeasurementDialog(      nextCorner:
          provider.currentPointsCount + 1,
    );

    if (measurement == null) {
      return;
    }

    setState(() {
      _processing = true;
    });

    try {
      _scannerAdapter
          .setNextMeasurement(
        distanceMeters:
            measurement.distance,
        angleDegrees:
            ContinuationDisplayFrame(_activeContinuationReference).toLocalAngle(measurement.angle),
      );

      final candidate =
          _scannerAdapter
              .previewNextPoint();

      if (candidate == null) {
        _showMessage(
          l10n.couldNotCalculateCorner,
        );
        return;
      }

      final closingDistance =
          _smartClosingDistance(
        provider,
        candidate,
      );

      if (closingDistance != null) {
        final shouldClose =
            await _confirmSmartClose(
          closingDistance,
        );

        if (!mounted) {
          return;
        }

        if (shouldClose) {
          _scannerAdapter
              .cancelPendingMeasurement();

          await _closeRoom(
            provider,
          );
          return;
        }
      }

      final result =
          provider.tryAddPoint(
        candidate.x,
        candidate.y,
        candidate.z,
      );

      if (!result.isValid) {
        _scannerAdapter
            .cancelPendingMeasurement();

        _showValidationError(
          validationErrorMessage(result, l10n, fallback: l10n.invalidCorner),
        );

        return;
      }

      _scannerAdapter
          .commitPendingPoint(
        candidate,
      );

      if (isFirstContinuationCorner) {
        _showMessage(
          l10n.firstCornerRegistered,
        );
      }

      if (closingDistance == null &&
          result.warningMessage != null) {
        _showMessage(
          result.warningMessage!,
        );
      }
    } catch (error) {
      _scannerAdapter
          .cancelPendingMeasurement();

      _showMessage(
        l10n.measurementRegistrationFailed(
          error.toString(),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }

  double? _smartClosingDistance(
    ScannerProvider provider,
    ScannerPoint candidate,
  ) {
    final points =
        provider.currentRoom?.points;

    if (points == null ||
        points.length < 3) {
      return null;
    }

    final first = points.first;
    final deltaX =
        candidate.x - first.x;
    final deltaZ =
        candidate.z - first.z;
    final distance =
        math.sqrt(
      deltaX * deltaX +
          deltaZ * deltaZ,
    );

    return distance <=
            ScanValidator.autoCloseThreshold
        ? distance
        : null;
  }

  Future<bool> _confirmSmartClose(
    double distance,
  ) async {
    final l10n =
        AppLocalizations.of(context)!;
    final confirmed =
        await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          AlertDialog(
        title: Text(
          l10n.closeRoom,
        ),
        content: Text(
          l10n.smartCloseMessage(
            distance.toStringAsFixed(2),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
              dialogContext,
              false,
            ),
            child: Text(
              l10n.continueMeasuring,
            ),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(
              dialogContext,
              true,
            ),
            icon: const Icon(
              Icons.check_circle_outline,
            ),
            label: Text(
              l10n.closeRoom,
            ),
          ),
        ],      ),
    );    return confirmed ?? false;
  }

  Future<void> _captureFeature(ScannerProvider provider) async {
    final room = provider.currentRoom;
    if (room == null || room.points.length < 2) return;
    final type = _currentMode == BasicAppMode.door ? FeatureType.door : FeatureType.window;
    setState(() { _processing = true; });
    try {
      final placement = await showOpeningPlacementDialog(
        context: context, room: room, type: type,
        system: context.read<MeasurementSettingsProvider>().system,
        reference: _activeContinuationReference,
      );
      if (!mounted || placement == null || !identical(provider.currentRoom, room)) return;
      final result = provider.addFeatureToCurrentRoom(
        type, placement.location, widthMeters: placement.width,
        preferredWallIndex: placement.wallIndex,
        openingHeightMeters: placement.openingHeightMeters,
        sillHeightMeters: placement.sillHeightMeters,
      );
      if (!result.isValid) {
        _showValidationError(result.errorMessage ??
            AppLocalizations.of(context)!.couldNotAttachOpening);
      }
    } finally {
      if (mounted) setState(() { _processing = false; });
    }
  }


  Future<_BasicMeasurement?>
      _showMeasurementDialog({    required int nextCorner,
    bool featureMode = false,
  }) async {
    final l10n =
        AppLocalizations.of(context)!;

    final distanceController =
        TextEditingController();
    final distanceFeetController =
        TextEditingController();
    final distanceInchesController =
        TextEditingController();

    final angleController = TextEditingController(
      text: _formatAngle(_lastAngleDegrees),    );

    final featureWidthController =        TextEditingController(
      text:
          _currentMode ==
                  BasicAppMode.door
              ? '0,80'
              : '1,00',
    );
    final initialFeatureWidth =
        _currentMode == BasicAppMode.door
            ? 0.80
            : 1.00;
    final initialImperialWidth =        MeasurementUnits.metersToFeetAndInches(
      initialFeatureWidth,
    );
    final featureFeetController =
        TextEditingController(
      text: initialImperialWidth.feet.toString(),
    );
    final featureInchesController =
        TextEditingController(
      text: _formatUnitNumber(
        initialImperialWidth.inches,
      ),
    );
    final selectedMeasurementSystem =
        context
            .read<MeasurementSettingsProvider>()
            .system;
    double? distanceError;
    double? angleError;
    double? featureWidthError;
    final manualInstruction = nextCorner <= 2
        ? l10n.manualFirstWallInstruction
        : l10n.manualNextWallInstruction;

    return showDialog<_BasicMeasurement>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder:
              (context, setDialogState) {
            final size = MediaQuery.sizeOf(dialogContext);
            return AlertDialog(
              scrollable: true,
              insetPadding: EdgeInsets.symmetric(
                horizontal: size.width < 400 ? 10 : 32,
                vertical: 8,
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              actionsOverflowAlignment: OverflowBarAlignment.end,
              actionsOverflowButtonSpacing: 6,
              title: Row(
                children: [
                  const Icon(
                    Icons.straighten,
                    color:
                        Colors.blueAccent,
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child: Text(
                      featureMode
                          ? l10n.placeElement
                          : l10n.measureCorner,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ],
              ),
              content:
                  SingleChildScrollView(
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration:
                          BoxDecoration(
                        color: Colors
                            .blueAccent
                            .withValues(
                          alpha: 0.08,
                        ),
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                      ),
                      child: Text(
                        featureMode
                            ? l10n.featureDistanceInstruction
                            : manualInstruction,
                        style:
                            const TextStyle(
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.straighten, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          selectedMeasurementSystem == MeasurementSystem.metric
                              ? l10n.metricSystem
                              : l10n.imperialSystem,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildLengthFields(
                            system: selectedMeasurementSystem,
                            metricController: distanceController,
                            feetController: distanceFeetController,
                            inchesController: distanceInchesController,
                            label: l10n.distance,
                            metricHint: l10n.distanceExample,
                            errorText: distanceError != null
                                ? l10n.enterPositiveDistance
                                : null,
                            autofocus: true,
                            compact: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: angleController,
                            onChanged: (_) {
                              setDialogState(() {
                                angleError = null;
                              });
                            },
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: InputDecoration(
          isDense: true,
                              labelText: l10n.direction,
                              hintText: l10n.directionExample,
                              suffixText: '°',
                              prefixIcon: const Icon(Icons.explore),
                              errorText: angleError != null
                                  ? l10n.enterValidDirection
                                  : null,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (featureMode) ...[
                      const SizedBox(
                        height: 16,
                      ),
                      _buildLengthFields(
                        system: selectedMeasurementSystem,
                        metricController: featureWidthController,
                        feetController: featureFeetController,
                        inchesController: featureInchesController,
                        label: _currentMode == BasicAppMode.door
                            ? l10n.doorWidth
                            : l10n.windowWidth,
                        metricHint: l10n.widthExample,
                        errorText: featureWidthError != null
                            ? l10n.enterMinimumOpeningWidth
                            : null,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      l10n.quickDirection,
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _angleChip(
                                l10n.front,
                                Icons.arrow_upward,
                                0,
                                angleController,
                                setDialogState,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _angleChip(
                                l10n.right,
                                Icons.arrow_forward,
                                90,
                                angleController,
                                setDialogState,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: _angleChip(
                                l10n.back,
                                Icons.arrow_downward,
                                180,
                                angleController,
                                setDialogState,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _angleChip(
                                l10n.left,
                                Icons.arrow_back,
                                270,
                                angleController,
                                setDialogState,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(                          child: OutlinedButton(
                            onPressed: () => _adjustAngle(
                              angleController,
                              -5.0,
                              setDialogState,
                            ),
                            child: const Text('-5°'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _adjustAngle(
                              angleController,
                              -1.0,
                              setDialogState,                            ),
                            child: const Text('-1°'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _adjustAngle(
                              angleController,
                              1.0,
                              setDialogState,
                            ),
                            child: const Text('+1°'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _adjustAngle(
                              angleController,
                              5.0,
                              setDialogState,
                            ),
                            child: const Text('+5°'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _directionPreview(angleController.text),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      featureMode
                          ? l10n.featureDoesNotCreateCorner
                          : l10n.positionValidatedBeforeAdding,
                      style:
                          const TextStyle(
                        color:
                            Colors.black54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child:
                      Text(
                    l10n.cancel,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final distance =
                        _lengthInputToMeters(
                      system: selectedMeasurementSystem,
                      metricController: distanceController,
                      feetController: distanceFeetController,
                      inchesController: distanceInchesController,
                    );

                    final angle =
                        _parseNumber(
                      angleController
                          .text,
                    );

                    final featureWidth =
                        featureMode
                            ? _lengthInputToMeters(
                                system: selectedMeasurementSystem,
                                metricController: featureWidthController,
                                feetController: featureFeetController,
                                inchesController: featureInchesController,
                              )
                            : null;

                    setDialogState(() {
                      distanceError =
                          distance == null ||
                              distance <= 0
                          ? 1
                          : null;

                      angleError =
                          angle == null
                          ? 1
                          : null;

                      featureWidthError =
                          featureMode &&
                                  (featureWidth ==
                                          null ||
                                      featureWidth <
                                          0.20)
                              ? 1
                              : null;
                    });

                    if (distance == null ||
                        distance <= 0 ||
                        angle == null ||
                        (featureMode &&
                            (featureWidth ==
                                    null ||
                                featureWidth <
                                    0.20))) {
                      return;
                    }

                    _lastAngleDegrees = _normalizeAngle(angle);

                    Navigator.pop(
                      dialogContext,
                      _BasicMeasurement(
                        distance:
                            distance,
                        angle:
                            _lastAngleDegrees,
                        featureWidth:
                            featureWidth,
                      ),
                    );
                  },
                  icon:
                      const Icon(
                    Icons.check,
                  ),
                  label:
                      Text(
                    l10n.useMeasurement,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLengthFields({
    required MeasurementSystem system,
    required TextEditingController metricController,
    required TextEditingController feetController,
    required TextEditingController inchesController,
    required String label,
    required String metricHint,
    String? errorText,
    bool autofocus = false,
    bool compact = false,
  }) {
    final l10n =
        AppLocalizations.of(context)!;
    const keyboardType =
        TextInputType.numberWithOptions(
      decimal: true,
    );

    if (system == MeasurementSystem.metric) {
      return TextField(
        controller: metricController,
        autofocus: autofocus,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          hintText: metricHint,
          suffixText: compact ? 'm' : l10n.meters,
          prefixIcon: const Icon(
            Icons.straighten,
          ),
          errorText: errorText,
          border: const OutlineInputBorder(),
        ),
      );
    }

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        if (!compact)
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        if (!compact) const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: feetController,
                autofocus: autofocus,
                keyboardType: keyboardType,
                decoration: InputDecoration(
          isDense: true,
                  labelText: compact ? '$label (′)' : l10n.feet,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: inchesController,                keyboardType: keyboardType,
                decoration: InputDecoration(
          isDense: true,
                  labelText: compact ? '″' : l10n.inches,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText,
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  double? _lengthInputToMeters({
    required MeasurementSystem system,
    required TextEditingController metricController,
    required TextEditingController feetController,
    required TextEditingController inchesController,
  }) {
    if (system == MeasurementSystem.metric) {
      return MeasurementUnits.metricInputToMeters(
        metricController.text,
      );
    }

    return MeasurementUnits.imperialInputToMeters(
      feetInput: feetController.text,
      inchesInput: inchesController.text,
    );
  }

  void _convertLengthControllers({
    required MeasurementSystem from,
    required MeasurementSystem to,
    required TextEditingController metricController,
    required TextEditingController feetController,
    required TextEditingController inchesController,
  }) {
    if (from == to) {
      return;
    }

    if (to == MeasurementSystem.imperial) {
      final meters =
          MeasurementUnits.metricInputToMeters(
        metricController.text,
      );

      if (meters == null) {
        feetController.clear();
        inchesController.clear();
        return;
      }

      final imperial =
          MeasurementUnits.metersToFeetAndInches(
        meters,
      );

      feetController.text =
          imperial.feet.toString();
      inchesController.text =
          _formatUnitNumber(
        imperial.inches,
      );
      return;
    }

    final meters =
        MeasurementUnits.imperialInputToMeters(
      feetInput: feetController.text,
      inchesInput: inchesController.text,
    );

    if (meters == null) {
      metricController.clear();
      return;
    }
    metricController.text =
        _formatUnitNumber(meters);
  }
  String _formatUnitNumber(
    double value,
  ) {    var formatted =
        value.toStringAsFixed(2);

    final languageCode =
        Localizations.localeOf(context)
            .languageCode;

    return languageCode == 'es'
        ? formatted.replaceAll('.', ',')
        : formatted;
  }

  Widget _angleChip(
    String label,    IconData icon,
    double value,
    TextEditingController controller,
    StateSetter setDialogState,
  ) {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 22),
        label: Text(
          '$label ${value.toStringAsFixed(0)}°',
          textAlign: TextAlign.center,
        ),
        onPressed: () {
          controller.text = _formatAngle(value);
          setDialogState(() {});
        },
      ),
    );
  }

  void _adjustAngle(
    TextEditingController controller,
    double delta,
    StateSetter setDialogState,
  ) {
    final current = _parseNumber(controller.text) ?? 0.0;
    controller.text = _formatAngle(
      _normalizeAngle(current + delta),
    );
    setDialogState(() {});
  }
  double _normalizeAngle(double value) {
    final normalized = value % 360.0;
    return normalized < 0 ? normalized + 360.0 : normalized;
  }

  String _formatAngle(double value) {
    final normalized = _normalizeAngle(value);

    if (normalized == normalized.roundToDouble()) {
      return normalized.toStringAsFixed(0);
    }
    return normalized
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  String _directionPreview(String rawValue) {
    final parsed = _parseNumber(rawValue);

    if (parsed == null) {
      return 'Ingresá un ángulo válido';
    }

    final angle = _normalizeAngle(parsed);
    const tolerance = 0.001;

    if ((angle - 0.0).abs() < tolerance) {
      return '↑ Frente · 0°';
    }
    if ((angle - 90.0).abs() < tolerance) {
      return '→ Derecha · 90°';
    }
    if ((angle - 180.0).abs() < tolerance) {
      return '↓ Atrás · 180°';
    }
    if ((angle - 270.0).abs() < tolerance) {
      return '← Izquierda · 270°';
    }

    return 'Dirección personalizada · ${_formatAngle(angle)}°';
  }

  double? _parseNumber(
    String value,
  ) {
    var normalized =
        value.trim().toLowerCase();

    normalized =
        normalized.replaceAll(
      'metros',
      '',
    );

    normalized =
        normalized.replaceAll(
      'metro',
      '',
    );

    normalized =
        normalized.replaceAll(
      'm',
      '',
    );

    normalized =
        normalized.replaceAll(
      'grados',
      '',
    );

    normalized =
        normalized.replaceAll(
      'grado',
      '',
    );

    normalized =
        normalized.replaceAll(
      '°',
      '',
    );

    normalized =
        normalized.trim();

    normalized =
        normalized.replaceAll(
      ',',
      '.',
    );

    return double.tryParse(
      normalized,
    );
  }  void _showValidationError(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(          behavior:
              SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.paddingOf(context).bottom + 146,
          ),
          backgroundColor:
              Colors.red.shade800,          duration:
              const Duration(
            seconds: 4,          ),
          content: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child: Text(
                  message,
                ),
              ),
            ],
          ),
        ),
      );
  }

  bool _closingRoom = false;

  Future<void> _closeRoom(ScannerProvider provider) async {
    if (_closingRoom) return;
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
    if (provider.currentPointsCount <
        3) {
      _showValidationError(
        'Necesitás al menos 3 esquinas para cerrar el ambiente.',
      );
      return;
    }

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
          _showValidationError(
            addition.errorMessage ??
                AppLocalizations.of(context)!.invalidCorner,
          );
          return;
        }
      }
    }


    final floorPlanProvider =
        context.read<FloorPlanProvider>();

    if (continuation != null) {
      final sourceFeature = floorPlanProvider.findFeature(
        roomId: continuation.sourceRoomId,
        featureId: continuation.featureId,
      );

      if (sourceFeature == null || sourceFeature.isConnected) {
        _showValidationError(
          sourceFeature == null
              ? 'La abertura de referencia ya no existe.'
              : 'La abertura ya conecta otro ambiente.',
        );
        return;
      }
    }

    final room =
        provider.closeCurrentRoom();

    if (room == null) {
      _showValidationError(
        provider.lastCloseError ??
            'No se pudo cerrar el ambiente.',
      );
      return;
    }

    final resumeRoom = _activeResumeRoom;
    final resumesExistingRoom = resumeRoom != null &&
        floorPlanProvider.completedRooms.any(
          (existing) => existing.id == resumeRoom.id,
        );
    final saved = resumesExistingRoom
        ? await floorPlanProvider.replaceCompletedRoom(
            room,
            expectedOpenRoom: resumeRoom,
          )
        : continuation == null
            ? await floorPlanProvider.addCompletedRoom(
                room, preservePlacement: resumeRoom != null)
            : await floorPlanProvider.addCompletedRoomFromContinuation(
            room: room,
            reference: continuation,
          );

    if (!saved) {
      provider.restoreCurrentRoom(room.copyWith(isClosed: false));
      _showValidationError(
        'No se pudo guardar el ambiente. Revisá los solapamientos y volvé a intentar.',
      );
      return;
    }

    _draftSaveTimer?.cancel();
    await _scanDraftService.clear(widget.projectUuid);
    _lastDraftFingerprint = null;

    if (!mounted) {
      return;
    }

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

  void _openFloorPlan() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const FloorPlanViewerScreen(),
      ),
    );
  }

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior:
              SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.paddingOf(context).bottom + 146,
          ),
          duration:
              const Duration(
            seconds: 2,
          ),
          content: Text(
            message,
          ),
        ),
      );
  }
}

class _BasicMeasurement {
  final double distance;
  final double angle;
  final double? featureWidth;

  const _BasicMeasurement({
    required this.distance,
    required this.angle,
    this.featureWidth,
  });
}