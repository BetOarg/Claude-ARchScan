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
import '../widgets/opening_placement_dialog.dart'
    show showOpeningPlacementDialog;
import '../widgets/room_name_dialog.dart';

part 'floor_plan_painters.dart';
part 'floor_plan_viewer_models.dart';
part 'floor_plan_viewer_widgets.dart';
part 'floor_plan_wall_editor.dart';

class FloorPlanViewerScreen extends StatefulWidget {
  final bool selectContinuationOpening;

  const FloorPlanViewerScreen({
    super.key,
    this.selectContinuationOpening = false,
  });

  @override
  State<FloorPlanViewerScreen> createState() => _FloorPlanViewerScreenState();
}

class _FloorPlanViewerScreenState extends State<FloorPlanViewerScreen>
    with _PlanWallEditing {
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

  void _startTouchTransform(ScaleStartDetails details, List<RoomModel> rooms) {
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
    final accepted = await context
        .read<FloorPlanProvider>()
        .endTouchRoomTransform(roomId: roomId);
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
  Offset _transformPoint(ARPoint point) {
    final x = _padding + (point.x - _minX) * _scale;

    final z = _padding + (point.z - _minZ) * _scale;

    return Offset(x, z);
  }

  @override
  ARPoint _inverseTransform(Offset screenPosition) {
    final x = (screenPosition.dx - _padding) / _scale + _minX;

    final z = (screenPosition.dy - _padding) / _scale + _minZ;

    return ARPoint(x: x, y: 0.0, z: z);
  }

  void _calculateTransform(Size screenSize, List<RoomModel> rooms) {
    if (rooms.isEmpty) {
      return;
    }

    double minX = double.infinity;
    double maxX = double.negativeInfinity;

    double minZ = double.infinity;
    double maxZ = double.negativeInfinity;

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

    _padding = screenSize.width * 0.08;

    final contentWidth = (maxX - minX).abs();

    final contentHeight = (maxZ - minZ).abs();

    final safeWidth = contentWidth <= 0.0001 ? 1.0 : contentWidth;

    final safeHeight = contentHeight <= 0.0001 ? 1.0 : contentHeight;

    final availableWidth = screenSize.width - (_padding * 2);

    final availableHeight = screenSize.height - (_padding * 2);

    final widthScale = availableWidth / safeWidth;

    final heightScale = availableHeight / safeHeight;

    _scale = widthScale < heightScale ? widthScale : heightScale;

    if (!_scale.isFinite || _scale <= 0) {
      _scale = 1.0;
    }
  }

  String? _getRoomAtPosition(ARPoint point, List<RoomModel> rooms) {
    for (final room in rooms.reversed) {
      if (GeometryService.isPointInPolygon(point, room.points)) {
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

        if (distance <= touchTolerance && distance < nearestDistance) {
          nearestDistance = distance;
          nearest = _FeatureSelection(roomId: room.id, feature: feature);
        }
      }
    }

    return nearest;
  }

  double _distanceToSegment(Offset point, Offset start, Offset end) {
    final segment = end - start;
    final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;

    if (lengthSquared <= 0.000001) {
      return (point - start).distance;
    }

    final fromStart = point - start;
    final rawT =
        (fromStart.dx * segment.dx + fromStart.dy * segment.dy) / lengthSquared;
    final t = rawT.clamp(0.0, 1.0).toDouble();
    final projection = Offset(
      start.dx + segment.dx * t,
      start.dy + segment.dy * t,
    );

    return (point - projection).distance;
  }

  Future<void> _showFeatureMenu(_FeatureSelection selection) async {
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
          child: SingleChildScrollView(
            child: Padding(
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
                        onPressed: () =>
                            selectAction(_FeatureMenuAction.delete),
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
            ),
          ),
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
      await _placeOpeningOnWall(
        selection.roomId,
        feature.type,
        feature: feature,
      );
      return;
    }

    if (action == _FeatureMenuAction.editGeometry) {
      await _showOpeningGeometryEditor(selection);
      return;
    }

    if (action == _FeatureMenuAction.delete) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(localizations.deleteOpening),
          content: Text(localizations.deleteOpeningConfirmation),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(localizations.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(localizations.deleteOpening),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      if (!await context.read<FloorPlanProvider>().removeOpening(
        selection.roomId,
        feature.id,
      )) {
        if (mounted) _planError(PlanEditError.invalid);
        return;
      }
      if (mounted)
        setState(() {
          _selectedFeatureId = null;
        });
      return;
    }

    if (action == _FeatureMenuAction.toggleHinge) {
      final updated = await context
          .read<FloorPlanProvider>()
          .updateDoorOrientation(
            featureId: feature.id,
            hingeSide: feature.doorHingeSide == DoorHingeSide.start
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

  OpeningConnectionSide _availableSideFor(_FeatureSelection selection) {
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
        : OpeningConnectionSide.left;
  }

  Future<void> _showOpeningGeometryEditor(_FeatureSelection selection) async {
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
      text: _formatDecimal(placement.distanceFromWallStartMeters),
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
    final positionImperial = MeasurementUnits.metersToFeetAndInches(
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
      text: _formatDecimal(widthImperial.inches),
    );
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
                return TextField(
                  controller: metric,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
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
                          keyboardType: const TextInputType.numberWithOptions(
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
                          keyboardType: const TextInputType.numberWithOptions(
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${localizations.wallLength}: '
                      '${_formatLength(placement.wallLengthMeters, measurementSystem)}',
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
                    if (selection.feature.type == FeatureType.window) ...[
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
                    ],
                  ],
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
                    final sill = selection.feature.type == FeatureType.window
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
                        !width.isFinite ||
                        width < 0.20 ||
                        !position.isFinite ||
                        position < 0 ||
                        width + position >
                            placement.wallLengthMeters + 0.000001 ||
                        !height.isFinite ||
                        height < 0.20 ||
                        !sill.isFinite ||
                        sill < 0) {
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
      distanceFromWallStartMeters: input.distanceFromWallStartMeters,
      openingHeightMeters: input.openingHeightMeters,
      sillHeightMeters: input.sillHeightMeters,
    );

    if (!mounted) return;
    _showMessage(
      result.isSuccess
          ? localizations.openingUpdated
          : result.errorMessage ?? localizations.invalidOpeningMeasurement,
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
          title: Text(localizations.chooseDoorOpeningDirection),
          children: [
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(dialogContext, DoorOpeningDirection.interior),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.home_outlined),
                title: Text(planDirectionLabel(DoorOpeningDirection.interior)),
                subtitle: Text(localizations.doorOpensInterior),
                trailing:
                    feature.doorOpeningDirection ==
                        DoorOpeningDirection.interior
                    ? const Icon(Icons.check_circle)
                    : null,
              ),
            ),
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(dialogContext, DoorOpeningDirection.exterior),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.exit_to_app),
                title: Text(planDirectionLabel(DoorOpeningDirection.exterior)),
                subtitle: Text(localizations.doorOpensExterior),
                trailing:
                    feature.doorOpeningDirection ==
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

  Future<OpeningConnectionSide?> _chooseConnectionSide(WallFeature feature) {
    final localizations = AppLocalizations.of(context)!;
    final start = _transformPoint(feature.start);
    final end = _transformPoint(feature.end);
    final openingDirection = end - start;
    final leftDirection = Offset(-openingDirection.dy, openingDirection.dx);
    final rightDirection = -leftDirection;
    final directionsAreVertical =
        leftDirection.dy.abs() > leftDirection.dx.abs();
    final leftChoiceComesFirst = directionsAreVertical
        ? leftDirection.dy <= rightDirection.dy
        : leftDirection.dx <= rightDirection.dx;
    final firstSide = leftChoiceComesFirst
        ? OpeningConnectionSide.left
        : OpeningConnectionSide.right;
    final firstDirection = leftChoiceComesFirst
        ? leftDirection
        : rightDirection;
    final secondSide = leftChoiceComesFirst
        ? OpeningConnectionSide.right
        : OpeningConnectionSide.left;
    final secondDirection = leftChoiceComesFirst
        ? rightDirection
        : leftDirection;

    return showDialog<OpeningConnectionSide>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(localizations.continuationDirectionTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(localizations.continuationDirectionExplanation),
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
                  onPressed: () => Navigator.pop(dialogContext, firstSide),
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
                  onPressed: () => Navigator.pop(dialogContext, secondSide),
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

  String _directionLabel(Offset direction, AppLocalizations localizations) {
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
      return direction.dx >= 0 ? Icons.arrow_forward : Icons.arrow_back;
    }

    return direction.dy >= 0 ? Icons.arrow_downward : Icons.arrow_upward;
  }

  double _featureWidth(WallFeature feature) {
    return GeometryService.calculateDistance(feature.start, feature.end);
  }

  String _formatLength(double meters, MeasurementSystem measurementSystem) {
    if (measurementSystem == MeasurementSystem.metric) {
      return '${_formatDecimal(meters)} m';
    }

    final imperial = MeasurementUnits.metersToFeetAndInches(meters);

    return '${imperial.feet}′ '
        '${_formatDecimal(imperial.inches)}″';
  }

  String _formatOpeningPlanDimensions(
    WallFeature feature,
    MeasurementSystem measurementSystem,
  ) {
    final localizations = AppLocalizations.of(context)!;
    final width = _formatLength(_featureWidth(feature), measurementSystem);
    final height = _formatLength(
      feature.openingHeightMeters,
      measurementSystem,
    );

    if (feature.type == FeatureType.door) {
      return localizations.doorPlanDimensions(width, height);
    }

    final sill = _formatLength(feature.sillHeightMeters, measurementSystem);
    final orientation = _featureWidth(feature) >= feature.openingHeightMeters
        ? localizations.horizontalOrientation
        : localizations.verticalOrientation;
    return localizations.windowPlanDimensions(width, height, sill, orientation);
  }

  String _formatArea(double squareMeters, MeasurementSystem measurementSystem) {
    final localizations = AppLocalizations.of(context)!;

    if (measurementSystem == MeasurementSystem.metric) {
      return '${_formatDecimal(squareMeters)} '
          '${localizations.squareMeters}';
    }

    final squareFeet = MeasurementUnits.squareMetersToSquareFeet(squareMeters);

    return '${_formatDecimal(squareFeet)} '
        '${localizations.squareFeet}';
  }

  String _formatDecimal(double value) {
    var formatted = value.toStringAsFixed(2);

    if (Localizations.localeOf(context).languageCode == 'es') {
      formatted = formatted.replaceAll('.', ',');
    }

    return formatted;
  }

  // ===========================================================================  // EDITOR DE MEDIDAS
  // ===========================================================================

  Future<void> _openMeasurementEditor({String? roomId}) async {
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
    final provider = context.read<FloorPlanProvider>();

    if (provider.completedRooms.length <= 1) {
      _showMessage(localizations.notEnoughRoomsToOrganize);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.grid_view_rounded),
              SizedBox(width: 10),
              Expanded(child: Text(localizations.organizeRooms)),
            ],
          ),
          content: Text(localizations.organizeRoomsExplanation),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: Text(localizations.cancel),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.auto_awesome),
              label: Text(localizations.organizeRooms),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final changed = await provider.autoArrangeRooms();

    if (!mounted) {
      return;
    }
    _showMessage(
      changed
          ? localizations.roomsOrganizedSuccessfully
          : localizations.roomsArrangementUnchanged,
    );
  }
  // ===========================================================================
  // BUILD
  // ===========================================================================

  Future<void> _showRoomTransformEditor() async {
    final provider = context.read<FloorPlanProvider>();
    final localizations = AppLocalizations.of(context)!;
    final measurementSystem = context
        .read<MeasurementSettingsProvider>()
        .system;
    final rooms = provider.completedRooms;

    if (rooms.isEmpty) {
      _showMessage(localizations.noRoomsToEdit);
      return;
    }

    var selectedRoomId = rooms.any((room) => room.id == _selectedRoomId)
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
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> moveRoom({
              required double offsetX,
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
                _showMessage(localizations.unsafeMovementRejected, error: true);
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
                _showMessage(localizations.unsafeRotationRejected, error: true);
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
              final horizontalController = TextEditingController(text: '0');
              final verticalController = TextEditingController(text: '0');
              final rotationController = TextEditingController(text: '0');

              double? parseNumber(String value) {
                return double.tryParse(value.trim().replaceAll(',', '.'));
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
                                suffixText:
                                    measurementSystem ==
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
                                suffixText:
                                    measurementSystem ==
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
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text(localizations.cancel),
                        ),
                        FilledButton(
                          onPressed: () {
                            final horizontal = parseNumber(
                              horizontalController.text,
                            );
                            final vertical = parseNumber(
                              verticalController.text,
                            );
                            final rotation = parseNumber(
                              rotationController.text,
                            );
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
                            final offsetX =
                                measurementSystem == MeasurementSystem.metric
                                ? horizontal
                                : MeasurementUnits.inchesToMeters(horizontal);
                            final offsetZ =
                                measurementSystem == MeasurementSystem.metric
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

              final result = await provider.applyWallAlignmentPreview(preview);
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
                  Text(localizations.connectedGroupTransformHint),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: provider.canUndoTransform
                              ? undoTransform
                              : null,
                          icon: const Icon(Icons.undo),
                          label: Text(localizations.undoLastTransform),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: provider.canRedoTransform
                              ? redoTransform
                              : null,
                          icon: const Icon(Icons.redo),
                          label: Text(localizations.redoLastTransform),
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
                    onPressed: targetRoomId == null ? null : joinSelectedRooms,
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
                      border: const OutlineInputBorder(),
                    ),
                    items: measurementSystem == MeasurementSystem.metric
                        ? [
                            DropdownMenuItem(
                              value: 0.05,
                              child: Text(localizations.fiveCentimeters),
                            ),
                            DropdownMenuItem(
                              value: 0.10,
                              child: Text(localizations.tenCentimeters),
                            ),
                            DropdownMenuItem(
                              value: 0.25,
                              child: Text(localizations.twentyFiveCentimeters),
                            ),
                            DropdownMenuItem(
                              value: 0.50,
                              child: Text(localizations.fiftyCentimeters),
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
                            await moveRoom(offsetX: 0, offsetZ: -movementStep);
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
                        ),
                      ),
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
    final measurementSystem = context
        .read<MeasurementSettingsProvider>()
        .system;
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
                      style: const TextStyle(fontWeight: FontWeight.w600),
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
                    _formatArea(provider.totalProjectArea, measurementSystem),
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

  void _closeProject() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
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
        actions: [
          IconButton(
            tooltip: localizations.closeProject,
            icon: const Icon(Icons.close),
            onPressed: _closeProject,
          ),
          if (!widget.selectContinuationOpening) ...[
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
                PopupMenuButton<_FloorPlanAction>(
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
                        enabled: context
                            .read<FloorPlanProvider>()
                            .completedRooms
                            .any((room) => room.points.length >= 2),
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.file_download_outlined),
                          title: Text(localizations.exportProject),
                        ),
                      ),
                      PopupMenuItem(
                        value: _FloorPlanAction.importProject,
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.file_upload),
                          title: Text(localizations.importProject),
                        ),
                      ),
                    ];
                  },
                ),
          ],
        ],
      ),
      bottomNavigationBar: widget.selectContinuationOpening
          ? null
          : _buildPlanToolbar(),
      body: Consumer<FloorPlanProvider>(
        builder: (context, provider, child) {
          final rooms = _roomsForDisplay(provider.completedRooms);
          final hasAvailableOpenings = rooms.any(
            (room) => room.features.any((feature) => !feature.isConnected),
          );

          if (rooms.isEmpty) {
            return const _EmptyPlanView();
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;

              if (!_touchTransformMode && !_freezePlanTransform) {
                _calculateTransform(size, rooms);
              }

              return Stack(
                children: [
                  InteractiveViewer(
                    transformationController: _planViewport,
                    panEnabled: !_touchTransformMode && !_wallGestureActive,
                    scaleEnabled: !_touchTransformMode && !_wallGestureActive,
                    constrained: true,
                    boundaryMargin: const EdgeInsets.all(200),
                    minScale: 0.2,
                    maxScale: 6.0,
                    child: GestureDetector(
                      dragStartBehavior: DragStartBehavior.down,
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) async {
                        if (_choosingContinuationClosing ||
                            _addOpeningType != null ||
                            _wallEditMode ||
                            _pendingPlanEdit != null) {
                          await _selectPlanElement(
                            details.localPosition,
                            provider.completedRooms,
                          );
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
                        final featureSelection = _getFeatureAtPosition(
                          details.localPosition,
                          rooms,
                        );

                        if (featureSelection != null) {
                          if (widget.selectContinuationOpening &&
                              featureSelection.feature.isConnected) {
                            return;
                          }
                          _showFeatureMenu(featureSelection);
                          return;
                        }

                        if (widget.selectContinuationOpening) {
                          return;
                        }

                        if (await _selectPlanElement(
                          details.localPosition,
                          provider.completedRooms,
                        ))
                          return;
                        if (!mounted) return;

                        final planePoint = _inverseTransform(
                          details.localPosition,
                        );
                        final roomId = _getRoomAtPosition(planePoint, rooms);

                        if (roomId == null) {
                          _showMessage(localizations.tapRoomToAddOpening);
                          return;
                        }

                        _showAddFeatureMenu(
                          roomId: roomId,
                          location: planePoint,
                        );
                      },
                      onScaleStart: _wallGestureActive
                          ? (details) =>
                                _startWallDrag(details, provider.completedRooms)
                          : _touchTransformMode
                          ? (details) => _startTouchTransform(details, rooms)
                          : null,
                      onScaleUpdate: _wallGestureActive
                          ? _updateWallDrag
                          : _touchTransformMode
                          ? _updateTouchTransform
                          : null,
                      onScaleEnd: _wallGestureActive
                          ? (_) => _endWallDrag()
                          : _touchTransformMode
                          ? (_) => _endTouchTransform()
                          : null,
                      child: _trackPlanPointer(
                        SizedBox.expand(
                          child: CustomPaint(
                            foregroundPainter: _planSelectionPainter(rooms),
                            painter: FloorPlanPainter(
                              rooms: rooms,
                              transform: _transformPoint,
                              selectedRoomId: _selectedRoomId,
                              selectedFeatureId: _selectedFeatureId,
                              formatLength: (length) =>
                                  _formatLength(length, measurementSystem),
                              formatOpeningDimensions: (feature) =>
                                  _formatOpeningPlanDimensions(
                                    feature,
                                    measurementSystem,
                                  ),
                              sharedWallLabel: localizations.sharedWall,
                              partialSharedWallLabel:
                                  localizations.partialSharedWall,
                              openRoomLabel: localizations.planOpenContour,
                              continuationSelectionMode:
                                  widget.selectContinuationOpening,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_touchTransformMode)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 18,
                      child: SafeArea(
                        child: Material(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHigh,
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
                                      icon: const Icon(
                                        Icons.center_focus_strong,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: localizations.zoomIn,
                                      onPressed: () => _zoomPlan(1.25),
                                      icon: const Icon(Icons.zoom_in),
                                    ),
                                    IconButton(
                                      tooltip:
                                          localizations.transformRoomsTitle,
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
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.72),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${localizations.roomCount(rooms.length)} · '
                          '${_formatArea(provider.totalProjectArea, measurementSystem)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
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
                                    : Theme.of(context)
                                          .colorScheme
                                          .onErrorContainer,
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
    final provider = context.read<FloorPlanProvider>();
    final result = await ImportExportService.importProject(
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
        _showMessage(localizations.planImportedSuccessfully);
        break;
      case JsonImportResult.cancelled:
        return;
      case JsonImportResult.invalid:
        _showMessage(localizations.planImportInvalid, error: true);
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
            onPressed: () =>
                Navigator.pop(dialogContext, ExportDestination.saveToFiles),
            child: Text(localizations.saveToFiles),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, ExportDestination.share),
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
    final provider = context.read<FloorPlanProvider>();

    try {
      await ImportExportService.exportToJson(
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
        provider.completedRooms,
        provider.projectName,
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
    final provider = context.read<FloorPlanProvider>();

    try {
      await ImportExportService.exportToPdf(
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
    final selected = await showModalBottomSheet<FeatureType>(
      context: context,
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_location_alt),
                title: Text(localizations.addElement),
                subtitle: Text(localizations.selectElementToAdd),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.door_front_door, color: Colors.red),
                title: Text(localizations.door),
                onTap: () {
                  Navigator.pop(bottomSheetContext, FeatureType.door);
                },
              ),
              ListTile(
                leading: const Icon(Icons.window, color: Colors.blue),
                title: Text(localizations.window),
                onTap: () {
                  Navigator.pop(bottomSheetContext, FeatureType.window);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected == null || !mounted) {
      return;
    }

    await _placeOpeningOnWall(roomId, selected);
  }

  @override
  Future<void> _placeOpeningOnWall(
    String roomId,
    FeatureType type, {
    WallFeature? feature,
    int? initialWallIndex,
    ARPoint? initialLocation,
  }) async {
    final provider = context.read<FloorPlanProvider>();
    final room = provider.completedRooms
        .where((r) => r.id == roomId)
        .firstOrNull;
    if (room == null || room.points.length < 2) return;
    final placement = await showOpeningPlacementDialog(
      context: context,
      room: room,
      type: type,
      system: context.read<MeasurementSettingsProvider>().system,
      initialFeature: feature,
      initialWallIndex: initialWallIndex,
      initialLocation: initialLocation,
      includeClosingWall: room.isClosed,
    );
    if (!mounted || placement == null) return;
    final current = provider.completedRooms
        .where((r) => r.id == roomId)
        .firstOrNull;
    if (!identical(current, room)) return;
    final result = await provider.placeOpeningOnWall(
      roomId: roomId,
      type: type,
      featureId: feature?.id,
      wallIndex: placement.wallIndex,
      location: placement.location,
      widthMeters: placement.width,
      openingHeightMeters: placement.openingHeightMeters,
      sillHeightMeters: placement.sillHeightMeters,
    );
    if (!mounted) return;
    _showMessage(
      result.isSuccess
          ? AppLocalizations.of(context)!.openingUpdated
          : result.errorMessage ??
                AppLocalizations.of(context)!.invalidOpeningMeasurement,
      error: !result.isSuccess,
    );
  }

  @override
  Future<void> _showRoomListDialog() async {
    ModalRoute<dynamic>? roomListRoute;
    final action = await showModalBottomSheet<_RoomListAction>(
      context: context,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        roomListRoute = ModalRoute.of(bottomSheetContext);
        return Consumer<FloorPlanProvider>(
          builder: (context, provider, child) {
            final rooms = provider.completedRooms;
            final localizations = AppLocalizations.of(context)!;
            final measurementSystem = context
                .watch<MeasurementSettingsProvider>()
                .system;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            localizations.registeredRooms,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: localizations.close,
                          onPressed: () {
                            Navigator.pop(bottomSheetContext);
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (rooms.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: Text(localizations.noRoomsYet)),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: rooms.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final room = rooms[index];

                            final area = PlanEditGeometry.area(room);
                            final perimeter = PlanEditGeometry.perimeter(room);

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                child: Text('${index + 1}'),
                              ),
                              title: Text(room.name),
                              subtitle: Text(
                                localizations.roomSummary(
                                  room.isClosed
                                      ? _formatArea(area, measurementSystem)
                                      : localizations.planOpenContour,
                                  _formatLength(perimeter, measurementSystem),
                                  room.points.length,
                                ),
                              ),
                              trailing: PopupMenuButton<_RoomListActionType>(
                                key: ValueKey('room-actions-${room.id}'),
                                tooltip: localizations.actions,
                                onSelected: (type) {
                                  Navigator.pop(
                                    bottomSheetContext,
                                    _RoomListAction(
                                      type: type,
                                      roomId: room.id,
                                    ),
                                  );
                                },
                                itemBuilder: (context) {
                                  return [
                                    PopupMenuItem(
                                      value:
                                          _RoomListActionType.editMeasurements,
                                      child: ListTile(
                                        dense: true,
                                        leading: Icon(
                                          Icons.straighten_outlined,
                                        ),
                                        title: Text(
                                          localizations.editMeasurements,
                                        ),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: _RoomListActionType.rename,
                                      child: ListTile(
                                        dense: true,
                                        leading: Icon(Icons.edit_outlined),
                                        title: Text(localizations.rename),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: _RoomListActionType.delete,
                                      child: ListTile(
                                        dense: true,
                                        leading: const Icon(
                                          Icons.delete_forever_outlined,
                                        ),
                                        title: Text(
                                          localizations.planDeleteRoom,
                                        ),
                                      ),
                                    ),
                                  ];
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    if (rooms.length > 1) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(
                              bottomSheetContext,
                              const _RoomListAction(
                                type: _RoomListActionType.organize,
                              ),
                            );
                          },
                          icon: const Icon(Icons.grid_view_rounded),
                          label: Text(localizations.organizeRooms),
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
    if (action == null || !mounted) {
      return;
    }

    switch (action.type) {
      case _RoomListActionType.delete:
        final room = _findRoom(action.roomId);
        if (room != null) await _deletePlanRoom(room);
        break;
      case _RoomListActionType.editMeasurements:
        await _openMeasurementEditor(roomId: action.roomId);
        break;

      case _RoomListActionType.rename:
        final room = _findRoom(action.roomId);
        if (room != null) {
          await _editRoomName(room);
        }
        break;

      case _RoomListActionType.organize:
        await _organizeRooms();
        break;
    }
  }

  RoomModel? _findRoom(String? roomId) {
    if (roomId == null) {
      return null;
    }

    final rooms = context.read<FloorPlanProvider>().completedRooms;

    for (final room in rooms) {
      if (room.id == roomId) {
        return room;
      }
    }
    return null;
  }

  // ===========================================================================
  // RENOMBRAR AMBIENTE
  // ===========================================================================

  Future<void> _editRoomName(RoomModel room) async {
    final localizations = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: room.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(localizations.renameRoom),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: localizations.roomNameShortLabel,
              hintText: localizations.roomNameMainBedroomExample,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              Navigator.pop(dialogContext, value.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: Text(localizations.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, controller.text.trim());
              },
              child: Text(localizations.save),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (newName == null || newName.trim().isEmpty || !mounted) {
      return;
    }

    await context.read<FloorPlanProvider>().updateRoomName(
      room.id,
      newName.trim(),
    );
  }

  // ===========================================================================
  // MENSAJES
  // ===========================================================================

  @override
  void _showMessage(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? Colors.red.shade700 : null,
          content: Text(message),
        ),
      );
  }
}
