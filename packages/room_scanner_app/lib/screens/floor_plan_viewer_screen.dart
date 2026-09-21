import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, listEquals;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers/floor_plan_provider.dart';
import '../providers/measurement_settings_provider.dart';
import '../services/import_export_service.dart';
import '../services/ar_check_service.dart';
import '../services/room_plan_capture_coordinator.dart';
import '../services/room_plan_service.dart';
import '../services/scan_draft_service.dart';
import '../widgets/plan_wall_length_dialog.dart';
import '../widgets/opening_placement_dialog.dart' show showOpeningPlacementDialog;
import '../widgets/room_name_dialog.dart';

part 'floor_plan_wall_editor.dart';

class FloorPlanViewerScreen extends StatefulWidget {
  final bool selectContinuationOpening;

  const FloorPlanViewerScreen({
    super.key,
    this.selectContinuationOpening = false,
  });

  @override
  State<FloorPlanViewerScreen> createState() =>
      _FloorPlanViewerScreenState();
}

class _FloorPlanViewerScreenState
    extends State<FloorPlanViewerScreen> with _PlanWallEditing {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  PersistentBottomSheetController? _featureSheetController;
  double _minX = 0.0;
  double _minZ = 0.0;
  double _scale = 1.0;
  double _padding = 20.0;

  @override
  String? _selectedRoomId;
  String? _selectedFeatureId;
  @override
  bool _touchTransformMode = false;
  Offset _touchStartFocalPoint = Offset.zero;
  Offset _touchNavigationFocalPoint = Offset.zero;
  double _touchNavigationScale = 1;
  bool _touchNavigating = false;
  String? _touchTransformRoomId;
  int _touchSnapCount = 0;
  bool _roomPlanSupported = false;
  bool _roomPlanScanning = false;

  @override
  void initState() {
    super.initState();
    _loadRoomPlanSupport();
  }

  Future<void> _loadRoomPlanSupport() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    final supported = await RoomPlanService.isSupported();
    if (!mounted || supported == _roomPlanSupported) return;
    setState(() => _roomPlanSupported = supported);
  }

  Future<void> _captureWithRoomPlan() async {
    if (_roomPlanScanning) return;
    final l10n = AppLocalizations.of(context)!;
    final roomName = await showRoomNameDialog(
      context: context,
      initialName: l10n.roomTypeOther,
    );
    if (!mounted || roomName == null) return;

    setState(() => _roomPlanScanning = true);
    try {
      final room = await const RoomPlanCaptureCoordinator().captureAndPersist(
        floorPlanProvider: context.read<FloorPlanProvider>(),
        roomName: roomName,
      );
      if (!mounted || room == null) return;
      _showMessage(l10n.roomPlanSpaceSaved);
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(
          l10n.roomPlanCaptureFailed(error.message ?? error.code),
          error: true,
        );
      }
    } on FormatException catch (error) {
      if (mounted) {
        _showMessage(
          l10n.roomPlanCaptureFailed('${error.message}'),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _roomPlanScanning = false);
    }
  }

  void _toggleTouchTransformMode() {
    _clearPlanSelection();
    _wallEditMode = false;
    final provider = context.read<FloorPlanProvider>();
    if (_touchTransformRoomId != null) {
      provider.cancelTouchRoomTransform();
      _touchTransformRoomId = null;
      _touchSnapCount = 0;
    }
    setState(() {
      _touchTransformMode = !_touchTransformMode;
      _selectedFeatureId = null;
    });
  }

  void _zoomPlan(double factor) {
    final current = _planViewport.value;
    final currentScale = current.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(0.2, 6.0).toDouble();
    if ((targetScale - currentScale).abs() <= 0.000001) return;
    final ratio = targetScale / currentScale;
    final viewportCenter = MediaQuery.sizeOf(context).center(Offset.zero);
    final translationX = current.storage[12];
    final translationY = current.storage[13];
    final next = Matrix4.identity()
      ..setEntry(0, 0, targetScale)
      ..setEntry(1, 1, targetScale)
      ..setEntry(2, 2, targetScale)
      ..setTranslationRaw(
        viewportCenter.dx - (viewportCenter.dx - translationX) * ratio,
        viewportCenter.dy - (viewportCenter.dy - translationY) * ratio,
        0,
      );
    _planViewport.value = next;
  }

  void _resetPlanZoom() {
    _planViewport.value = Matrix4.identity();
  }

  void _startTouchTransform(
    ScaleStartDetails details,
    List<RoomModel> rooms,
  ) {
    _touchNavigationFocalPoint = details.focalPoint;
    _touchNavigationScale = 1;
    _touchNavigating = false;
    final planePoint = _inverseTransform(details.localFocalPoint);
    final roomId = _getRoomAtPosition(planePoint, rooms) ?? _selectedRoomId;
    if (roomId == null ||
        !context.read<FloorPlanProvider>().beginTouchRoomTransform(roomId)) {
      return;
    }
    _touchStartFocalPoint = details.localFocalPoint;
    _touchTransformRoomId = roomId;
    _touchSnapCount = 0;
    setState(() {
      _selectedRoomId = roomId;
      _selectedFeatureId = null;
    });
  }

  void _updateTouchTransform(ScaleUpdateDetails details) {
    if (details.pointerCount > 1) {
      final provider = context.read<FloorPlanProvider>();
      if (!_touchNavigating) {
        provider.cancelTouchRoomTransform();
        _touchTransformRoomId = null;
        _touchSnapCount = 0;
        _touchNavigating = true;
        _touchNavigationFocalPoint = details.focalPoint;
        _touchNavigationScale = details.scale;
        return;
      }
      final delta = details.focalPoint - _touchNavigationFocalPoint;
      final next = _planViewport.value.clone();
      next.storage[12] += delta.dx;
      next.storage[13] += delta.dy;
      _planViewport.value = next;
      final scaleFactor = details.scale / _touchNavigationScale;
      if (scaleFactor.isFinite && scaleFactor > 0) {
        _zoomPlan(scaleFactor);
      }
      _touchNavigationFocalPoint = details.focalPoint;
      _touchNavigationScale = details.scale;
      return;
    }
    if (_touchNavigating) return;
    final roomId = _touchTransformRoomId;
    if (roomId == null) return;
    final delta = details.localFocalPoint - _touchStartFocalPoint;
    final provider = context.read<FloorPlanProvider>();
    final updated = provider.updateTouchRoomTransform(
      roomId: roomId,
      offsetX: delta.dx / _scale,
      offsetZ: delta.dy / _scale,
      angleDegrees: details.rotation * 180 / math.pi,
    );
    if (!updated) return;
    final snapCount = provider.touchTransformSnapCount;
    if (snapCount > _touchSnapCount) {
      HapticFeedback.selectionClick();
    }
    _touchSnapCount = snapCount;
  }

  Future<void> _endTouchTransform() async {
    if (_touchNavigating) {
      _touchNavigating = false;
      return;
    }
    final roomId = _touchTransformRoomId;
    if (roomId == null) return;
    _touchTransformRoomId = null;
    _touchSnapCount = 0;
    final accepted = await context.read<FloorPlanProvider>().endTouchRoomTransform(
          roomId: roomId,
        );
    if (!mounted) return;
    if (!accepted) {
      _showMessage(
        AppLocalizations.of(context)!.unsafeMovementRejected,
        error: true,
      );
    }
    setState(() {});
  }

  // ===========================================================================
  // TRANSFORMACIÓN PLANO ↔ PANTALLA
  // ===========================================================================

  @override
  Offset _transformPoint(
    ARPoint point,
  ) {
    final x =
        _padding +
        (point.x - _minX) * _scale;

    final z =
        _padding +
        (point.z - _minZ) * _scale;

    return Offset(x, z);
  }

  @override
  ARPoint _inverseTransform(
    Offset screenPosition,
  ) {
    final x =
        (screenPosition.dx - _padding) /
                _scale +
            _minX;

    final z =
        (screenPosition.dy - _padding) /
                _scale +
            _minZ;

    return ARPoint(
      x: x,
      y: 0.0,
      z: z,
    );
  }

  void _calculateTransform(
    Size screenSize,
    List<RoomModel> rooms,
  ) {
    if (rooms.isEmpty) {
      return;
    }

    double minX = double.infinity;
    double maxX =
        double.negativeInfinity;

    double minZ = double.infinity;
    double maxZ =
        double.negativeInfinity;

    bool hasPoints = false;

    for (final room in rooms) {
      for (final point in room.points) {
        hasPoints = true;

        if (point.x < minX) {
          minX = point.x;
        }

        if (point.x > maxX) {
          maxX = point.x;
        }

        if (point.z < minZ) {
          minZ = point.z;
        }

        if (point.z > maxZ) {
          maxZ = point.z;
        }
      }
    }

    if (!hasPoints) {
      _minX = 0.0;
      _minZ = 0.0;
      _scale = 1.0;
      _padding = 20.0;
      return;
    }

    _minX = minX;
    _minZ = minZ;

    _padding =
        screenSize.width * 0.08;

    final contentWidth =
        (maxX - minX).abs();

    final contentHeight =
        (maxZ - minZ).abs();

    final safeWidth =
        contentWidth <= 0.0001
            ? 1.0
            : contentWidth;

    final safeHeight =
        contentHeight <= 0.0001
            ? 1.0
            : contentHeight;

    final availableWidth =
        screenSize.width -
            (_padding * 2);

    final availableHeight =
        screenSize.height -
            (_padding * 2);

    final widthScale =
        availableWidth / safeWidth;

    final heightScale =
        availableHeight / safeHeight;

    _scale =
        widthScale < heightScale
            ? widthScale
            : heightScale;

    if (!_scale.isFinite ||
        _scale <= 0) {
      _scale = 1.0;
    }
  }

  String? _getRoomAtPosition(
    ARPoint point,
    List<RoomModel> rooms,
  ) {
    for (final room
        in rooms.reversed) {
      if (GeometryService
          .isPointInPolygon(
        point,
        room.points,
      )) {
        return room.id;
      }
    }

    return null;
  }

  _FeatureSelection? _getFeatureAtPosition(
    Offset screenPosition,
    List<RoomModel> rooms,
  ) {
    const touchTolerance = 18.0;

    _FeatureSelection? nearest;
    double nearestDistance = double.infinity;

    for (final room in rooms.reversed) {
      for (final feature in room.features) {
        final distance = _distanceToSegment(
          screenPosition,
          _transformPoint(feature.start),
          _transformPoint(feature.end),
        );

        if (distance <= touchTolerance &&
            distance < nearestDistance) {
          nearestDistance = distance;
          nearest = _FeatureSelection(
            roomId: room.id,
            feature: feature,
          );
        }
      }
    }

    return nearest;
  }

  double _distanceToSegment(
    Offset point,
    Offset start,
    Offset end,
  ) {
    final segment = end - start;
    final lengthSquared = segment.dx * segment.dx +
        segment.dy * segment.dy;

    if (lengthSquared <= 0.000001) {
      return (point - start).distance;
    }

    final fromStart = point - start;
    final rawT =
        (fromStart.dx * segment.dx +
                fromStart.dy * segment.dy) /
            lengthSquared;
    final t = rawT.clamp(0.0, 1.0).toDouble();
    final projection = Offset(
      start.dx + segment.dx * t,
      start.dy + segment.dy * t,
    );

    return (point - projection).distance;
  }

  Future<void> _showFeatureMenu(
    _FeatureSelection selection,
  ) async {
    if (widget.selectContinuationOpening) {
      await _continueFromOpening(selection, chooseSide: false);
      return;
    }

    setState(() {
      _selectedRoomId = selection.roomId;
      _selectedFeatureId = selection.feature.id;
    });

    final feature = selection.feature;
    final measurementSystem = context
        .read<MeasurementSettingsProvider>()
        .system;
    final localizations = AppLocalizations.of(context)!;
    final label = feature.type == FeatureType.door
        ? localizations.selectedDoor
        : localizations.selectedWindow;

    final previousController = _featureSheetController;
    if (previousController != null) {
      previousController.close();
      await previousController.closed;
      if (!mounted) return;
    }
    _FeatureMenuAction? action;
    late PersistentBottomSheetController controller;
    void selectAction(_FeatureMenuAction selected) {
      action = selected;
      controller.close();
    }
    controller = _scaffoldKey.currentState!.showBottomSheet(
      (bottomSheetContext) {
        return SafeArea(
          child: SingleChildScrollView(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    feature.type == FeatureType.door
                        ? Icons.door_front_door
                        : Icons.window,
                    color: feature.type == FeatureType.door
                        ? const Color(0xFFFF8A00)
                        : const Color(0xFFD500F9),
                  ),
                  title: Text(label),
                  subtitle: Text(
                    '${feature.isConnected ? localizations.openingConnectedStatus : localizations.openingAvailableStatus} · '
                    '${_formatLength(_featureWidth(feature), measurementSystem)}'
                    '${feature.isConnected ? '' : ' · ${localizations.openingStartAtMarkedPoint}'}',
                  ),
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: 52,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          selectAction(_FeatureMenuAction.editGeometry),
                      icon: const Icon(Icons.straighten),
                      label: Text(
                        localizations.editOpeningDimensions,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.touch_app),
                      label: Text(
                        localizations.moveOpeningOnWall,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                      ),
                      onPressed: () => selectAction(_FeatureMenuAction.move),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: Text(
                        localizations.deleteOpening,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                      ),
                      onPressed: () => selectAction(_FeatureMenuAction.delete),
                    ),
                    if (feature.type == FeatureType.door)
                      OutlinedButton.icon(
                        onPressed: () =>
                            selectAction(_FeatureMenuAction.toggleHinge),
                        icon: const Icon(Icons.flip),
                        label: Text(
                          localizations.changeDoorHingeSide,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (feature.type == FeatureType.door) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => selectAction(
                        _FeatureMenuAction.chooseOpeningDirection,
                      ),
                      icon: const Icon(Icons.rotate_left),
                      label: Text(
                        feature.doorOpeningDirection ==
                                DoorOpeningDirection.interior
                            ? localizations.doorOpensInterior
                            : localizations.doorOpensExterior,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: feature.isConnected
                        ? null
                        : () => selectAction(
                              _FeatureMenuAction.continueScanning,
                            ),
                    icon: const Icon(Icons.add_road_rounded),
                    label: Text(
                      feature.isConnected
                          ? localizations.openingAlreadyConnected
                          : localizations.continueScanFromHere,
                    ),
                  ),
                ),
              ],
            ),
          )),
        );
      },
      enableDrag: true,
      showDragHandle: true,
    );
    _featureSheetController = controller;
    await controller.closed;
    if (identical(_featureSheetController, controller)) {
      _featureSheetController = null;
    }

    if (!mounted) return;

    if (action == _FeatureMenuAction.move) {
      await _placeOpeningOnWall(selection.roomId, feature.type, feature: feature);
      return;
    }

    if (action == _FeatureMenuAction.editGeometry) {
      await _showOpeningGeometryEditor(selection);
      return;
    }

    if (action == _FeatureMenuAction.delete) {
      final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: Text(localizations.deleteOpening),
        content: Text(localizations.deleteOpeningConfirmation),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(localizations.cancel)),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(localizations.deleteOpening)),
        ],
      ));
      if (!mounted || confirmed != true) return;
      if (!await context.read<FloorPlanProvider>().removeOpening(selection.roomId, feature.id)) {
        if (mounted) _planError(PlanEditError.invalid);
        return;
      }
      if (mounted) setState(() { _selectedFeatureId = null; });
      return;
    }

    if (action == _FeatureMenuAction.toggleHinge) {
      final updated = await context
          .read<FloorPlanProvider>()
          .updateDoorOrientation(
            featureId: feature.id,
            hingeSide:
                feature.doorHingeSide == DoorHingeSide.start
                    ? DoorHingeSide.end
                    : DoorHingeSide.start,
          );

      if (mounted && !updated) {
        _showMessage(
          AppLocalizations.of(context)!.selectedDoorUnavailable,
          error: true,
        );
      }
      return;
    }

    if (action == _FeatureMenuAction.chooseOpeningDirection) {
      final direction = await _chooseDoorOpeningDirection(feature);

      if (!mounted || direction == null) {
        return;
      }

      final updated = await context
          .read<FloorPlanProvider>()
          .updateDoorOrientation(
            featureId: feature.id,
            openingDirection: direction,
          );

      if (mounted && !updated) {
        _showMessage(
          AppLocalizations.of(context)!.selectedDoorUnavailable,
          error: true,
        );
      }
      return;
    }

    if (action != _FeatureMenuAction.continueScanning) {
      return;
    }

    await _continueFromOpening(selection, chooseSide: true);
  }

  Future<void> _continueFromOpening(
    _FeatureSelection selection, {
    required bool chooseSide,
  }) async {
    final feature = selection.feature;
    if (feature.isConnected) {
      if (widget.selectContinuationOpening) {
        _showMessage(
          AppLocalizations.of(context)!.openingAlreadyConnected,
          error: true,
        );
      }
      return;
    }

    final side = chooseSide
        ? await _chooseConnectionSide(feature)
        : _availableSideFor(selection);

    if (!mounted || side == null) return;

    final provider = context.read<FloorPlanProvider>();
    final reference = provider.createContinuationReference(
      roomId: selection.roomId,
      featureId: feature.id,
      side: side,
      startEndpoint: ContinuationStartEndpoint.start,
    );

    final projectUuid = provider.projectUuid;

    if (reference == null || projectUuid == null) {
      _showMessage(
        AppLocalizations.of(context)!.selectedOpeningUnavailable,
        error: true,
      );
      return;
    }

    await ArCheckService.abrirEscanerConValidacion(
      context,
      projectUuid: projectUuid,
      projectName: provider.projectName,
      continuationReference: reference,
    );
  }

  OpeningConnectionSide _availableSideFor(
    _FeatureSelection selection,
  ) {
    final provider = context.read<FloorPlanProvider>();
    final room = provider.completedRooms.firstWhere(
      (candidate) => candidate.id == selection.roomId,
    );
    final feature = selection.feature;
    final dx = feature.end.x - feature.start.x;
    final dz = feature.end.z - feature.start.z;
    final length = math.sqrt(dx * dx + dz * dz);

    if (length <= 0.000001) {
      return OpeningConnectionSide.left;
    }

    final midpoint = ARPoint(
      x: (feature.start.x + feature.end.x) / 2,
      y: (feature.start.y + feature.end.y) / 2,
      z: (feature.start.z + feature.end.z) / 2,
    );
    final leftProbe = ARPoint(
      x: midpoint.x - dz / length * 0.10,
      y: midpoint.y,
      z: midpoint.z + dx / length * 0.10,
    );

    return GeometryService.isPointInPolygon(leftProbe, room.points)
        ? OpeningConnectionSide.right
        : OpeningConnectionSide.left;  }  Future<void> _showOpeningGeometryEditor(    _FeatureSelection selection,
  ) async {
    final provider = context.read<FloorPlanProvider>();
    final placement = provider.getOpeningPlacement(
      roomId: selection.roomId,
      featureId: selection.feature.id,
    );
    final localizations = AppLocalizations.of(context)!;
    final measurementSystem = context
        .read<MeasurementSettingsProvider>()
        .system;

    if (placement == null) {
      _showMessage(
        AppLocalizations.of(context)!.openingWallNotFound,
        error: true,
      );
      return;
    }

    final widthMetricController = TextEditingController(
      text: _formatDecimal(placement.widthMeters),
    );
    final positionMetricController = TextEditingController(
      text: _formatDecimal(
        placement.distanceFromWallStartMeters,
      ),
    );
    final heightMetricController = TextEditingController(
      text: _formatDecimal(placement.openingHeightMeters),
    );
    final sillMetricController = TextEditingController(
      text: _formatDecimal(placement.sillHeightMeters),
    );
    final widthImperial = MeasurementUnits.metersToFeetAndInches(
      placement.widthMeters,
    );
    final positionImperial =
        MeasurementUnits.metersToFeetAndInches(
      placement.distanceFromWallStartMeters,
    );
    final heightImperial = MeasurementUnits.metersToFeetAndInches(
      placement.openingHeightMeters,
    );
    final sillImperial = MeasurementUnits.metersToFeetAndInches(
      placement.sillHeightMeters,
    );
    final widthFeetController = TextEditingController(
      text: widthImperial.feet.toString(),
    );
    final widthInchesController = TextEditingController(
      text: _formatDecimal(widthImperial.inches),    );
    final positionFeetController = TextEditingController(
      text: positionImperial.feet.toString(),
    );
    final positionInchesController = TextEditingController(
      text: _formatDecimal(positionImperial.inches),
    );
    final heightFeetController = TextEditingController(
      text: heightImperial.feet.toString(),
    );
    final heightInchesController = TextEditingController(
      text: _formatDecimal(heightImperial.inches),
    );
    final sillFeetController = TextEditingController(
      text: sillImperial.feet.toString(),
    );
    final sillInchesController = TextEditingController(
      text: _formatDecimal(sillImperial.inches),
    );

    double? readLength({
      required TextEditingController metric,
      required TextEditingController feet,
      required TextEditingController inches,
    }) {
      if (measurementSystem == MeasurementSystem.metric) {
        return MeasurementUnits.metricInputToMeters(metric.text);
      }
      return MeasurementUnits.imperialInputToMeters(
        feetInput: feet.text,
        inchesInput: inches.text,
      );
    }

    final route = DialogRoute<_OpeningGeometryInput>(
      context: context,
      builder: (dialogContext) {
        String? validationMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget lengthFields({
              required String label,
              required TextEditingController metric,
              required TextEditingController feet,
              required TextEditingController inches,
            }) {
              if (measurementSystem == MeasurementSystem.metric) {
                return TextField(                  controller: metric,                  keyboardType: const TextInputType.numberWithOptions(                    decimal: true,                  ),                  decoration: InputDecoration(
                    labelText: label,
                    suffixText: localizations.meters,
                    border: const OutlineInputBorder(),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: feet,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: localizations.feet,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: inches,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: localizations.inches,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }

            return AlertDialog(
              title: Text(localizations.editOpeningDimensions),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,                  children: [                    Text(                      '${localizations.wallLength}: '                      '${_formatLength(placement.wallLengthMeters, measurementSystem)}',
                    ),
                    const SizedBox(height: 16),
                    lengthFields(
                      label: localizations.openingWidth,
                      metric: widthMetricController,
                      feet: widthFeetController,
                      inches: widthInchesController,
                    ),
                    const SizedBox(height: 16),
                    lengthFields(
                      label: localizations.distanceFromWallStart,
                      metric: positionMetricController,
                      feet: positionFeetController,
                      inches: positionInchesController,
                    ),
                    const SizedBox(height: 16),
                    lengthFields(
                      label: localizations.openingHeight,
                      metric: heightMetricController,
                      feet: heightFeetController,
                      inches: heightInchesController,
                    ),
                    if (selection.feature.type ==
                        FeatureType.window) ...[
                      const SizedBox(height: 16),
                      lengthFields(
                        label: localizations.sillHeight,
                        metric: sillMetricController,
                        feet: sillFeetController,
                        inches: sillInchesController,
                      ),
                    ],
                    if (validationMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        validationMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ],                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(localizations.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    final width = readLength(
                      metric: widthMetricController,
                      feet: widthFeetController,
                      inches: widthInchesController,
                    );
                    final position = readLength(
                      metric: positionMetricController,
                      feet: positionFeetController,
                      inches: positionInchesController,
                    );
                    final height = readLength(
                      metric: heightMetricController,
                      feet: heightFeetController,
                      inches: heightInchesController,
                    );
                    final sill = selection.feature.type ==
                            FeatureType.window
                        ? readLength(
                            metric: sillMetricController,
                            feet: sillFeetController,
                            inches: sillInchesController,
                          )
                        : 0.0;

                    if (width == null ||
                        position == null ||
                        height == null ||
                        sill == null ||
                        !width.isFinite || width < 0.20 ||
                        !position.isFinite || position < 0 ||
                        width + position > placement.wallLengthMeters + 0.000001 ||
                        !height.isFinite || height < 0.20 ||
                        !sill.isFinite || sill < 0) {
                      setDialogState(() {
                        validationMessage =
                            localizations.invalidOpeningMeasurement;
                      });
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      _OpeningGeometryInput(
                        widthMeters: width,
                        distanceFromWallStartMeters: position,
                        openingHeightMeters: height,
                        sillHeightMeters: sill,
                      ),
                    );
                  },
                  child: Text(localizations.save),
                ),
              ],
            );
          },
        );
      },
    );
    final input = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;

    widthMetricController.dispose();
    positionMetricController.dispose();
    widthFeetController.dispose();
    widthInchesController.dispose();
    positionFeetController.dispose();
    positionInchesController.dispose();
    heightMetricController.dispose();
    sillMetricController.dispose();
    heightFeetController.dispose();
    heightInchesController.dispose();
    sillFeetController.dispose();
    sillInchesController.dispose();

    if (!mounted || input == null) return;

    final result = await provider.updateOpeningGeometry(
      roomId: selection.roomId,
      featureId: selection.feature.id,
      widthMeters: input.widthMeters,
      distanceFromWallStartMeters:
          input.distanceFromWallStartMeters,
      openingHeightMeters: input.openingHeightMeters,
      sillHeightMeters: input.sillHeightMeters,
    );

    if (!mounted) return;
    _showMessage(
      result.isSuccess
          ? localizations.openingUpdated
          : result.errorMessage ??
              localizations.invalidOpeningMeasurement,
      error: !result.isSuccess,
    );
  }

  Future<DoorOpeningDirection?> _chooseDoorOpeningDirection(
    WallFeature feature,
  ) {
    final localizations = AppLocalizations.of(context)!;

    String planDirectionLabel(DoorOpeningDirection openingDirection) {
      final start = _transformPoint(feature.start);
      final end = _transformPoint(feature.end);
      final opening = end - start;
      if (opening.distance <= 0.000001) {
        return openingDirection == DoorOpeningDirection.interior
            ? localizations.doorOpensInterior
            : localizations.doorOpensExterior;
      }
      final tangent = opening / opening.distance;
      var direction = feature.doorSwingSide == DoorSwingSide.left
          ? Offset(-tangent.dy, tangent.dx)
          : Offset(tangent.dy, -tangent.dx);
      if (openingDirection == DoorOpeningDirection.exterior) {
        direction = -direction;
      }
      if (direction.dx.abs() > direction.dy.abs()) {
        return direction.dx >= 0
            ? '→ ${localizations.right}'
            : '← ${localizations.left}';
      }
      return direction.dy >= 0
          ? '↓ ${localizations.directionDown}'
          : '↑ ${localizations.directionUp}';
    }

    return showDialog<DoorOpeningDirection>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: Text(
            localizations.chooseDoorOpeningDirection,
          ),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(
                dialogContext,
                DoorOpeningDirection.interior,
              ),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.home_outlined),
                title: Text(
                  planDirectionLabel(DoorOpeningDirection.interior),
                ),
                subtitle: Text(localizations.doorOpensInterior),
                trailing: feature.doorOpeningDirection ==
                        DoorOpeningDirection.interior
                    ? const Icon(Icons.check_circle)
                    : null,
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(
                dialogContext,
                DoorOpeningDirection.exterior,
              ),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.exit_to_app),
                title: Text(
                  planDirectionLabel(DoorOpeningDirection.exterior),
                ),
                subtitle: Text(localizations.doorOpensExterior),
                trailing: feature.doorOpeningDirection ==
                        DoorOpeningDirection.exterior
                    ? const Icon(Icons.check_circle)
                    : null,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<OpeningConnectionSide?> _chooseConnectionSide(
    WallFeature feature,
  ) {
    final localizations = AppLocalizations.of(context)!;
    final start = _transformPoint(feature.start);
    final end = _transformPoint(feature.end);
    final openingDirection = end - start;
    final leftDirection = Offset(
      -openingDirection.dy,
      openingDirection.dx,
    );
    final rightDirection = -leftDirection;
    final directionsAreVertical =
        leftDirection.dy.abs() > leftDirection.dx.abs();
    final leftChoiceComesFirst = directionsAreVertical
        ? leftDirection.dy <= rightDirection.dy
        : leftDirection.dx <= rightDirection.dx;
    final firstSide = leftChoiceComesFirst
        ? OpeningConnectionSide.left
        : OpeningConnectionSide.right;
    final firstDirection =
        leftChoiceComesFirst ? leftDirection : rightDirection;
    final secondSide = leftChoiceComesFirst
        ? OpeningConnectionSide.right
        : OpeningConnectionSide.left;
    final secondDirection =
        leftChoiceComesFirst ? rightDirection : leftDirection;

    return showDialog<OpeningConnectionSide>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(localizations.continuationDirectionTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                localizations.continuationDirectionExplanation,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 240,
                height: 120,
                child: CustomPaint(
                  painter: _OpeningDirectionPainter(
                    openingDirection: openingDirection,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    firstSide,
                  ),
                  icon: Icon(_directionIcon(firstDirection)),
                  label: Text(
                    localizations.continueToward(
                      _directionLabel(firstDirection, localizations),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    secondSide,
                  ),
                  icon: Icon(_directionIcon(secondDirection)),
                  label: Text(
                    localizations.continueToward(
                      _directionLabel(secondDirection, localizations),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(localizations.cancel),
            ),
          ],
        );
      },
    );
  }

  String _directionLabel(
    Offset direction,
    AppLocalizations localizations,
  ) {
    if (direction.dx.abs() >= direction.dy.abs()) {
      return direction.dx >= 0
          ? localizations.directionRight
          : localizations.directionLeft;
    }

    return direction.dy >= 0
        ? localizations.directionDown
        : localizations.directionUp;
  }

  IconData _directionIcon(Offset direction) {
    if (direction.dx.abs() >= direction.dy.abs()) {
      return direction.dx >= 0
          ? Icons.arrow_forward
          : Icons.arrow_back;
    }

    return direction.dy >= 0
        ? Icons.arrow_downward
        : Icons.arrow_upward;
  }

  double _featureWidth(WallFeature feature) {
    return GeometryService.calculateDistance(
      feature.start,
      feature.end,
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

  String _formatOpeningPlanDimensions(
    WallFeature feature,
    MeasurementSystem measurementSystem,
  ) {
    final localizations = AppLocalizations.of(context)!;
    final width = _formatLength(
      _featureWidth(feature),
      measurementSystem,
    );
    final height = _formatLength(
      feature.openingHeightMeters,
      measurementSystem,
    );

    if (feature.type == FeatureType.door) {
      return localizations.doorPlanDimensions(width, height);
    }

    final sill = _formatLength(
      feature.sillHeightMeters,
      measurementSystem,
    );
    final orientation = _featureWidth(feature) >=
            feature.openingHeightMeters        ? localizations.horizontalOrientation
        : localizations.verticalOrientation;
    return localizations.windowPlanDimensions(
      width,
      height,
      sill,      orientation,
    );  }
  String _formatArea(
    double squareMeters,
    MeasurementSystem measurementSystem,
  ) {
    final localizations =
        AppLocalizations.of(context)!;

    if (measurementSystem ==
        MeasurementSystem.metric) {
      return '${_formatDecimal(squareMeters)} '
          '${localizations.squareMeters}';
    }

    final squareFeet =
        MeasurementUnits.squareMetersToSquareFeet(
      squareMeters,
    );

    return '${_formatDecimal(squareFeet)} '
        '${localizations.squareFeet}';
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

  // ===========================================================================  // EDITOR DE MEDIDAS
  // ===========================================================================

  Future<void>
      _openMeasurementEditor({    String? roomId,
  }) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _clearPlanSelection();
      _touchTransformMode = false;
      _wallEditMode = true;
      _selectedRoomId = roomId;
    });
  }

  // ===========================================================================
  // ORGANIZACIÓN AUTOMÁTICA
  // ===========================================================================
  Future<void> _organizeRooms() async {
    final localizations = AppLocalizations.of(context)!;
    final provider =        context.read<            FloorPlanProvider>();

    if (provider.completedRooms.length <=
        1) {
      _showMessage(
        localizations.notEnoughRoomsToOrganize,
      );
      return;
    }

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.grid_view_rounded,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  localizations.organizeRooms,
                ),
              ),
            ],
          ),
          content: Text(
            localizations.organizeRoomsExplanation,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: Text(
                localizations.cancel,
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,                );
              },
              icon: const Icon(
                Icons.auto_awesome,
              ),
              label: Text(
                localizations.organizeRooms,
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true ||
        !mounted) {
      return;
    }

    final changed = await provider.autoArrangeRooms();

    if (!mounted) {
      return;
    }
    _showMessage(changed
        ? localizations.roomsOrganizedSuccessfully
        : localizations.roomsArrangementUnchanged);
  }
  // ===========================================================================
  // BUILD
  // ===========================================================================

  Future<void> _showRoomTransformEditor() async {
    final provider = context.read<FloorPlanProvider>();
    final localizations = AppLocalizations.of(context)!;
    final measurementSystem =
        context.read<MeasurementSettingsProvider>().system;
    final rooms = provider.completedRooms;

    if (rooms.isEmpty) {
      _showMessage(localizations.noRoomsToEdit);
      return;
    }

    var selectedRoomId = rooms.any(
      (room) => room.id == _selectedRoomId,
    )
        ? _selectedRoomId!
        : rooms.first.id;
    String? targetRoomId = rooms
        .where(
          (room) => provider.canJoinRoomPair(
            sourceRoomId: selectedRoomId,
            targetRoomId: room.id,
          ),
        )
        .map((room) => room.id)
        .firstOrNull;
    var movementStep = measurementSystem == MeasurementSystem.metric
        ? 0.10
        : MeasurementUnits.inchesToMeters(3);

    setState(() {
      _selectedRoomId = selectedRoomId;
      _selectedFeatureId = null;
    });

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (bottomSheetContext) {
        return StatefulBuilder(          builder: (context, setModalState) {
            Future<void> moveRoom({              required double offsetX,
              required double offsetZ,
            }) async {
              final result = await provider.translateRoomAutomatically(
                roomId: selectedRoomId,
                offsetX: offsetX,
                offsetZ: offsetZ,
              );
              if (context.mounted) {
                setModalState(() {});
              }
              if (result.wasAdjusted && mounted) {
                _showMessage(localizations.roomAdjustedAutomatically);
              } else if (result.wasRejected && mounted) {
                _showMessage(
                  localizations.unsafeMovementRejected,
                  error: true,
                );
              }
            }

            Future<void> rotateRoom(double angleDegrees) async {
              final rotated = await provider.rotateRoom(
                roomId: selectedRoomId,
                angleDegrees: angleDegrees,
              );
              if (context.mounted) {
                setModalState(() {});
              }
              if (!rotated && mounted) {
                _showMessage(
                  localizations.unsafeRotationRejected,
                  error: true,
                );
              }
            }

            Future<void> undoTransform() async {
              await provider.undoTransform();
              if (context.mounted) {
                setModalState(() {});
              }
            }

            Future<void> redoTransform() async {
              await provider.redoTransform();
              if (context.mounted) {
                setModalState(() {});
              }
            }

            Future<void> applyPreciseAdjustment() async {
              final horizontalController =
                  TextEditingController(text: '0');
              final verticalController =
                  TextEditingController(text: '0');
              final rotationController =
                  TextEditingController(text: '0');

              double? parseNumber(String value) {
                return double.tryParse(
                  value.trim().replaceAll(',', '.'),
                );
              }

              final input = await showDialog<_PreciseTransformInput>(
                context: context,
                builder: (dialogContext) {
                  String? validationMessage;
                  return StatefulBuilder(
                    builder: (context, setDialogState) => AlertDialog(
                      title: Text(localizations.preciseAdjustment),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(localizations.preciseAdjustmentExplanation),
                            const SizedBox(height: 16),
                            TextField(
                              controller: horizontalController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              decoration: InputDecoration(
                                labelText: localizations.horizontalAdjustment,
                                suffixText: measurementSystem ==
                                        MeasurementSystem.metric
                                    ? localizations.meters
                                    : localizations.inches,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: verticalController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              decoration: InputDecoration(
                                labelText: localizations.verticalAdjustment,
                                suffixText: measurementSystem ==
                                        MeasurementSystem.metric
                                    ? localizations.meters
                                    : localizations.inches,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: rotationController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              decoration: InputDecoration(
                                labelText: localizations.rotationDegrees,
                                suffixText: localizations.degrees,
                                border: const OutlineInputBorder(),
                                errorText: validationMessage,
                              ),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(dialogContext),
                          child: Text(localizations.cancel),
                        ),
                        FilledButton(
                          onPressed: () {
                            final horizontal =
                                parseNumber(horizontalController.text);
                            final vertical =
                                parseNumber(verticalController.text);
                            final rotation =
                                parseNumber(rotationController.text);
                            if (horizontal == null ||
                                vertical == null ||
                                rotation == null ||
                                (horizontal.abs() <= 0.000001 &&
                                    vertical.abs() <= 0.000001 &&
                                    rotation.abs() <= 0.000001)) {
                              setDialogState(() {
                                validationMessage =
                                    localizations.invalidPreciseAdjustment;
                              });
                              return;
                            }
                            final offsetX = measurementSystem ==
                                    MeasurementSystem.metric
                                ? horizontal
                                : MeasurementUnits.inchesToMeters(horizontal);
                            final offsetZ = measurementSystem ==
                                    MeasurementSystem.metric
                                ? vertical
                                : MeasurementUnits.inchesToMeters(vertical);
                            Navigator.pop(
                              dialogContext,
                              _PreciseTransformInput(
                                offsetX: offsetX,
                                offsetZ: offsetZ,
                                angleDegrees: rotation,
                              ),
                            );
                          },
                          child: Text(localizations.applyAdjustment),
                        ),
                      ],
                    ),
                  );
                },
              );
              horizontalController.dispose();
              verticalController.dispose();
              rotationController.dispose();

              if (input == null) {
                return;
              }
              final applied = await provider.transformRoomPrecisely(
                roomId: selectedRoomId,
                offsetX: input.offsetX,
                offsetZ: input.offsetZ,
                angleDegrees: input.angleDegrees,
              );
              if (context.mounted) {
                setModalState(() {});
              }
              if (!mounted) {
                return;
              }
              _showMessage(
                applied
                    ? localizations.preciseAdjustmentApplied
                    : localizations.unsafeMovementRejected,
                error: !applied,
              );
            }

            Future<void> alignNearestWall() async {
              final previewResult = provider.createWallAlignmentPreview(
                roomId: selectedRoomId,
              );
              final preview = previewResult.preview;
              if (preview == null) {
                _showMessage(
                  previewResult.status ==
                          WallAlignmentPreviewStatus.overlapPrevented
                      ? localizations.joinOverlapPrevented
                      : localizations.noSafeNearbyWall,
                  error: true,
                );
                return;
              }

              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(localizations.alignmentPreviewTitle),
                  content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          localizations.alignmentPreviewMessage,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        AspectRatio(
                          aspectRatio: 1.5,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F8FA),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFD8DCE2),
                              ),
                            ),
                            child: CustomPaint(
                              painter: _AlignmentPreviewPainter(
                                preview: preview,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 18,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _PreviewLegend(
                              color: const Color(0xFFFF8A00),
                              label: localizations.alignmentCurrentPosition,
                            ),
                            _PreviewLegend(
                              color: const Color(0xFF00A86B),
                              label: localizations.alignmentProposedPosition,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(localizations.cancel),
                    ),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      icon: const Icon(Icons.check),
                      label: Text(localizations.applyAlignment),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !mounted) {
                return;
              }

              final result =
                  await provider.applyWallAlignmentPreview(preview);
              if (context.mounted) {
                setModalState(() {});
              }
              if (!mounted) {
                return;
              }
              _showMessage(
                result == WallAlignmentResult.aligned
                    ? localizations.wallAlignedSuccessfully
                    : result == WallAlignmentResult.stalePreview
                        ? localizations.alignmentPreviewExpired
                        : localizations.noSafeNearbyWall,
                error: result != WallAlignmentResult.aligned,
              );
            }

            Future<void> joinSelectedRooms() async {
              final destinationId = targetRoomId;
              if (destinationId == null) {
                _showMessage(
                  localizations.noIndependentRoomAvailable,
                  error: true,
                );
                return;
              }

              final sourceRoom = rooms.firstWhere(
                (room) => room.id == selectedRoomId,
              );
              final targetRoom = rooms.firstWhere(
                (room) => room.id == destinationId,
              );
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(localizations.joinPreviewTitle),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.join_inner_rounded,
                        size: 48,
                        color: Color(0xFF00A86B),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        localizations.joinPreviewMessage(
                          sourceRoom.name,
                          targetRoom.name,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(localizations.cancel),
                    ),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      icon: const Icon(Icons.check),
                      label: Text(localizations.applyJoin),
                    ),
                  ],
                ),
              );

              if (confirmed != true) return;

              final result = await provider.joinRooms(
                sourceRoomId: selectedRoomId,
                targetRoomId: destinationId,
              );
              if (context.mounted) {
                setModalState(() {});
              }
              if (!mounted) return;

              _showMessage(
                result == WallAlignmentResult.aligned
                    ? localizations.joinCompleted
                    : result == WallAlignmentResult.overlapPrevented
                        ? localizations.joinOverlapPrevented
                        : localizations.noSafeNearbyWall,
                error: result != WallAlignmentResult.aligned,
              );
            }

            Widget movementButton({
              required IconData icon,
              required String tooltip,
              required VoidCallback onPressed,
            }) {
              return Tooltip(
                message: tooltip,
                child: SizedBox(
                  width: 58,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: onPressed,
                    child: Icon(icon),
                  ),
                ),
              );
            }

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                24 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    localizations.transformRoomsTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    localizations.connectedGroupTransformHint,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: provider.canUndoTransform
                              ? undoTransform
                              : null,
                          icon: const Icon(Icons.undo),
                          label: Text(
                            localizations.undoLastTransform,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: provider.canRedoTransform
                              ? redoTransform
                              : null,
                          icon: const Icon(Icons.redo),
                          label: Text(
                            localizations.redoLastTransform,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: alignNearestWall,
                    icon: const Icon(Icons.vertical_align_center),
                    label: Text(localizations.alignNearestWall),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: targetRoomId == null
                        ? null
                        : joinSelectedRooms,
                    icon: const Icon(Icons.join_inner_rounded),
                    label: Text(localizations.joinRooms),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    value: selectedRoomId,
                    decoration: InputDecoration(
                      labelText: localizations.selectedRoom,
                      border: const OutlineInputBorder(),
                    ),
                    items: rooms
                        .map(
                          (room) => DropdownMenuItem<String>(
                            value: room.id,
                            child: Text(room.name),
                          ),
                        )
                        .toList(),
                    onChanged: (roomId) {
                      if (roomId == null) {
                        return;
                      }

                      setModalState(() {
                        selectedRoomId = roomId;
                        final availableTargets = rooms.where(
                          (room) => provider.canJoinRoomPair(
                            sourceRoomId: roomId,
                            targetRoomId: room.id,
                          ),
                        );
                        if (targetRoomId == null ||
                            !availableTargets.any(
                              (room) => room.id == targetRoomId,
                            )) {
                          targetRoomId = availableTargets
                              .map((room) => room.id)
                              .firstOrNull;
                        }
                      });
                      setState(() {
                        _selectedRoomId = roomId;
                        _selectedFeatureId = null;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: targetRoomId,
                    decoration: InputDecoration(
                      labelText: localizations.roomToJoin,
                      border: const OutlineInputBorder(),
                    ),
                    items: rooms
                        .where(
                          (room) => provider.canJoinRoomPair(
                            sourceRoomId: selectedRoomId,
                            targetRoomId: room.id,
                          ),
                        )
                        .map(
                          (room) => DropdownMenuItem<String>(
                            value: room.id,
                            child: Text(room.name),
                          ),
                        )
                        .toList(),
                    onChanged: (roomId) {
                      setModalState(() {
                        targetRoomId = roomId;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<double>(
                    value: movementStep,
                    decoration: InputDecoration(
                      labelText: localizations.movementDistance,
                      border: const OutlineInputBorder(),                    ),
                    items: measurementSystem == MeasurementSystem.metric                        ? [
                            DropdownMenuItem(
                              value: 0.05,
                              child: Text(localizations.fiveCentimeters),
                            ),
                            DropdownMenuItem(
                              value: 0.10,
                              child: Text(localizations.tenCentimeters),
                            ),                            DropdownMenuItem(
                              value: 0.25,
                              child: Text(
                                localizations.twentyFiveCentimeters,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 0.50,                              child: Text(localizations.fiftyCentimeters),
                            ),
                          ]
                        : [
                            DropdownMenuItem(
                              value: MeasurementUnits.inchesToMeters(1),
                              child: Text(localizations.oneInch),
                            ),
                            DropdownMenuItem(
                              value: MeasurementUnits.inchesToMeters(3),
                              child: Text(localizations.threeInches),
                            ),
                            DropdownMenuItem(
                              value: MeasurementUnits.inchesToMeters(6),
                              child: Text(localizations.sixInches),
                            ),
                            DropdownMenuItem(
                              value: MeasurementUnits.metersPerFoot,
                              child: Text(localizations.oneFoot),
                            ),
                          ],
                    onChanged: (step) {
                      if (step == null) {
                        return;
                      }
                      setModalState(() {
                        movementStep = step;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: applyPreciseAdjustment,
                    icon: const Icon(Icons.tune_rounded),
                    label: Text(localizations.preciseAdjustment),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    localizations.movement,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Column(
                      children: [
                        movementButton(
                          icon: Icons.keyboard_arrow_up,
                          tooltip: localizations.moveUp,
                          onPressed: () async {
                            await moveRoom(
                              offsetX: 0,
                              offsetZ: -movementStep,
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            movementButton(
                              icon: Icons.keyboard_arrow_left,
                              tooltip: localizations.moveLeft,
                              onPressed: () async {
                                await moveRoom(
                                  offsetX: -movementStep,
                                  offsetZ: 0,
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            movementButton(
                              icon: Icons.keyboard_arrow_down,
                              tooltip: localizations.moveDown,
                              onPressed: () async {
                                await moveRoom(
                                  offsetX: 0,
                                  offsetZ: movementStep,
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            movementButton(
                              icon: Icons.keyboard_arrow_right,
                              tooltip: localizations.moveRight,
                              onPressed: () async {
                                await moveRoom(
                                  offsetX: movementStep,
                                  offsetZ: 0,
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    localizations.rotation,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await rotateRoom(-15);
                          },
                          icon: const Icon(Icons.rotate_left),
                          label: Text(
                            localizations.rotateFifteenDegreesLeft,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await rotateRoom(15);
                          },
                          icon: const Icon(Icons.rotate_right),
                          label: Text(
                            localizations.rotateFifteenDegreesRight,
                            textAlign: TextAlign.center,
                          ),
                        ),                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(bottomSheetContext).pop(),
                    icon: const Icon(Icons.check),
                    label: Text(localizations.finishEditing),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAreaSummary() async {
    final provider = context.read<FloorPlanProvider>();
    final measurementSystem =
        context.read<MeasurementSettingsProvider>().system;
    final localizations = AppLocalizations.of(context)!;
    final rooms = provider.completedRooms;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.areaSummaryTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final room in rooms)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(room.name),
                    trailing: Text(
                      room.isClosed
                          ? _formatArea(
                              GeometryService.calculateArea(room.points),
                              measurementSystem,
                            )
                          : localizations.planOpenContour,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    localizations.totalAreaLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: Text(
                    _formatArea(
                      provider.totalProjectArea,
                      measurementSystem,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(localizations.close),
          ),
        ],
      ),
    );
  }

  @override  Widget build(
    BuildContext context,
  ) {
    final measurementSystem = context
        .watch<MeasurementSettingsProvider>()
        .system;
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
          widget.selectContinuationOpening
              ? localizations.chooseOpeningToContinue
              : localizations.floorPlan2D,
        ),
        centerTitle: true,
        actions: widget.selectContinuationOpening ? const [] : [
          if (_roomPlanSupported)
            IconButton(
              icon: _roomPlanScanning
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.view_in_ar_outlined),
              tooltip: localizations.scanWithRoomPlan,
              onPressed: _roomPlanScanning ? null : _captureWithRoomPlan,
            ),
          PopupMenuButton<
              _FloorPlanAction>(
            tooltip: localizations.moreOptions,
            onSelected: (action) {
              switch (action) {
                case _FloorPlanAction.transformRooms:
                  _toggleTouchTransformMode();
                  break;
                case _FloorPlanAction.organizeRooms:
                  _organizeRooms();
                  break;
                case _FloorPlanAction.areaSummary:
                  _showAreaSummary();
                  break;
                case _FloorPlanAction.importProject:
                  _importProject();
                  break;
                case _FloorPlanAction.exportProject:
                  _showExportFlow();
                  break;
              }
            },
            itemBuilder: (context) {
              return [
                PopupMenuItem(
                  value: _FloorPlanAction.transformRooms,
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      _touchTransformMode
                          ? Icons.check
                          : Icons.open_with_rounded,
                    ),
                    title: Text(
                      _touchTransformMode
                          ? localizations.finishEditing
                          : localizations.touchTransformRooms,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: _FloorPlanAction.organizeRooms,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.grid_view_rounded),
                    title: Text(localizations.organizeRooms),
                  ),
                ),
                PopupMenuItem(
                  value: _FloorPlanAction.areaSummary,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.straighten_outlined),
                    title: Text(localizations.areaSummaryTitle),
                  ),
                ),
                PopupMenuItem(
                  value: _FloorPlanAction.exportProject,
                  enabled: context.read<FloorPlanProvider>().completedRooms
                      .any((room) => room.points.length >= 2),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.file_download_outlined),
                    title: Text(localizations.exportProject),
                  ),
                ),
                PopupMenuItem(
                  value:
                      _FloorPlanAction
                          .importProject,
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.file_upload,
                    ),
                    title: Text(
                      localizations.importProject,
                    ),
                  ),
                ),
              ];
            },
          ),
        ],
      ),

      bottomNavigationBar: widget.selectContinuationOpening ? null : _buildPlanToolbar(),

      body: Consumer<
          FloorPlanProvider>(
        builder: (
          context,
          provider,
          child,
        ) {
          final rooms = _roomsForDisplay(provider.completedRooms);
          final hasAvailableOpenings = rooms.any(
            (room) => room.features.any((feature) => !feature.isConnected),
          );

          if (rooms.isEmpty) {
            return const _EmptyPlanView();
          }
          return LayoutBuilder(
            builder: (              context,
              constraints,
            ) {
              final size =
                  constraints.biggest;

              if (!_touchTransformMode && !_freezePlanTransform) {
                _calculateTransform(size, rooms);
              }

              return Stack(                children: [
                  InteractiveViewer(
                    transformationController: _planViewport,
                    panEnabled: !_touchTransformMode && !_wallGestureActive,
                    scaleEnabled: !_touchTransformMode && !_wallGestureActive,
                    constrained: true,
                    boundaryMargin:
                        const EdgeInsets.all(
                      200,
                    ),
                    minScale: 0.2,
                    maxScale: 6.0,
                    child:
                        GestureDetector(
                      dragStartBehavior: DragStartBehavior.down,
                      behavior:
                          HitTestBehavior
                              .opaque,
                      onTapUp: (
                        details,
                      ) async {
                        if (_choosingContinuationClosing ||
                            _addOpeningType != null ||
                            _wallEditMode ||
                            _pendingPlanEdit != null) {
                          await _selectPlanElement(details.localPosition, provider.completedRooms);
                          return;
                        }
                        if (_touchTransformMode) {
                          final roomId = _getRoomAtPosition(
                            _inverseTransform(details.localPosition),
                            rooms,
                          );
                          if (roomId != null) {
                            setState(() {
                              _selectedRoomId = roomId;
                              _selectedFeatureId = null;
                            });
                          }
                          return;
                        }
                        final featureSelection =
                            _getFeatureAtPosition(
                          details.localPosition,
                          rooms,
                        );

                        if (featureSelection != null) {
                          if (widget.selectContinuationOpening &&
                              featureSelection.feature.isConnected) {
                            return;
                          }
                          _showFeatureMenu(
                            featureSelection,
                          );
                          return;
                        }

                        if (widget.selectContinuationOpening) {
                          return;
                        }

                        if (await _selectPlanElement(details.localPosition, provider.completedRooms)) return;
                        if (!mounted) return;

                        final planePoint =
                            _inverseTransform(
                          details                              .localPosition,                        );
                        final roomId =
                            _getRoomAtPosition(
                          planePoint,
                          rooms,
                        );

                        if (roomId ==
                            null) {
                          _showMessage(
                            localizations.tapRoomToAddOpening,
                          );
                          return;
                        }

                        _showAddFeatureMenu(
                          roomId:
                              roomId,
                          location:
                              planePoint,
                        );
                      },
                      onScaleStart: _wallGestureActive
                          ? (details) => _startWallDrag(details, provider.completedRooms)
                          : _touchTransformMode
                          ? (details) => _startTouchTransform(details, rooms)
                          : null,
                      onScaleUpdate: _wallGestureActive ? _updateWallDrag :
                          _touchTransformMode ? _updateTouchTransform : null,
                      onScaleEnd: _wallGestureActive ? (_) => _endWallDrag() : _touchTransformMode
                          ? (_) => _endTouchTransform()
                          : null,
                      child:
                          _trackPlanPointer(SizedBox.expand(
                        child:
                            CustomPaint(
                          foregroundPainter: _planSelectionPainter(rooms),
                          painter:
                              FloorPlanPainter(
                            rooms:
                                rooms,
                            transform:
                                _transformPoint,
                            selectedRoomId:
                                _selectedRoomId,
                            selectedFeatureId:
                                _selectedFeatureId,
                            formatLength: (length) =>
                                _formatLength(
                              length,
                              measurementSystem,
                            ),
                            formatOpeningDimensions: (feature) =>
                                _formatOpeningPlanDimensions(
                              feature,
                              measurementSystem,
                            ),
                            sharedWallLabel:
                                localizations.sharedWall,
                            partialSharedWallLabel:
                                localizations.partialSharedWall,
                            openRoomLabel: localizations.planOpenContour,
                            continuationSelectionMode:
                                widget.selectContinuationOpening,
                          ),
                        ),
                      )),
                    ),
                  ),

                  if (_touchTransformMode)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 18,
                      child: SafeArea(
                        child: Material(
                          color: Theme.of(context).colorScheme.surfaceContainerHigh,
                          elevation: 6,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.touch_app_rounded),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        localizations.touchTransformExplanation,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      tooltip: localizations.zoomOut,
                                      onPressed: () => _zoomPlan(0.8),
                                      icon: const Icon(Icons.zoom_out),
                                    ),
                                    IconButton(
                                      tooltip: localizations.resetView,
                                      onPressed: _resetPlanZoom,
                                      icon: const Icon(Icons.center_focus_strong),
                                    ),
                                    IconButton(
                                      tooltip: localizations.zoomIn,
                                      onPressed: () => _zoomPlan(1.25),
                                      icon: const Icon(Icons.zoom_in),
                                    ),
                                    IconButton(
                                      tooltip: localizations.transformRoomsTitle,
                                      onPressed: _showRoomTransformEditor,
                                      icon: const Icon(Icons.tune_rounded),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  Positioned(
                    left: 12,
                    top: 12,
                    child:
                        IgnorePointer(
                      child: Container(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 12,
                          vertical: 8,                        ),                        decoration:
                            BoxDecoration(
                          color: Colors
                              .black
                              .withOpacity(
                            0.72,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(
                            12,
                          ),
                        ),
                        child: Text(
                          '${localizations.roomCount(rooms.length)} · '
                          '${_formatArea(provider.totalProjectArea, measurementSystem)}',
                          style:
                              const TextStyle(
                            color:
                                Colors.white,
                            fontWeight:
                                FontWeight
                                    .w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.selectContinuationOpening)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 20,
                      child: SafeArea(
                        child: Card(
                          color: hasAvailableOpenings
                              ? const Color(0xFF0D5C3D)
                              : Theme.of(context).colorScheme.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              hasAvailableOpenings
                                  ? localizations.chooseOpeningToContinue
                                  : localizations.noAvailableOpenings,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: hasAvailableOpenings
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ===========================================================================
  // IMPORTAR / EXPORTAR
  // ===========================================================================

  Future<void> _importProject() async {
    final localizations = AppLocalizations.of(context)!;
    final provider =
        context.read<
            FloorPlanProvider>();
    final result =
        await ImportExportService
            .importProject(
      provider,
      confirmReplacement: () async {
        if (provider.completedRooms.isEmpty) return true;
        return await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(localizations.replaceProjectTitle),
                content: Text(localizations.replaceProjectMessage),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(localizations.cancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(localizations.importProject),
                  ),
                ],
              ),
            ) ??
            false;
      },
    );
    if (!mounted) {
      return;
    }

    switch (result) {
      case JsonImportResult.imported:
        _showMessage(
          localizations.planImportedSuccessfully,
        );
        break;
      case JsonImportResult.cancelled:
        return;
      case JsonImportResult.invalid:
        _showMessage(
          localizations.planImportInvalid,
          error: true,
        );
        break;
    }
  }

  Future<void> _showExportFlow() async {
    final localizations = AppLocalizations.of(context)!;
    final format = await showDialog<_ExportFormat>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(localizations.exportProject),
        children: [
          for (final format in _ExportFormat.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, format),
              child: Text(format.label(localizations)),
            ),
        ],
      ),
    );
    if (format == null || !mounted) return;
    final destination = await showDialog<ExportDestination>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(localizations.exportDestination),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(
              dialogContext,
              ExportDestination.saveToFiles,
            ),
            child: Text(localizations.saveToFiles),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(
              dialogContext,
              ExportDestination.share,
            ),
            child: Text(localizations.shareFile),
          ),
        ],
      ),
    );
    if (destination == null || !mounted) return;
    switch (format) {
      case _ExportFormat.json:
        await _saveJson(destination);
        break;
      case _ExportFormat.svg:
        await _exportSvg(destination);
        break;
      case _ExportFormat.png:
        await _exportRaster(destination, jpeg: false);
        break;
      case _ExportFormat.jpg:
        await _exportRaster(destination, jpeg: true);
        break;
      case _ExportFormat.pdf:
        await _exportPdf(destination);
        break;
      case _ExportFormat.dxf:
        await _exportDxf(destination);
        break;
    }
  }

  Rect _shareOrigin() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    final size = MediaQuery.sizeOf(context);
    return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
  }

  Future<void> _saveJson(ExportDestination destination) async {
    final localizations = AppLocalizations.of(context)!;
    final provider =
        context.read<
            FloorPlanProvider>();

    try {
      await ImportExportService
          .exportToJson(
        provider.completedRooms,
        provider.projectName,
        destination: destination,
        sharePositionOrigin: _shareOrigin(),
      );
    } catch (_) {
      if (mounted) {
        _showMessage(localizations.fileSaveFailed, error: true);
      }
    }
  }

  bool _exportingDxf = false;

  Future<void> _exportDxf(ExportDestination destination) async {
    if (_exportingDxf) return;
    final localizations = AppLocalizations.of(context)!;
    final provider = context.read<FloorPlanProvider>();
    _exportingDxf = true;
    try {
      await ImportExportService.exportToDxf(
        provider.completedRooms, provider.projectName,
        languageCode: Localizations.localeOf(context).languageCode,
        destination: destination,
        sharePositionOrigin: _shareOrigin(),
      );
    } catch (_) {
      if (mounted) _showMessage(localizations.fileSaveFailed, error: true);
    } finally {
      _exportingDxf = false;
    }
  }

  Future<void> _exportPdf(ExportDestination destination) async {
    final localizations = AppLocalizations.of(context)!;
    final provider =
        context.read<
            FloorPlanProvider>();

    try {
      await ImportExportService
          .exportToPdf(
        provider.completedRooms,
        provider.projectName,
        context.read<MeasurementSettingsProvider>().system,
        languageCode: Localizations.localeOf(context).languageCode,
        destination: destination,
        sharePositionOrigin: _shareOrigin(),
      );
    } catch (_) {
      if (mounted) {
        _showMessage(localizations.fileSaveFailed, error: true);
      }
    }
  }

  Future<void> _exportSvg(ExportDestination destination) async {
    final localizations = AppLocalizations.of(context)!;
    final provider = context.read<FloorPlanProvider>();
    try {
      await ImportExportService.exportToSvg(
        provider.completedRooms,
        provider.projectName,
        context.read<MeasurementSettingsProvider>().system,
        languageCode: Localizations.localeOf(context).languageCode,
        destination: destination,
        sharePositionOrigin: _shareOrigin(),
      );
    } catch (_) {
      if (mounted) _showMessage(localizations.fileSaveFailed, error: true);
    }
  }

  Future<void> _exportRaster(
    ExportDestination destination, {
    required bool jpeg,
  }) async {
    final localizations = AppLocalizations.of(context)!;
    final provider = context.read<FloorPlanProvider>();
    try {
      await ImportExportService.exportToRasterImage(
        provider.completedRooms,
        provider.projectName,
        context.read<MeasurementSettingsProvider>().system,
        languageCode: Localizations.localeOf(context).languageCode,
        jpeg: jpeg,
        destination: destination,
        sharePositionOrigin: _shareOrigin(),
      );
    } catch (_) {
      if (mounted) _showMessage(localizations.fileSaveFailed, error: true);
    }
  }
  // ===========================================================================
  // PUERTAS / VENTANAS
  // ===========================================================================  Future<void>
      _showAddFeatureMenu({
    required String roomId,
    required ARPoint location,
  }) async {
    final localizations = AppLocalizations.of(context)!;
    final selected =
        await showModalBottomSheet<
            FeatureType>(
      context: context,
      builder: (
        bottomSheetContext,
      ) {
        return SafeArea(
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons
                      .add_location_alt,
                ),
                title: Text(
                  localizations.addElement,
                ),
                subtitle: Text(
                  localizations.selectElementToAdd,
                ),
              ),
              const Divider(
                height: 1,
              ),
              ListTile(
                leading:
                    const Icon(
                  Icons
                      .door_front_door,
                  color:
                      Colors.red,
                ),
                title: Text(localizations.door),
                onTap: () {
                  Navigator.pop(
                    bottomSheetContext,
                    FeatureType.door,                  );
                },
              ),
              ListTile(
                leading:
                    const Icon(
                  Icons.window,
                  color:
                      Colors.blue,
                ),
                title: Text(localizations.window),
                onTap: () {
                  Navigator.pop(
                    bottomSheetContext,
                    FeatureType.window,
                  );
                },
              ),
              const SizedBox(
                height: 8,
              ),
            ],
          ),
        );
      },
    );

    if (selected == null ||
        !mounted) {
      return;
    }

    await _placeOpeningOnWall(roomId, selected);
  }

  @override
  Future<void> _placeOpeningOnWall(
    String roomId, FeatureType type, {WallFeature? feature, int? initialWallIndex, ARPoint? initialLocation}
  ) async {
    final provider = context.read<FloorPlanProvider>();
    final room = provider.completedRooms.where((r) => r.id == roomId).firstOrNull;
    if (room == null || room.points.length < 2) return;
    final placement = await showOpeningPlacementDialog(
      context: context, room: room, type: type,
      system: context.read<MeasurementSettingsProvider>().system,
      initialFeature: feature,
      initialWallIndex: initialWallIndex, initialLocation: initialLocation,
      includeClosingWall: room.isClosed,
    );
    if (!mounted || placement == null) return;
    final current = provider.completedRooms.where((r) => r.id == roomId).firstOrNull;
    if (!identical(current, room)) return;
    final result = await provider.placeOpeningOnWall(
      roomId: roomId, type: type, featureId: feature?.id,
      wallIndex: placement.wallIndex, location: placement.location,
      widthMeters: placement.width,
      openingHeightMeters: placement.openingHeightMeters,
      sillHeightMeters: placement.sillHeightMeters,
    );
    if (!mounted) return;
    _showMessage(result.isSuccess
        ? AppLocalizations.of(context)!.openingUpdated
        : result.errorMessage ?? AppLocalizations.of(context)!.invalidOpeningMeasurement,
        error: !result.isSuccess);
  }

  @override
  Future<void> _showRoomListDialog() async {
    ModalRoute<dynamic>? roomListRoute;
    final action =
        await showModalBottomSheet<
            _RoomListAction>(      context: context,
      isScrollControlled: true,      builder: (
        bottomSheetContext,
      ) {
        roomListRoute = ModalRoute.of(bottomSheetContext);
        return Consumer<
            FloorPlanProvider>(
          builder: (
            context,
            provider,
            child,
          ) {
            final rooms =
                provider.completedRooms;
            final localizations = AppLocalizations.of(context)!;
            final measurementSystem = context
                .watch<MeasurementSettingsProvider>()
                .system;

            return SafeArea(
              child: Padding(
                padding:                    const EdgeInsets
                        .fromLTRB(                  16,
                  16,
                  16,
                  24,
                ),
                child: Column(                  mainAxisSize:
                      MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            localizations.registeredRooms,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: localizations.close,
                          onPressed: () {
                            Navigator.pop(
                              bottomSheetContext,
                            );
                          },                          icon: const Icon(
                            Icons.close,
                          ),
                        ),
                      ],                    ),
                    const SizedBox(
                      height: 8,
                    ),

                    if (rooms.isEmpty)
                      Padding(
                        padding:
                            const
                            EdgeInsets.symmetric(
                          vertical: 32,
                        ),
                        child: Center(
                          child: Text(
                            localizations.noRoomsYet,
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child:
                            ListView.separated(
                          shrinkWrap: true,
                          itemCount:
                              rooms.length,
                          separatorBuilder:
                              (
                            context,                            index,
                          ) =>
                                  const Divider(
                            height: 1,
                          ),
                          itemBuilder:
                              (
                            context,
                            index,
                          ) {
                            final room =
                                rooms[index];

                            final area = PlanEditGeometry.area(room);
                            final perimeter = PlanEditGeometry.perimeter(room);

                            return ListTile(
                              contentPadding:
                                  EdgeInsets.zero,
                              leading:
                                  CircleAvatar(
                                child: Text(
                                  '${index + 1}',
                                ),
                              ),
                              title: Text(
                                room.name,
                              ),
                              subtitle: Text(
                                localizations.roomSummary(
                                  room.isClosed ? _formatArea(area, measurementSystem) : localizations.planOpenContour,
                                  _formatLength(perimeter, measurementSystem),
                                  room.points.length,
                                ),
                              ),
                              trailing:
                                  PopupMenuButton<
                                      _RoomListActionType>(
                                key: ValueKey('room-actions-${room.id}'),
                                tooltip: localizations.actions,
                                onSelected:
                                    (
                                  type,
                                ) {
                                  Navigator.pop(
                                    bottomSheetContext,
                                    _RoomListAction(
                                      type: type,
                                      roomId:
                                          room.id,
                                    ),
                                  );
                                },
                                itemBuilder:
                                    (
                                  context,
                                ) {
                                  return [
                                    PopupMenuItem(
                                      value:
                                          _RoomListActionType
                                              .editMeasurements,
                                      child:
                                          ListTile(
                                        dense: true,
                                        leading:
                                            Icon(
                                          Icons
                                              .straighten_outlined,
                                        ),
                                        title:
                                            Text(
                                          localizations.editMeasurements,
                                        ),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value:
                                          _RoomListActionType
                                              .rename,
                                      child:
                                          ListTile(
                                        dense: true,
                                        leading:
                                            Icon(
                                          Icons
                                              .edit_outlined,
                                        ),
                                        title:
                                            Text(
                                          localizations.rename,
                                        ),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: _RoomListActionType.delete,
                                      child: ListTile(
                                        dense: true,
                                        leading: const Icon(Icons.delete_forever_outlined),
                                        title: Text(localizations.planDeleteRoom),
                                      ),
                                    ),
                                  ];
                                },
                              ),
                            );
                          },
                        ),
                      ),

                    if (rooms.length >
                        1) ...[
                      const SizedBox(
                        height: 12,
                      ),
                      SizedBox(
                        width:
                            double.infinity,
                        child:
                            OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(
                              bottomSheetContext,
                              const _RoomListAction(
                                type:
                                    _RoomListActionType
                                        .organize,
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons
                                .grid_view_rounded,
                          ),
                          label: Text(
                            localizations.organizeRooms,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    await roomListRoute?.completed;
    if (action == null ||
        !mounted) {
      return;
    }

    switch (action.type) {
      case _RoomListActionType.delete:
        final room = _findRoom(action.roomId);
        if (room != null) await _deletePlanRoom(room);
        break;
      case _RoomListActionType
            .editMeasurements:
        await _openMeasurementEditor(
          roomId:
              action.roomId,
        );
        break;

      case _RoomListActionType
            .rename:
        final room =
            _findRoom(
          action.roomId,
        );
        if (room != null) {
          await _editRoomName(
            room,          );
        }
        break;

      case _RoomListActionType
            .organize:
        await _organizeRooms();
        break;
    }
  }

  RoomModel? _findRoom(
    String? roomId,
  ) {
    if (roomId == null) {
      return null;
    }

    final rooms =
        context
            .read<
                FloorPlanProvider>()
            .completedRooms;

    for (final room in rooms) {
      if (room.id ==
          roomId) {
        return room;
      }    }
    return null;
  }

  // ===========================================================================
  // RENOMBRAR AMBIENTE
  // ===========================================================================

  Future<void> _editRoomName(
    RoomModel room,
  ) async {
    final localizations = AppLocalizations.of(context)!;
    final controller =
        TextEditingController(      text: room.name,
    );

    final newName =
        await showDialog<String>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: Text(
            localizations.renameRoom,
          ),
          content: TextField(
            controller:
                controller,
            autofocus: true,
            textCapitalization:
                TextCapitalization
                    .sentences,
            decoration:
                InputDecoration(
              labelText: localizations.roomNameShortLabel,
              hintText:
                  localizations.roomNameMainBedroomExample,
              border:
                  const OutlineInputBorder(),
            ),
            onSubmitted:
                (value) {
              Navigator.pop(
                dialogContext,
                value.trim(),
              );
            },
          ),
          actions: [
            TextButton(              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child: Text(
                localizations.cancel,
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  controller.text
                      .trim(),
                );
              },
              child: Text(
                localizations.save,              ),
            ),
          ],
        );      },
    );

    controller.dispose();
    if (newName == null ||
        newName.trim().isEmpty ||        !mounted) {
      return;
    }

    await context
        .read<FloorPlanProvider>()
        .updateRoomName(
          room.id,
          newName.trim(),
        );
  }

  // ===========================================================================
  // MENSAJES
  // ===========================================================================

  @override
  void _showMessage(
    String message, {
    bool error = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior:
              SnackBarBehavior.floating,
          backgroundColor:
              error
                  ? Colors.red.shade700
                  : null,
          content: Text(            message,
          ),
        ),
      );
  }
}
// =============================================================================
// ACCIONES
// =============================================================================
enum _FloorPlanAction {
  transformRooms,
  organizeRooms,
  areaSummary,
  importProject,
  exportProject,
}

enum _ExportFormat { json, svg, png, jpg, pdf, dxf }

extension on _ExportFormat {
  String label(AppLocalizations localizations) => switch (this) {
        _ExportFormat.json => localizations.exportJson,
        _ExportFormat.svg => localizations.exportSvg,
        _ExportFormat.png => localizations.exportPng,
        _ExportFormat.jpg => localizations.exportJpg,
        _ExportFormat.pdf => localizations.exportPdf,
        _ExportFormat.dxf => localizations.exportDxf,
      };
}
enum _RoomListActionType {
  delete,
  editMeasurements,
  rename,
  organize,
}
class _RoomListAction {
  final _RoomListActionType type;

  final String? roomId;

  const _RoomListAction({
    required this.type,
    this.roomId,
  });
}

enum _FeatureMenuAction {
  move,
  delete,
  continueScanning,
  editGeometry,
  toggleHinge,
  chooseOpeningDirection,
}

class _OpeningGeometryInput {
  final double widthMeters;
  final double distanceFromWallStartMeters;
  final double openingHeightMeters;
  final double sillHeightMeters;

  const _OpeningGeometryInput({
    required this.widthMeters,
    required this.distanceFromWallStartMeters,
    required this.openingHeightMeters,
    required this.sillHeightMeters,
  });
}

class _FeatureSelection {
  final String roomId;
  final WallFeature feature;

  const _FeatureSelection({
    required this.roomId,
    required this.feature,
  });
}

class _OpeningDirectionPainter extends CustomPainter {
  final Offset openingDirection;

  const _OpeningDirectionPainter({
    required this.openingDirection,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final midpoint = Offset(
      size.width / 2.0,
      size.height / 2.0,
    );
    final length = openingDirection.distance;
    final tangent = length <= 0.000001
        ? const Offset(1, 0)
        : openingDirection / length;
    final normal = Offset(-tangent.dy, tangent.dx);
    final halfOpening = size.shortestSide * 0.42;
    final arrowLength = size.shortestSide * 0.35;
    final start = midpoint - tangent * halfOpening;
    final end = midpoint + tangent * halfOpening;

    final openingPaint = Paint()
      ..color = const Color(0xFFFF8A00)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final arrowPaint = Paint()
      ..color = const Color(0xFF00C853)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(start, end, openingPaint);
    _drawArrow(
      canvas,      midpoint,
      midpoint + normal * arrowLength,
      arrowPaint,
    );
    _drawArrow(
      canvas,
      midpoint,
      midpoint - normal * arrowLength,
      arrowPaint,
    );
    canvas.drawCircle(
      start,
      9,
      Paint()..color = const Color(0xFF00C853),
    );
    canvas.drawCircle(
      start,
      3,
      Paint()..color = Colors.white,
    );
  }

  void _drawArrow(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    canvas.drawLine(start, end, paint);
    final delta = end - start;
    final length = delta.distance;

    if (length <= 0.000001) {
      return;
    }

    final direction = delta / length;
    final perpendicular = Offset(-direction.dy, direction.dx);
    canvas.drawLine(
      end,
      end - direction * 10 + perpendicular * 8,
      paint,
    );
    canvas.drawLine(
      end,
      end - direction * 10 - perpendicular * 8,
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _OpeningDirectionPainter oldDelegate,
  ) => false;
}

class _EmptyPlanView extends StatelessWidget {
  const _EmptyPlanView();

  @override
  Widget build(
    BuildContext context,
  ) {
    final localizations = AppLocalizations.of(context)!;
    return Center(
      child: Padding(        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            const Icon(
              Icons
                  .architecture_outlined,
              size: 72,
              color: Colors.black38,
            ),
            const SizedBox(
              height: 16,
            ),
            Text(
              localizations.noScannedRooms,
              style: const TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              localizations.completeScanToViewPlan,
              textAlign:
                  TextAlign.center,              style: const TextStyle(
                color: Colors.black54,              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PAINTER// =============================================================================
class _WallIdentity {
  final String roomId;
  final int wallIndex;

  const _WallIdentity(this.roomId, this.wallIndex);

  @override
  bool operator ==(Object other) =>
      other is _WallIdentity &&
      other.roomId == roomId &&
      other.wallIndex == wallIndex;

  @override
  int get hashCode => Object.hash(roomId, wallIndex);
}

class _WallInterval {
  final double start;
  final double end;

  const _WallInterval(this.start, this.end);
}

class _PreciseTransformInput {
  final double offsetX;
  final double offsetZ;
  final double angleDegrees;

  const _PreciseTransformInput({
    required this.offsetX,
    required this.offsetZ,
    required this.angleDegrees,
  });
}

class _PreviewLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _PreviewLegend({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Text(label),
      ],
    );
  }
}

class _AlignmentPreviewPainter extends CustomPainter {
  final WallAlignmentPreview preview;

  const _AlignmentPreviewPainter({
    required this.preview,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final points = <ARPoint>[
      for (final room in preview.currentRooms) ...room.points,
      for (final room in preview.proposedRooms) ...room.points,
    ];
    if (points.isEmpty || size.isEmpty) {
      return;
    }

    var minX = points.first.x;
    var maxX = points.first.x;
    var minZ = points.first.z;
    var maxZ = points.first.z;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minZ = math.min(minZ, point.z);
      maxZ = math.max(maxZ, point.z);
    }

    const padding = 18.0;
    final width = math.max(maxX - minX, 0.01);
    final height = math.max(maxZ - minZ, 0.01);
    final scale = math.min(
      (size.width - padding * 2) / width,
      (size.height - padding * 2) / height,
    );
    final drawingWidth = width * scale;
    final drawingHeight = height * scale;
    final origin = Offset(
      (size.width - drawingWidth) / 2,
      (size.height - drawingHeight) / 2,
    );

    Offset transform(ARPoint point) => Offset(
          origin.dx + (point.x - minX) * scale,
          origin.dy + (point.z - minZ) * scale,
        );

    void drawRoom(RoomModel room, Paint paint) {
      if (room.points.length < 2) {
        return;
      }
      final path = Path()..moveTo(
          transform(room.points.first).dx,
          transform(room.points.first).dy,
        );
      for (final point in room.points.skip(1)) {
        final transformed = transform(point);
        path.lineTo(transformed.dx, transformed.dy);
      }
      if (room.isClosed && room.points.length >= 3) {
        path.close();
      }
      canvas.drawPath(path, paint);
    }

    final fixedPaint = Paint()
      ..color = const Color(0xFF7B8492).withOpacity(0.55)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final currentPaint = Paint()
      ..color = const Color(0xFFFF8A00)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final proposedPaint = Paint()
      ..color = const Color(0xFF00A86B)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    for (final room in preview.currentRooms) {
      if (!preview.transformedRoomIds.contains(room.id)) {
        drawRoom(room, fixedPaint);
      }
    }
    for (final room in preview.currentRooms) {
      if (preview.transformedRoomIds.contains(room.id)) {
        drawRoom(room, currentPaint);
      }
    }
    for (final room in preview.proposedRooms) {
      if (preview.transformedRoomIds.contains(room.id)) {
        drawRoom(room, proposedPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AlignmentPreviewPainter oldDelegate) {
    return oldDelegate.preview != preview;
  }
}

class FloorPlanPainter
    extends CustomPainter {
  final List<RoomModel> rooms;

  final Offset Function(
    ARPoint,
  ) transform;
  final String? selectedRoomId;
  final String? selectedFeatureId;
  final String Function(double)
      formatLength;
  final String Function(WallFeature)
      formatOpeningDimensions;
  final String sharedWallLabel;
  final String partialSharedWallLabel;
  final String openRoomLabel;
  final bool continuationSelectionMode;

  final List<Rect> _occupiedLabelRects = <Rect>[];

  FloorPlanPainter({
    required this.rooms,
    required this.transform,
    required this.formatLength,
    required this.formatOpeningDimensions,
    required this.sharedWallLabel,
    required this.partialSharedWallLabel,
    this.openRoomLabel = '',
    this.continuationSelectionMode = false,
    this.selectedRoomId,
    this.selectedFeatureId,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,  ) {
    if (rooms.isEmpty) {
      return;
    }

    _occupiedLabelRects.clear();

    final wallPaint =
        Paint()
          ..color =
              const Color(
            0xFF448AFF,
          )
          ..strokeWidth = 3.0
          ..style =
              PaintingStyle.stroke
          ..strokeJoin =
              StrokeJoin.round
          ..strokeCap =
              StrokeCap.round;

    final roomFill =
        Paint()
          ..color =
              const Color(
            0xFF448AFF,
          ).withOpacity(
            0.10,
          )
          ..style =
              PaintingStyle.fill;

    final pointPaint =
        Paint()
          ..color =
              const Color(
            0xFF448AFF,
          )
          ..style =
              PaintingStyle.fill;
    final doorPaint =
        Paint()
          ..color =
              const Color(
            0xFFFF8A00,
          )
          ..strokeWidth = 5.0
          ..style =
              PaintingStyle.stroke
          ..strokeCap =
              StrokeCap.square;

    final windowPaint =
        Paint()
          ..color =
              const Color(
            0xFFD500F9,
          )
          ..strokeWidth = 5.0
          ..style =
              PaintingStyle.stroke
          ..strokeCap =
              StrokeCap.square;

    final selectedPaint = Paint()
      ..color = const Color(0xFF00C853)
      ..strokeWidth = 11.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final referencePaint = Paint()
      ..color = const Color(0xFF00C853)
      ..style = PaintingStyle.fill;
    if (continuationSelectionMode) {
      doorPaint
        ..color = const Color(0xFF00C853)
        ..strokeWidth = 9.0;
      windowPaint
        ..color = const Color(0xFF00C853)
        ..strokeWidth = 9.0;
    }
    final dimensionedFeatureIds = <String>{};
    final featureOwnerRoomIds = <String, String>{};
    final sharedWalls = SharedWallService.detect(rooms: rooms);
    final hiddenWallIntervals =
        _buildHiddenWallIntervals(sharedWalls);
    final hiddenDimensionWalls = hiddenWallIntervals.entries
        .where(
          (entry) => entry.value.any(
            (interval) =>
                interval.start <= 0.000001 &&
                interval.end >= 0.999999,
          ),
        )
        .map((entry) => entry.key)
        .toSet();

    for (final room in rooms) {
      for (final feature in room.features) {
        featureOwnerRoomIds.putIfAbsent(
          feature.id,
          () => room.id,
        );

        if (room.id == selectedRoomId &&
            feature.id == selectedFeatureId) {
          featureOwnerRoomIds[feature.id] = room.id;
        }
      }
    }

    for (final room in rooms) {
      _drawRoom(
        canvas,
        room,
        wallPaint,
        roomFill,
        pointPaint,
        hiddenWallIntervals,
      );

    }

    _drawSharedWalls(
      canvas,
      sharedWalls,
    );

    for (final room in rooms) {

      _drawRoomLabel(
        canvas,
        room,
      );

      _drawFeatures(
        canvas,
        room,
        doorPaint,
        windowPaint,
        selectedPaint,
        referencePaint,
        featureOwnerRoomIds,
      );
      _drawCadDimensions(
        canvas: canvas,
        room: room,
        hiddenDimensionWalls: hiddenDimensionWalls,
        dimensionedFeatureIds: dimensionedFeatureIds,
      );
    }

  }

  // ===========================================================================
  // HABITACIÓN
  // ===========================================================================

  void _drawRoom(
    Canvas canvas,
    RoomModel room,
    Paint wallPaint,
    Paint roomFill,
    Paint pointPaint,
    Map<_WallIdentity, List<_WallInterval>> hiddenWallIntervals,
  ) {
    if (room.points.isEmpty) {
      return;
    }

    final path = Path();

    final start =
        transform(
      room.points.first,
    );

    path.moveTo(
      start.dx,
      start.dy,
    );

    for (
      int i = 1;
      i < room.points.length;      i++
    ) {
      final next =
          transform(
        room.points[i],
      );

      path.lineTo(
        next.dx,
        next.dy,
      );    }
    if (room.isClosed) { path.close();
    }
    if (room.isClosed && room.points.length >= 3) {
      canvas.drawPath(
        path,        roomFill,
      );
    }

    final wallCount = room.isClosed
        ? room.points.length
        : room.points.length - 1;
    for (var wallIndex = 0;
        wallIndex < wallCount;
        wallIndex++) {
      final wallStart = transform(room.points[wallIndex]);
      final wallEnd = transform(
        room.points[(wallIndex + 1) % room.points.length],
      );
      _drawVisibleWallParts(
        canvas: canvas,
        start: wallStart,
        end: wallEnd,
        paint: wallPaint,
        hiddenIntervals: hiddenWallIntervals[
              _WallIdentity(room.id, wallIndex)
            ] ??
            const [],
      );
    }

    for (final point
        in room.points) {
      canvas.drawCircle(
        transform(point),
        4.0,
        pointPaint,
      );
    }
  }

  Map<_WallIdentity, List<_WallInterval>> _buildHiddenWallIntervals(
    List<SharedWallSegment> sharedWalls,
  ) {
    final intervals = <_WallIdentity, List<_WallInterval>>{};
    for (final sharedWall in sharedWalls) {
      final room = rooms.firstWhere(
        (candidate) => candidate.id == sharedWall.secondRoomId,
      );
      final wallStart = room.points[sharedWall.secondWallIndex];
      final wallEnd = room.points[
        (sharedWall.secondWallIndex + 1) % room.points.length
      ];
      final dx = wallEnd.x - wallStart.x;
      final dz = wallEnd.z - wallStart.z;
      final lengthSquared = dx * dx + dz * dz;
      if (lengthSquared <= 0.000001) {
        continue;
      }
      double projection(ARPoint point) {
        return (((point.x - wallStart.x) * dx +
                    (point.z - wallStart.z) * dz) /
                lengthSquared)
            .clamp(0.0, 1.0)
            .toDouble();
      }

      final first = projection(sharedWall.start);
      final second = projection(sharedWall.end);
      intervals
          .putIfAbsent(
            _WallIdentity(
              sharedWall.secondRoomId,
              sharedWall.secondWallIndex,
            ),
            () => [],
          )
          .add(
            _WallInterval(
              math.min(first, second),
              math.max(first, second),
            ),
          );
    }
    return intervals;
  }

  void _drawVisibleWallParts({
    required Canvas canvas,
    required Offset start,
    required Offset end,
    required Paint paint,
    required List<_WallInterval> hiddenIntervals,
  }) {
    if (hiddenIntervals.isEmpty) {
      canvas.drawLine(start, end, paint);
      return;
    }

    final sorted = List<_WallInterval>.from(hiddenIntervals)
      ..sort((first, second) => first.start.compareTo(second.start));
    var visibleStart = 0.0;
    for (final interval in sorted) {
      final hiddenStart = interval.start.clamp(0.0, 1.0).toDouble();
      final hiddenEnd = interval.end.clamp(0.0, 1.0).toDouble();
      if (hiddenStart > visibleStart + 0.000001) {
        canvas.drawLine(
          Offset.lerp(start, end, visibleStart)!,
          Offset.lerp(start, end, hiddenStart)!,
          paint,
        );
      }
      visibleStart = math.max(visibleStart, hiddenEnd);
    }
    if (visibleStart < 1.0 - 0.000001) {
      canvas.drawLine(
        Offset.lerp(start, end, visibleStart)!,
        end,
        paint,
      );
    }
  }

  void _drawSharedWalls(
    Canvas canvas,
    List<SharedWallSegment> sharedWalls,
  ) {
    final completePaint = Paint()
      ..color = const Color(0xFF00695C)
      ..strokeWidth = 4.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final partialPaint = Paint()
      ..color = const Color(0xFF00897B)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final endpointPaint = Paint()
      ..color = const Color(0xFF00897B)
      ..style = PaintingStyle.fill;

    for (final sharedWall in sharedWalls) {
      final start = transform(sharedWall.start);
      final end = transform(sharedWall.end);
      final isPartial =
          sharedWall.coverage == SharedWallCoverage.partial;
      canvas.drawLine(
        start,
        end,
        isPartial ? partialPaint : completePaint,
      );
      if (isPartial) {
        canvas.drawCircle(start, 3.5, endpointPaint);
        canvas.drawCircle(end, 3.5, endpointPaint);
      }
    }
  }

  // ===========================================================================
  // NOMBRE Y SUPERFICIE
  // ===========================================================================

  void _drawRoomLabel(
    Canvas canvas,
    RoomModel room,
  ) {
    if (room.points.isEmpty) {
      return;
    }

    double x = 0.0;    double y = 0.0;

    for (final point
        in room.points) {
      final transformed =
          transform(point);

      x += transformed.dx;
      y += transformed.dy;
    }

    final center = Offset(
      x / room.points.length,
      y / room.points.length,
    );

    final screenBounds = _boundsForPoints(
      room.points.map(transform).toList(growable: false),
    );
    final compact =
        screenBounds.width < 105 || screenBounds.height < 54;

    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: room.name,
            style: TextStyle(
              color: Colors.black87,
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (!room.isClosed)
            TextSpan(
              text: '\n$openRoomLabel',
              style: TextStyle(
                color: Colors.black54,
                fontSize: compact ? 8 : 9,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: room.isClosed ? 1 : 2,
    )..layout(maxWidth: 112);
    final shiftY = math.min(18.0, screenBounds.height * 0.18);
    final shiftX = math.min(24.0, screenBounds.width * 0.16);
    final candidates = <Offset>[
      center,
      center + Offset(0, -shiftY),
      center + Offset(0, shiftY),
      center + Offset(-shiftX, 0),
      center + Offset(shiftX, 0),
    ];
    var labelCenter = center;
    var backgroundRect = Rect.fromCenter(
      center: center,
      width: textPainter.width + 10,
      height: textPainter.height + 6,
    );
    for (final candidate in candidates) {
      final candidateRect = Rect.fromCenter(
        center: candidate,
        width: textPainter.width + 14,
        height: textPainter.height + 10,
      );
      if (_isLabelAreaAvailable(candidateRect)) {
        labelCenter = candidate;
        backgroundRect = candidateRect;
        break;
      }
    }
    _occupiedLabelRects.add(backgroundRect.inflate(2));
    final backgroundPaint =
        Paint()
          ..color = Colors.white
              .withOpacity(
            0.86,
          )
          ..style =
              PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        backgroundRect,
        const Radius.circular(
          7,
        ),
      ),
      backgroundPaint,
    );

    textPainter.paint(
      canvas,
      Offset(
        labelCenter.dx -
            textPainter.width / 2,
        labelCenter.dy -
            textPainter.height / 2,
      ),
    );
  }

  // ===========================================================================
  // COTAS CAD COMPARTIDAS
  // ===========================================================================

  void _drawCadDimensions({
    required Canvas canvas,
    required RoomModel room,
    required Set<_WallIdentity> hiddenDimensionWalls,
    required Set<String> dimensionedFeatureIds,
  }) {
    if (room.points.length < 2) {
      return;
    }

    final hiddenIndexes = <int>{
      for (final identity in hiddenDimensionWalls)
        if (identity.roomId == room.id) identity.wallIndex,
    };

    final dimensions = TechnicalDimensionLayout.forRoom(
      room: room,
      x: (point) => transform(point).dx,
      y: (point) => transform(point).dy,
      includeTotals: true,
      hiddenWallIndexes: hiddenIndexes,
    );

    final placements = DimensionLayout.layout(
      dimensions.map(
        (dimension) {
          if (dimension.kind == DimensionKind.opening) {
            dimensionedFeatureIds.add(dimension.id);
          }
          return dimension;
        },
      ),
      suppressRedundantOverallSegments: true,
      strictHierarchy: true,
    );

    final dimensionPaint = Paint()
      ..color = const Color(0xFF174EA6)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    for (final placement in placements) {
      final dimension = placement.segment;
      final start = Offset(dimension.x1, dimension.y1);
      final end = Offset(dimension.x2, dimension.y2);
      final direction = end - start;
      final screenLength = direction.distance;
      if (screenLength < 8.0) {
        continue;
      }

      final tangent = Offset(placement.tangentX, placement.tangentY);
      final normal = Offset(placement.normalX, placement.normalY);
      final dimensionStart = start + normal * placement.offset;
      final dimensionEnd = end + normal * placement.offset;

      canvas.drawLine(
        start + normal * 5.0,
        start + normal * placement.offset,
        dimensionPaint,
      );
      canvas.drawLine(
        end + normal * 5.0,
        end + normal * placement.offset,
        dimensionPaint,
      );
      canvas.drawLine(dimensionStart, dimensionEnd, dimensionPaint);

      _drawIsoDimensionArrow(
        canvas,
        dimensionStart,
        tangent,
        dimensionPaint,
      );
      _drawIsoDimensionArrow(
        canvas,
        dimensionEnd,
        tangent * -1,
        dimensionPaint,
      );

      final label = switch (dimension.kind) {
        DimensionKind.opening => _openingDimensionLabelForId(
            room,
            dimension.id,
          ),
        DimensionKind.wall => formatLength(
            _dimensionLengthMeters(room, dimension),
          ),
        DimensionKind.total => formatLength(
            _dimensionLengthMeters(room, dimension),
          ),
      };
      if (label.isEmpty) {
        continue;
      }

      final textPainter = _adaptiveTextPainter(
        text: label,
        color: const Color(0xFF174EA6),
        preferredFontSize: dimension.kind == DimensionKind.opening ? 9 : 10,
        minimumFontSize: 7,
        availableWidth: math.max(20.0, screenLength - 8.0),
        maxLines: dimension.kind == DimensionKind.opening ? 2 : 1,
      );
      if (textPainter == null) {
        continue;
      }

      var angle = math.atan2(tangent.dy, tangent.dx);
      if (angle > math.pi / 2 || angle < -math.pi / 2) {
        angle += math.pi;
      }

      final labelCenter = _findAvailableLabelCenter(
        preferredCenter: Offset(
          (dimensionStart.dx + dimensionEnd.dx) / 2.0,
          (dimensionStart.dy + dimensionEnd.dy) / 2.0,
        ),
        normal: normal,
        angle: angle,
        width: textPainter.width + 8,
        height: textPainter.height + 4,
      );
      if (labelCenter == null) {
        continue;
      }

      _occupiedLabelRects.add(
        _rotatedLabelBounds(
          center: labelCenter,
          angle: angle,
          width: textPainter.width + 8,
          height: textPainter.height + 4,
        ).inflate(2),
      );

      canvas.save();
      canvas.translate(labelCenter.dx, labelCenter.dy);
      canvas.rotate(angle);
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2.0, -textPainter.height / 2.0),
      );
      canvas.restore();
    }
  }

  void _drawIsoDimensionArrow(
    Canvas canvas,
    Offset tip,
    Offset direction,
    Paint paint,
  ) {
    final length = direction.distance;
    if (length < 0.000001) return;
    final unit = direction / length;
    final normal = Offset(-unit.dy, unit.dx);
    const arrowLength = 7.0;
    const arrowHalfWidth = 2.4;
    final base = tip + unit * arrowLength;
    canvas.drawLine(
      tip,
      base + normal * arrowHalfWidth,
      paint,
    );
    canvas.drawLine(
      tip,
      base - normal * arrowHalfWidth,
      paint,
    );
  }

  String _openingDimensionLabelForId(
    RoomModel room,
    String dimensionId,
  ) {
    final marker = ':opening:';
    final markerIndex = dimensionId.indexOf(marker);
    if (markerIndex < 0) {
      return '';
    }
    final featureId = dimensionId.substring(markerIndex + marker.length);
    for (final feature in room.features) {
      if (feature.id == featureId) {
        return formatOpeningDimensions(feature);
      }
    }
    return '';
  }

  double _dimensionLengthMeters(
    RoomModel room,
    DimensionSegment dimension,
  ) {
    final pointByScreen = <ARPoint>[];
    for (final point in room.points) {
      final screen = transform(point);
      if ((screen.dx - dimension.x1).abs() < 0.01 &&
          (screen.dy - dimension.y1).abs() < 0.01) {
        pointByScreen.add(point);
      }
      if ((screen.dx - dimension.x2).abs() < 0.01 &&
          (screen.dy - dimension.y2).abs() < 0.01) {
        pointByScreen.add(point);
      }
    }

    if (pointByScreen.length >= 2) {
      return GeometryService.calculateDistance(
        pointByScreen.first,
        pointByScreen.last,
      );
    }

    final scale = _screenMetersScale(room);
    return dimension.length / math.max(scale, 0.000001);
  }

  double _screenMetersScale(RoomModel room) {
    for (var index = 0; index < room.points.length - 1; index++) {
      final first = transform(room.points[index]);
      final second = transform(room.points[index + 1]);
      final meters = GeometryService.calculateDistance(
        room.points[index],
        room.points[index + 1],
      );
      final pixels = (second - first).distance;
      if (meters > 0.000001 && pixels > 0.000001) {
        return pixels / meters;
      }
    }
    return 1.0;
  }

  Rect _boundsForPoints(List<Offset> points) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final point in points) {
      minX = math.min(minX, point.dx);
      minY = math.min(minY, point.dy);
      maxX = math.max(maxX, point.dx);
      maxY = math.max(maxY, point.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  bool _isLabelAreaAvailable(Rect bounds) {
    return !_occupiedLabelRects.any(
      (occupied) => occupied.overlaps(bounds.inflate(2)),
    );
  }

  TextPainter? _adaptiveTextPainter({
    required String text,
    required Color color,
    required double preferredFontSize,
    required double minimumFontSize,
    required double availableWidth,
    int maxLines = 1,
  }) {
    if (availableWidth < 12) {
      return null;
    }
    var fontSize = preferredFontSize;
    while (fontSize >= minimumFontSize - 0.001) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
      )..layout(maxWidth: availableWidth);
      if (!painter.didExceedMaxLines &&
          painter.width <= availableWidth + 0.001) {
        return painter;
      }
      fontSize -= 0.5;
    }
    return null;
  }

  Rect _rotatedLabelBounds({
    required Offset center,
    required double angle,
    required double width,
    required double height,
  }) {
    final cosine = math.cos(angle).abs();
    final sine = math.sin(angle).abs();
    return Rect.fromCenter(
      center: center,
      width: width * cosine + height * sine,
      height: width * sine + height * cosine,
    );
  }

  Offset? _findAvailableLabelCenter({
    required Offset preferredCenter,
    required Offset normal,
    required double angle,
    required double width,
    required double height,
  }) {
    for (final offset in const [0.0, 12.0, 24.0]) {
      final center = preferredCenter + normal * offset;
      final bounds = _rotatedLabelBounds(
        center: center,
        angle: angle,
        width: width,
        height: height,
      );
      if (_isLabelAreaAvailable(bounds)) {
        return center;
      }
    }
    return null;
  }

  // ===========================================================================
  // PUERTAS Y VENTANAS
  // ===========================================================================

  void _drawFeatures(
    Canvas canvas,
    RoomModel room,
    Paint doorPaint,
    Paint windowPaint,
    Paint selectedPaint,
    Paint referencePaint,
    Map<String, String> featureOwnerRoomIds,
  ) {
    for (final feature
        in room.features) {
      if (featureOwnerRoomIds[feature.id] != room.id) {
        continue;
      }

      final start =
          transform(
        feature.start,
      );

      final end =
          transform(
        feature.end,
      );

      final isSelected =
          room.id == selectedRoomId &&
              feature.id == selectedFeatureId;

      if (isSelected) {
        canvas.drawLine(
          start,
          end,
          selectedPaint,
        );
      }

      switch (feature.type) {
        case FeatureType.door:
          _drawProfessionalDoor(
            canvas: canvas,
            feature: feature,
            start: start,
            end: end,
            paint: doorPaint,
          );
          break;

        case FeatureType.window:
          _drawProfessionalWindow(
            canvas: canvas,
            start: start,
            end: end,
            paint: windowPaint,          );
          break;
      }

      if (continuationSelectionMode && feature.isConnected) {
        final unavailablePaint = Paint()
          ..color = Colors.grey.withOpacity(0.35)
          ..strokeWidth = 5.0
          ..style = PaintingStyle.stroke;
        canvas.drawLine(start, end, unavailablePaint);
      }

      if (!feature.isConnected) {
        _drawContinuationPoint(
          canvas,
          start,
          referencePaint,
          selected: isSelected,
        );
      }
    }
  }

  void _drawProfessionalDoor({
    required Canvas canvas,
    required WallFeature feature,
    required Offset start,
    required Offset end,
    required Paint paint,
  }) {
    final opening = end - start;
    final width = opening.distance;

    if (width <= 0.000001) {
      return;
    }

    final tangent = opening / width;
    final leftNormal = Offset(-tangent.dy, tangent.dx);
    final baseSwingNormal =
        feature.doorSwingSide == DoorSwingSide.left
            ? leftNormal
            : -leftNormal;
    final swingNormal =
        feature.doorOpeningDirection == DoorOpeningDirection.interior
            ? baseSwingNormal
            : -baseSwingNormal;
    final hinge = feature.doorHingeSide == DoorHingeSide.start
        ? start
        : end;
    final latch = feature.doorHingeSide == DoorHingeSide.start
        ? end
        : start;
    final closedDirection = (latch - hinge) / width;
    final erasePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final symbolPaint = Paint()      ..color = paint.color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;    final leafEnd = hinge + swingNormal * width;

    // Interrumpe gráficamente la pared en el ancho real de la puerta.
    canvas.drawLine(start, end, erasePaint);

    // Hoja abierta a 90 grados según la orientación elegida.
    canvas.drawLine(hinge, leafEnd, symbolPaint);
    canvas.drawCircle(
      hinge,
      2.5,
      Paint()
        ..color = paint.color
        ..style = PaintingStyle.fill,
    );

    final startAngle = math.atan2(
      closedDirection.dy,
      closedDirection.dx,
    );
    final inwardAngle = math.atan2(
      swingNormal.dy,
      swingNormal.dx,
    );
    final sweepAngle = _shortestSweep(
      startAngle,
      inwardAngle,
    );

    canvas.drawArc(
      Rect.fromCircle(
        center: hinge,
        radius: width,
      ),
      startAngle,
      sweepAngle,
      false,
      symbolPaint,
    );
  }

  void _drawProfessionalWindow({
    required Canvas canvas,    required Offset start,
    required Offset end,
    required Paint paint,
  }) {
    final opening = end - start;
    final width = opening.distance;

    if (width <= 0.000001) {
      return;
    }

    final tangent = opening / width;
    final normal = Offset(-tangent.dy, tangent.dx);
    final erasePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final symbolPaint = Paint()
      ..color = paint.color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    const railOffset = 2.5;

    canvas.drawLine(start, end, erasePaint);
    canvas.drawLine(
      start + normal * railOffset,
      end + normal * railOffset,
      symbolPaint,
    );
    canvas.drawLine(
      start - normal * railOffset,
      end - normal * railOffset,
      symbolPaint,
    );
    canvas.drawLine(
      start - normal * 5,
      start + normal * 5,
      symbolPaint,    );
    canvas.drawLine(
      end - normal * 5,
      end + normal * 5,
      symbolPaint,
    );
  }

  double _shortestSweep(
    double startAngle,
    double endAngle,
  ) {
    var sweep = endAngle - startAngle;

    while (sweep > math.pi) {
      sweep -= math.pi * 2;
    }

    while (sweep < -math.pi) {
      sweep += math.pi * 2;
    }

    return sweep;
  }

  void _drawContinuationPoint(
    Canvas canvas,
    Offset point,
    Paint referencePaint, {
    required bool selected,
  }) {
    canvas.drawCircle(
      point,
      selected ? 10 : 8,
      referencePaint,
    );

    canvas.drawCircle(
      point,
      selected ? 4 : 3,
      Paint()..color = Colors.white,
    );
  }


  // REPAINT
  // ===========================================================================

  @override
  bool shouldRepaint(
    covariant FloorPlanPainter
        oldDelegate,
  ) {
    return true;
  }
}
