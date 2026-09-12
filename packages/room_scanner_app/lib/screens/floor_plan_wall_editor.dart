part of 'floor_plan_viewer_screen.dart';

class _PlanHit {
  final String roomId;
  final int index;
  final bool corner;
  const _PlanHit(this.roomId, this.index, this.corner);
}

mixin _PlanWallEditing on State<FloorPlanViewerScreen> {
  ARPoint _inverseTransform(Offset position);
  Offset _transformPoint(ARPoint point);
  set _touchTransformMode(bool value);
  set _selectedRoomId(String? value);
  void _showMessage(String text, {bool error = false});
  Future<void> _showRoomListDialog();

  Future<void> _continueOpenRoom(
    RoomModel room, {
    int? vertexIndex,
  }) async {
    if (room.points.length < 2) return;

    final l10n = AppLocalizations.of(context)!;
    var selectedVertexIndex = vertexIndex;
    int? closingVertexIndex;

    // When the action starts from a selected wall, do not silently return to
    // the historical first point. Let the user choose either valid endpoint.
    if (selectedVertexIndex == null) {
      selectedVertexIndex = await showModalBottomSheet<int>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  l10n.continueFromSelectedVertexTitle,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.first_page),
                title: Text('${l10n.planCorner} 1'),
                onTap: () => Navigator.pop(sheetContext, 0),
              ),
              ListTile(
                leading: const Icon(Icons.last_page),
                title: Text(
                  '${l10n.planCorner} ${room.points.length}',
                ),
                onTap: () => Navigator.pop(
                  sheetContext,
                  room.points.length - 1,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (!mounted || selectedVertexIndex == null) return;
    }

    if (room.isClosed) {
      closingVertexIndex = await _chooseContinuationClosingCorner(
        room,
        selectedVertexIndex,
      );
      if (!mounted || closingVertexIndex == null) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }

    final preparedRoom = _plan.prepareOpenRoomContinuation(
      roomId: room.id,
      vertexIndex: selectedVertexIndex,
      closingVertexIndex: closingVertexIndex,
    );
    if (preparedRoom == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.continueFromSelectedVertexTitle),
        content: Text(l10n.continueFromSelectedVertexBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.continueScan),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(_clearContinuationCornerSelection);
    if (confirmed != true) return;

    final projectUuid = _plan.projectUuid;
    if (projectUuid == null) return;
    await ArCheckService.abrirEscanerConValidacion(
      context,
      projectUuid: projectUuid,
      projectName: _plan.projectName,
      resumeRoom: preparedRoom,
    );
  }
  Future<void> _placeOpeningOnWall(
    String roomId,
    FeatureType type, {
    int? initialWallIndex,
    ARPoint? initialLocation,
  });

  final _planViewport = TransformationController();
  bool _wallEditMode = false, _planSaving = false;
  _PlanHit? _planHit;
  FeatureType? _addOpeningType;
  RoomModel? _dragRoom;
  ARPoint? _dragOrigin;
  Offset? _wallPointerOrigin;
  List<ARPoint>? _dragPoints;
  PlanEditProposal? _pendingPlanEdit;
  String? _previewTitle;
  bool _deletingPreview = false;
  Completer<int?>? _closingCornerCompleter;
  _PlanHit? _continuationStartHit;
  _PlanHit? _continuationClosingHit;
  bool get _choosingContinuationClosing =>
      _closingCornerCompleter != null;
  FloorPlanProvider get _plan => context.read<FloorPlanProvider>();
  bool get _wallGestureActive =>
      !_choosingContinuationClosing &&
      _planHit != null &&
      _pendingPlanEdit == null &&
      !_planSaving;
  bool get _freezePlanTransform =>
      _pendingPlanEdit != null || _dragRoom != null;

  @override
  void dispose() {
    final completer = _closingCornerCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
    _planViewport.dispose();
    super.dispose();
  }

  Future<int?> _chooseContinuationClosingCorner(
    RoomModel room,
    int startVertexIndex,
  ) async {
    final completer = Completer<int?>();
    setState(() {
      _closingCornerCompleter = completer;
      _continuationStartHit =
          _PlanHit(room.id, startVertexIndex, true);
      _continuationClosingHit = null;
      _wallEditMode = false;
    });
    return completer.future;
  }

  void _clearContinuationCornerSelection() {
    _closingCornerCompleter = null;
    _continuationStartHit = null;
    _continuationClosingHit = null;
  }

  void _cancelContinuationCornerSelection() {
    final completer = _closingCornerCompleter;
    setState(_clearContinuationCornerSelection);
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
  }

  void _clearPlanSelection() {
    _planHit = null;
    _dragRoom = null;
    _dragPoints = null;
    _dragOrigin = null;
    _pendingPlanEdit = null;
    _previewTitle = null;
    _addOpeningType = null;
  }

  List<RoomModel> _roomsForDisplay(List<RoomModel> rooms) {
    if (_pendingPlanEdit != null) return _pendingPlanEdit!.after;
    if (_dragRoom != null && _dragPoints != null) {
      final preview = PlanEditGeometry.reshape(_dragRoom!, _dragPoints!) ??
          _dragRoom!.copyWith(points: _dragPoints);
      return [for (final r in rooms) r.id == preview.id ? preview : r];
    }
    return rooms;
  }

  List<_PlanHit> _planHits(
    Offset position,
    List<RoomModel> rooms, {
    bool corners = true,
    String? onlyRoom,
  }) {
    final zoom = _planViewport.value.getMaxScaleOnAxis();
    final hits = <({double distance, _PlanHit hit})>[];
    for (final room in rooms.reversed) {
      if (onlyRoom != null && room.id != onlyRoom) continue;
      if (corners) {
        for (var i = 0; i < room.points.length; i++) {
          final d = (_transformPoint(room.points[i]) - position).distance;
          if (d <= 14 / zoom) {
            hits.add((distance: d, hit: _PlanHit(room.id, i, true)));
          }
        }
      }
      for (var i = 0; i < PlanEditGeometry.wallCount(room); i++) {
        final a = _transformPoint(room.points[i]);
        final v =
            _transformPoint(room.points[(i + 1) % room.points.length]) - a;
        if (v.distanceSquared < 1e-9) continue;
        final t = ((position - a).dx * v.dx + (position - a).dy * v.dy) /
            v.distanceSquared;
        final d = (position - (a + v * t.clamp(0.0, 1.0))).distance;
        if (d <= 22 / zoom) {
          hits.add((distance: d, hit: _PlanHit(room.id, i, false)));
        }
      }
    }
    hits.sort((a, b) {
      if (a.hit.corner != b.hit.corner) return a.hit.corner ? -1 : 1;
      return a.distance.compareTo(b.distance);
    });
    final seen = <String>{};
    return [
      for (final item in hits)
        if (seen.add(item.hit.roomId)) item.hit,
    ];
  }

  Future<bool> _selectPlanElement(
    Offset position,
    List<RoomModel> rooms,
  ) async {
    final closingCompleter = _closingCornerCompleter;
    final startHit = _continuationStartHit;
    if (closingCompleter != null && startHit != null) {
      final cornerHits = _planHits(
        position,
        rooms,
        onlyRoom: startHit.roomId,
      ).where((hit) => hit.corner).toList();
      if (cornerHits.isEmpty) {
        _showMessage(AppLocalizations.of(context)!.chooseClosingCorner);
        return true;
      }
      final hit = cornerHits.first;
      if (hit.index == startHit.index) {
        _showMessage(AppLocalizations.of(context)!.chooseDifferentCorner);
        return true;
      }
      setState(() => _continuationClosingHit = hit);
      if (!closingCompleter.isCompleted) {
        closingCompleter.complete(hit.index);
      }
      return true;
    }
    if (_pendingPlanEdit != null || _planSaving) return true;
    final type = _addOpeningType;
    final hits = _planHits(position, rooms, corners: type == null);
    if (hits.isEmpty) {
      if (type != null) {
        _showMessage(AppLocalizations.of(context)!.planTapWall);
        return true;
      }
      if (_wallEditMode) {
        setState(_clearPlanSelection);
        return true;
      }
      return false;
    }
    var hit = hits.first;
    if (hits.length > 1) {
      final selected = await showModalBottomSheet<_PlanHit>(
        context: context,
        builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(AppLocalizations.of(sheet)!.planChooseRoom),
                ),
                for (final option in hits)
                  ListTile(
                    title: Text(
                      rooms.firstWhere((r) => r.id == option.roomId).name,
                    ),
                    onTap: () => Navigator.pop(sheet, option),
                  ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || selected == null) return true;
      hit = selected;
    }
    if (type != null) {
      setState(_clearPlanSelection);
      await _placeOpeningOnWall(
        hit.roomId,
        type,
        initialWallIndex: hit.index,
        initialLocation: _inverseTransform(position),
      );
    } else {
      setState(() {
        _planHit = hit;
        _selectedRoomId = hit.roomId;
        _touchTransformMode = false;
      });
    }
    return true;
  }

  Widget _trackPlanPointer(Widget child) => Listener(
        onPointerDown: (event) => _wallPointerOrigin = event.localPosition,
        child: child,
      );

  void _startWallDrag(ScaleStartDetails details, List<RoomModel> rooms) {
    final selected = _planHit;
    if (selected == null || _pendingPlanEdit != null) return;
    final hits = _planHits(
      _wallPointerOrigin ?? details.localFocalPoint,
      rooms,
      onlyRoom: selected.roomId,
    );
    if (hits.isEmpty) return;
    _planHit = hits.first;
    _dragRoom = rooms.where((r) => r.id == selected.roomId).firstOrNull;
    _dragOrigin =
        _inverseTransform(_wallPointerOrigin ?? details.localFocalPoint);
    _dragPoints = _dragRoom?.points;
  }

  void _updateWallDrag(ScaleUpdateDetails details) {
    final room = _dragRoom, origin = _dragOrigin, hit = _planHit;
    if (room == null ||
        origin == null ||
        hit == null ||
        details.pointerCount != 1) {
      return;
    }
    final point = _inverseTransform(details.localFocalPoint);
    final dx = point.x - origin.x, dz = point.z - origin.z;
    final points = hit.corner
        ? List<ARPoint>.from(room.points)
        : PlanEditGeometry.moveWall(room, hit.index, dx, dz);
    if (hit.corner) {
      final old = points[hit.index];
      final radius = PlanEditGeometry.distance(
        _inverseTransform(Offset.zero),
        _inverseTransform(
            Offset(16 / _planViewport.value.getMaxScaleOnAxis(), 0)),
      );
      points[hit.index] = PlanEditGeometry.snapPoint(
        ARPoint(x: old.x + dx, y: old.y, z: old.z + dz),
        _plan.completedRooms.where((r) => r.id != room.id),
        radius,
      );
    }
    setState(() => _dragPoints = points);
  }

  Future<void> _endWallDrag() async {
    final room = _dragRoom, points = _dragPoints;
    if (room == null || points == null) return;
    final proposal = _plan.previewGeometry(room, points);
    setState(() {
      _dragRoom = null;
      _dragPoints = null;
      _dragOrigin = null;
    });
    if (proposal.error != null) {
      _planError(proposal.error!);
      return;
    }
    await _applyPlanProposal(proposal);
  }

  void _planError(PlanEditError error) {
    final l = AppLocalizations.of(context)!;
    _showMessage(
        switch (error) {
          PlanEditError.connection => l.planConnectionBlocked,
          PlanEditError.overlap => l.planOverlapBlocked,
          PlanEditError.noClosure => l.planNoClosure,
          PlanEditError.stale => l.planStaleEdit,
          PlanEditError.invalid => l.planInvalidGeometry,
        },
        error: true);
  }

  Future<void> _applyPlanProposal(PlanEditProposal proposal) async {
    if (_planSaving) return;
    final closedRoomIds = <String>{
      for (final beforeRoom in proposal.before)
        if (!beforeRoom.isClosed &&
            proposal.after.any(
              (afterRoom) =>
                  afterRoom.id == beforeRoom.id && afterRoom.isClosed,
            ))
          beforeRoom.id,
    };
    setState(() => _planSaving = true);
    final applied = await _plan.applyPlanEdit(proposal);

    if (applied && closedRoomIds.isNotEmpty) {
      final projectUuid = _plan.projectUuid;
      if (projectUuid != null) {
        const draftService = ScanDraftService();
        final draft = await draftService.load(projectUuid);
        if (draft != null && closedRoomIds.contains(draft.room.id)) {
          await draftService.clear(projectUuid);
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _planSaving = false;
      _pendingPlanEdit = null;
      _previewTitle = null;
    });
    if (!applied && !listEquals(proposal.before, _plan.completedRooms)) {
      _planError(PlanEditError.stale);
    }
  }

  void _previewEdit(bool close) {
    final hit = _planHit;
    if (hit == null) return;
    final room =
        _plan.completedRooms.where((r) => r.id == hit.roomId).firstOrNull;
    if (room == null) return;
    final proposal = close
        ? _plan.previewCloseRoom(room)
        : _plan.previewDeleteWall(room, hit.index);
    if (proposal.error != null) {
      _planError(proposal.error!);
      return;
    }
    final l = AppLocalizations.of(context)!;
    setState(() {
      _pendingPlanEdit = proposal;
      _previewTitle = close ? l.planClosePreview : l.planDeletePreview;
      _deletingPreview = !close;
    });
  }

  Future<void> _editSelectedLength() async {
    final hit = _planHit;
    if (hit == null || hit.corner) return;
    final room =
        _plan.completedRooms.where((r) => r.id == hit.roomId).firstOrNull;
    if (room == null) return;
    final length = PlanEditGeometry.distance(
      room.points[hit.index],
      room.points[(hit.index + 1) % room.points.length],
    );
    final route = DialogRoute<double>(
      context: context,
      builder: (_) => PlanWallLengthDialog(
        roomName: room.name,
        wallNumber: hit.index + 1,
        meters: length,
        system: context.read<MeasurementSettingsProvider>().system,
      ),
    );
    final value = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    if (!mounted || value == null) return;
    final points = PlanEditGeometry.resizeWall(room, hit.index, value);
    if (points == null) {
      _planError(PlanEditError.invalid);
      return;
    }
    final proposal = _plan.previewGeometry(room, points);
    if (proposal.error != null) {
      _planError(proposal.error!);
      return;
    }
    // Preview remains on the same plan, with the selected wall highlighted.
    setState(() {
      _pendingPlanEdit = proposal;
      _previewTitle = AppLocalizations.of(context)!.planMeasurePreview;
      _deletingPreview = false;
    });
  }

  Widget _buildPlanToolbar() {
    final provider = context.watch<FloorPlanProvider>();
    final l = AppLocalizations.of(context)!;
    final room = provider.completedRooms
        .where((r) => r.id == _planHit?.roomId)
        .firstOrNull;
    Widget action(
      String text,
      IconData icon,
      VoidCallback? onPressed, {
      Color? color,
      Key? key,
    }) =>
        OutlinedButton.icon(
          key: key,
          onPressed: onPressed,
          icon: Icon(icon, color: color),
          label: Text(text),
        );
    Widget actionGrid(List<Widget> children) => GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 8,
          mainAxisExtent: 44,
          children: children,
        );
    return SafeArea(
      top: false,
      child: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.50,
            minHeight: _planHit != null || _pendingPlanEdit != null
                ? MediaQuery.sizeOf(context).height * 0.43
                : 0,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_choosingContinuationClosing) ...[
                    Row(
                      children: [
                        const Icon(Icons.touch_app_rounded),
                        const SizedBox(width: 8),
                        Expanded(child: Text(l.chooseClosingCorner)),
                        IconButton(
                          tooltip: l.cancel,
                          onPressed: _cancelContinuationCornerSelection,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ] else if (_pendingPlanEdit != null) ...[
                    Text(_previewTitle!, textAlign: TextAlign.center),
                    Wrap(
                      spacing: 8,
                      children: [
                        action(
                          l.cancel,
                          Icons.close,
                          _planSaving
                              ? null
                              : () => setState(() {
                                    _pendingPlanEdit = null;
                                    _previewTitle = null;
                                  }),
                        ),
                        FilledButton.icon(
                          onPressed: _planSaving
                              ? null
                              : () async {
                                  await _applyPlanProposal(_pendingPlanEdit!);
                                  if (mounted) setState(_clearPlanSelection);
                                },
                          icon: const Icon(Icons.check),
                          label: Text(l.planConfirm),
                        ),
                      ],
                    ),
                  ] else if (room != null && _planHit != null) ...[
                    Text(
                      '${room.name} · ${_planHit!.corner ? l.planCorner : l.wall} ${_planHit!.index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(l.planDragSelection, textAlign: TextAlign.center),
                    actionGrid([
                        if (!_planHit!.corner)
                          action(
                            l.editMeasurements,
                            Icons.straighten,
                            _planSaving ? null : _editSelectedLength,
                          ),
                        if (!_planHit!.corner)
                          action(
                            l.planDeleteWall,
                            Icons.delete_outline,
                            _planSaving ? null : () => _previewEdit(false),
                          ),
                        if ((room.isClosed && _planHit!.corner) ||
                            (!room.isClosed &&
                                (!_planHit!.corner ||
                                    _planHit!.index == 0 ||
                                    _planHit!.index ==
                                        room.points.length - 1)))
                          action(
                            l.continueScan,
                            Icons.add_road_rounded,
                            _planSaving
                                ? null
                                : () => _continueOpenRoom(
                                      room,
                                      vertexIndex: _planHit!.corner
                                          ? _planHit!.index
                                          : null,
                                    ),
                            key: const ValueKey('plan-continue-scan'),
                          ),
                        if (!room.isClosed) ...[
                          action(
                            l.closeRoom,
                            Icons.check_circle_outline,
                            _planSaving ? null : () => _previewEdit(true),
                          ),
                        ],
                        action(
                          l.planDeleteRoom,
                          Icons.delete_forever_outlined,
                          _planSaving ? null : () => _deletePlanRoom(room),
                          key: const ValueKey('plan-delete-room'),
                        ),
                        action(
                          l.finishEditing,
                          Icons.done,
                          _planSaving
                              ? null
                              : () => setState(() {
                                    _clearPlanSelection();
                                    _wallEditMode = false;
                                  }),
                        ),
                      ],
                    ),
                  ] else if (_addOpeningType != null || _wallEditMode)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _addOpeningType == null
                                ? l.planSelectWall
                                : l.planTapWall,
                          ),
                        ),
                        IconButton(
                          tooltip: l.cancel,
                          onPressed: () => setState(() {
                            _clearPlanSelection();
                            _wallEditMode = false;
                          }),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  if (!_choosingContinuationClosing) ...[
                    SizedBox(
                      width: double.infinity,
                      child: action(
                        l.registeredRooms,
                        Icons.meeting_room_outlined,
                        _planSaving ? null : _showRoomListDialog,
                      ),
                    ),
                    const SizedBox(height: 6),
                    actionGrid([
                      action(
                        l.planAddDoor,
                        Icons.door_front_door,
                        _planSaving
                            ? null
                            : () => setState(() {
                                  _clearPlanSelection();
                                  _touchTransformMode = false;
                                  _addOpeningType = FeatureType.door;
                                }),
                        color: Colors.orange,
                        key: const ValueKey('plan-add-door'),
                      ),
                      action(
                        l.planAddWindow,
                        Icons.window,
                        _planSaving
                            ? null
                            : () => setState(() {
                                  _clearPlanSelection();
                                  _touchTransformMode = false;
                                  _addOpeningType = FeatureType.window;
                                }),
                        color: Colors.purple,
                        key: const ValueKey('plan-add-window'),
                      ),
                      action(
                        l.planUndo,
                        Icons.undo,
                        !_planSaving && provider.canUndoTransform
                            ? () async {
                                setState(_clearPlanSelection);
                                await provider.undoTransform();
                              }
                            : null,
                        key: const ValueKey('plan-undo'),
                      ),
                      action(
                        l.planRedo,
                        Icons.redo,
                        !_planSaving && provider.canRedoTransform
                            ? () async {
                                setState(_clearPlanSelection);
                                await provider.redoTransform();
                              }
                            : null,
                        key: const ValueKey('plan-redo'),
                      ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  CustomPainter _planSelectionPainter(List<RoomModel> rooms) =>
      _PlanSelectionPainter(
        _pendingPlanEdit != null && _deletingPreview
            ? _pendingPlanEdit!.before
            : rooms,
        _planHit,
        _transformPoint,
        _pendingPlanEdit?.returnPath ?? const [],
        continuationStart: _continuationStartHit,
        continuationClosing: _continuationClosingHit,
        deleting: _pendingPlanEdit != null && _deletingPreview,
      );

  Future<void> _deletePlanRoom(RoomModel room) async {
    if (_planSaving) return;
    final provider = _plan;
    final l = AppLocalizations.of(context)!;
    setState(() => _planSaving = true);
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.planDeleteRoom),
        content: Text(l.planDeleteRoomConfirmation(room.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('plan-confirm-delete-room'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l.planDeleteRoom),
          ),
        ],
      ),
    );
    try {
      final confirmed = await Navigator.of(context).push(route);
      await route.completed;
      if (!mounted || confirmed != true) return;
      // Do not delete a replacement or edited room after a stale dialog.
      if (!provider.completedRooms.any((r) => identical(r, room))) {
        _planError(PlanEditError.stale);
        return;
      }
      if (!await provider.removeRoom(room.id)) {
        if (mounted) _planError(PlanEditError.invalid);
        return;
      }
      if (!mounted) return;
      setState(() {
        _clearPlanSelection();
        _selectedRoomId = null;
        _wallEditMode = false;
      });
      _showMessage(l.planRoomDeleted);
    } finally {
      if (mounted) setState(() => _planSaving = false);
    }
  }
}

class _PlanSelectionPainter extends CustomPainter {
  final List<RoomModel> rooms;
  final _PlanHit? hit;
  final Offset Function(ARPoint) project;
  final List<ARPoint> returnPath;
  final bool deleting;
  final _PlanHit? continuationStart;
  final _PlanHit? continuationClosing;
  _PlanSelectionPainter(
    this.rooms,
    this.hit,
    this.project,
    this.returnPath, {
    this.deleting = false,
    this.continuationStart,
    this.continuationClosing,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = deleting ? Colors.redAccent : Colors.orange
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;
    final room = rooms.where((r) => r.id == hit?.roomId).firstOrNull;
    if (room != null && hit!.index < room.points.length) {
      final p = project(room.points[hit!.index]);
      if (hit!.corner) {
        canvas.drawCircle(p, 10, paint);
      } else if (hit!.index < PlanEditGeometry.wallCount(room)) {
        canvas.drawLine(
          p,
          project(room.points[(hit!.index + 1) % room.points.length]),
          paint,
        );
      }
    }
    paint.color = Colors.greenAccent;
    for (var i = 1; i < returnPath.length; i++) {
      canvas.drawLine(
        project(returnPath[i - 1]),
        project(returnPath[i]),
        paint,
      );
      canvas.drawCircle(project(returnPath[i]), 5, paint);
    }
    void drawContinuationCorner(_PlanHit? selection, Color color) {
      if (selection == null) return;
      final selectedRoom =
          rooms.where((room) => room.id == selection.roomId).firstOrNull;
      if (selectedRoom == null || selection.index >= selectedRoom.points.length) {
        return;
      }
      paint.color = color;
      canvas.drawCircle(project(selectedRoom.points[selection.index]), 13, paint);
    }

    drawContinuationCorner(continuationStart, Colors.orangeAccent);
    drawContinuationCorner(continuationClosing, Colors.greenAccent);
  }

  @override
  bool shouldRepaint(covariant _PlanSelectionPainter oldDelegate) => true;
}
