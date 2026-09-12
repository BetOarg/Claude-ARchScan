import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

typedef ProjectPersister = Future<void> Function({
  required String uuid,
  required String name,
  required List<RoomModel> rooms,
});

enum WallAlignmentResult {
  aligned,
  noCandidate,
  overlapPrevented,
  stalePreview;

  bool get isSuccess => this == WallAlignmentResult.aligned;
}

enum WallAlignmentPreviewStatus {
  available,
  noCandidate,
  overlapPrevented,
}

class WallAlignmentPreview {
  final List<RoomModel> currentRooms;
  final List<RoomModel> proposedRooms;
  final Set<String> transformedRoomIds;

  WallAlignmentPreview._({
    required List<RoomModel> currentRooms,
    required List<RoomModel> proposedRooms,
    required Set<String> transformedRoomIds,
  })  : currentRooms = List<RoomModel>.unmodifiable(currentRooms),
        proposedRooms = List<RoomModel>.unmodifiable(proposedRooms),
        transformedRoomIds = Set<String>.unmodifiable(transformedRoomIds);
}

class WallAlignmentPreviewResult {
  final WallAlignmentPreviewStatus status;
  final WallAlignmentPreview? preview;

  const WallAlignmentPreviewResult._({
    required this.status,
    this.preview,
  });

  const WallAlignmentPreviewResult.noCandidate()
      : this._(status: WallAlignmentPreviewStatus.noCandidate);

  const WallAlignmentPreviewResult.overlapPrevented()
      : this._(status: WallAlignmentPreviewStatus.overlapPrevented);

  WallAlignmentPreviewResult.available(WallAlignmentPreview preview)
      : this._(
          status: WallAlignmentPreviewStatus.available,
          preview: preview,
        );
}

enum AutomaticRoomMoveResult {
  moved,
  movedAndAdjusted,
  rejectedOverlap;

  bool get wasAdjusted => this == AutomaticRoomMoveResult.movedAndAdjusted;
  bool get wasRejected => this == AutomaticRoomMoveResult.rejectedOverlap;
}

class FloorPlanProvider extends ChangeNotifier {
  /// All plan edits share the same snapshot history, including connected rooms.
  PlanEditProposal previewGeometry(RoomModel original, List<ARPoint> points) {
    if (!_completedRooms.any((r) => identical(r, original))) {
      return const PlanEditProposal.failed(PlanEditError.stale);
    }
    final next = PlanEditGeometry.reshape(original, points);
    if (next == null) return const PlanEditProposal.failed(PlanEditError.invalid);
    for (final f in original.features.where((f) => f.isConnected)) {
      final updated = next.features.firstWhere((e) => e.id == f.id);
      if (PlanEditGeometry.distance(f.start, updated.start) > 1e-5 ||
          PlanEditGeometry.distance(f.end, updated.end) > 1e-5 ||
          PlanEditGeometry.featureWall(next, updated) < 0) {
        return const PlanEditProposal.failed(PlanEditError.connection);
      }
    }
    if (_completedRooms.any((r) => r.id != original.id && PlanEditGeometry.overlaps(next, r))) {
      return const PlanEditProposal.failed(PlanEditError.overlap);
    }
    return PlanEditProposal(_completedRooms, [
      for (final r in _completedRooms) r.id == original.id ? next : r,
    ]);
  }

  PlanEditProposal previewDeleteWall(RoomModel original, int index) {
    if (!_completedRooms.any((r) => identical(r, original))) {
      return const PlanEditProposal.failed(PlanEditError.stale);
    }
    final parts = PlanEditGeometry.deleteWall(original, index);
    if (parts.isEmpty) return const PlanEditProposal.failed(PlanEditError.invalid);
    for (var i = 1; i < parts.length; i++) {
      parts[i] = parts[i].copyWith(id: _nextUniqueId());
    }
    final proposed = <RoomModel>[];
    for (final room in _completedRooms) {
      if (room.id == original.id) { proposed.addAll(parts); continue; }
      final features = room.features.map((f) {
        if (f.connectedRoomId != original.id) return f;
        final owner = parts.where((r) => r.features.any((e) => e.id == f.id)).firstOrNull;
        if (owner != null) return f.copyWith(connectedRoomId: owner.id);
        // Its wall still exists in the neighbour: keep that opening, disconnected.
        final json = f.toJson()..remove('connectedRoomId')..remove('connectionSide');
        return WallFeature.fromJson(json);
      }).toList();
      proposed.add(room.copyWith(features: features));
    }
    return PlanEditProposal(_completedRooms, proposed);
  }

  PlanEditProposal previewCloseRoom(RoomModel original) {
    if (!_completedRooms.any((r) => identical(r, original))) {
      return const PlanEditProposal.failed(PlanEditError.stale);
    }
    final closure = PlanClosure.nearest(original, _completedRooms);
    if (closure == null) return const PlanEditProposal.failed(PlanEditError.noClosure);
    return PlanEditProposal(_completedRooms, [
      for (final r in _completedRooms) r.id == original.id ? closure.room : r,
    ], returnPath: closure.returnPath);
  }

  Future<bool> applyPlanEdit(PlanEditProposal proposal) async {
    if (proposal.error != null ||
        !_sameRoomSnapshot(proposal.before, _completedRooms) ||
        _sameRoomSnapshot(proposal.after, _completedRooms)) {
      return false;
    }
    final before = List<RoomModel>.from(_completedRooms);
    _completedRooms..clear()..addAll(proposal.after);
    notifyListeners();
    if (!await _persistRoomChange(before)) return false;
    if (_sameRoomSnapshot(proposal.after, _completedRooms)) {
      _recordTransform(before);
      notifyListeners();
    }
    return true;
  }

  static const double _defaultRoomSpacing = 1.0;
  static const int _maximumTransformHistoryEntries = 50;

  MeasurementSystem measurementSystem =
      MeasurementSystem.metric;

  String? _projectUuid;

  String _projectName = 'Mi Casa Completa';

  final List<RoomModel> _completedRooms = [];

  final List<_TransformHistoryEntry> _transformUndoHistory = [];
  final List<_TransformHistoryEntry> _transformRedoHistory = [];

  List<RoomModel>? _touchTransformBefore;
  List<RoomModel>? _touchTransformLastValid;
  String? _touchTransformRoomId;
  int _touchTransformSnapCount = 0;

  ProjectPersister? persister;

  static int _lastGeneratedId = 0;

  String? get projectUuid => _projectUuid;

  String get projectName => _projectName;

  int get touchTransformSnapCount => _touchTransformSnapCount;

  List<RoomModel> get completedRooms =>
      List.unmodifiable(
        _completedRooms,
      );

  bool get canUndoTransform =>
      _transformUndoHistory.isNotEmpty &&
      _sameRoomSnapshot(
        _transformUndoHistory.last.after,
        _completedRooms,
      );

  bool get canRedoTransform =>
      _transformRedoHistory.isNotEmpty &&
      _sameRoomSnapshot(
        _transformRedoHistory.last.before,
        _completedRooms,
      );

  // ===========================================================================
  // IDENTIFICADORES
  // ===========================================================================

  static String _nextUniqueId() {
    final now =
        DateTime.now().microsecondsSinceEpoch;

    if (now > _lastGeneratedId) {
      _lastGeneratedId = now;
    } else {
      _lastGeneratedId++;
    }

    return _lastGeneratedId.toString();
  }

  /// Repara IDs vacíos o repetidos.
  ///
  /// Permite abrir proyectos creados antes de incorporar
  /// el generador monotónico de identificadores.
  _RoomNormalizationResult _normalizeRoomIds(
    List<RoomModel> rooms,
  ) {
    final usedIds = <String>{};

    final normalized = <RoomModel>[];

    bool changed = false;

    for (final room in rooms) {
      var id = room.id.trim();

      if (id.isEmpty ||
          usedIds.contains(id)) {
        id = _nextUniqueId();

        changed = true;
      }

      usedIds.add(id);

      if (id != room.id) {
        normalized.add(
          room.copyWith(
            id: id,
          ),
        );
      } else {
        normalized.add(room);
      }
    }

    return _RoomNormalizationResult(
      rooms: normalized,
      changed: changed,
    );
  }

  // ===========================================================================
  // PROYECTO
  // ===========================================================================

  void loadProject({
    required String uuid,
    required String name,
    required List<RoomModel> rooms,
  }) {
    _projectUuid = uuid;

    _projectName = name;

    final normalized =
        _normalizeRoomIds(
      rooms,
    );

    _completedRooms
      ..clear()
      ..addAll(
        normalized.rooms,
      );

    _clearTransformHistory();

    notifyListeners();

    if (normalized.changed) {
      Future<void>.microtask(
        () async { await _persist(); },
      );
    }
  }

  Future<bool> _saveQueue = Future<bool>.value(true);

  Future<bool> _persist() {
    final uuid = _projectUuid;
    final save = persister;
    final name = _projectName;
    final rooms = List<RoomModel>.unmodifiable(_completedRooms);

    if (uuid == null ||
        save == null) {
      return Future<bool>.value(true);
    }

    // Capture identity and data now; execute writes in request order.
    final operation = _saveQueue.then((_) async {
      try {
        await save(uuid: uuid, name: name, rooms: rooms);
        return true;
      } catch (e) {
        debugPrint('No se pudo guardar el proyecto "$name": $e');
        return false;
      }
    });
    _saveQueue = operation;
    return operation;
  }

  /// A failed scan save must not leave an apparently completed room in memory.
  Future<bool> _persistRoomChange(List<RoomModel> before) async {
    final uuid = _projectUuid;
    final attempted = List<RoomModel>.from(_completedRooms);
    if (await _persist()) return true;
    // Never erase a later edit or a different project after an older failure.
    if (_projectUuid == uuid && _sameRoomSnapshot(attempted, _completedRooms)) {
      _completedRooms..clear()..addAll(before);
      notifyListeners();
    }
    return false;
  }

  bool canPlaceScannedRoom(RoomModel room) => !_completedRooms.any(
    (existing) => existing.id != room.id &&
        PlanEditGeometry.overlaps(room, existing),
  );

  Future<bool> _saveTransform(List<RoomModel> before) async {
    final uuid = _projectUuid;
    final after = List<RoomModel>.from(_completedRooms);
    notifyListeners();
    if (!await _persistRoomChange(before)) return false;
    if (_projectUuid == uuid && _sameRoomSnapshot(after, _completedRooms)) {
      _recordTransform(before);
      notifyListeners();
    }
    return true;
  }

  Future<void> setProjectName(
    String name,
  ) async {
    final normalized =
        name.trim();

    if (normalized.isEmpty) {
      return;
    }

    _projectName = normalized;

    notifyListeners();

    await _persist();
  }

  // ===========================================================================
  // HABITACIONES
  // ===========================================================================

  /// Agrega una habitación terminada.
  ///
  /// Si ya existen habitaciones en el proyecto, la nueva se posiciona
  /// automáticamente a continuación del plano existente.
  ///
  /// IMPORTANTE:
  ///
  /// Esto es una traslación rígida:
  ///
  ///   x' = x + offsetX
  ///   z' = z + offsetZ
  ///
  /// Por lo tanto NO modifica:
  ///
  /// - longitudes;
  /// - ángulos;
  /// - superficie;
  /// - perímetro;
  /// - forma del ambiente.
  Future<bool> addCompletedRoom(
    RoomModel room,
    {bool preservePlacement = false}
  ) async {
    var roomToAdd = room;

    final duplicate =
        _completedRooms.any(
      (existing) =>
          existing.id == room.id,
    );

    if (room.id.trim().isEmpty ||
        duplicate) {
      roomToAdd =
          room.copyWith(
        id: _nextUniqueId(),
      );
    }

    if (!preservePlacement &&
        _completedRooms.isNotEmpty &&
        roomToAdd.points.isNotEmpty) {
      roomToAdd =
          _placeRoomAfterExisting(
        roomToAdd,
      );
    }

    if (preservePlacement && !canPlaceScannedRoom(roomToAdd)) return false;
    final before = List<RoomModel>.from(_completedRooms);
    _completedRooms.add(
      roomToAdd,
    );

    notifyListeners();

    return _persistRoomChange(before);
  }

  /// Prepara un contorno para continuar desde una esquina válida.
  ///
  /// El scanner siempre agrega puntos al final de la lista. Si se elige el
  /// primer vértice, el recorrido se invierte sin modificar coordenadas,
  /// medidas, aberturas ni el ID histórico del ambiente. Los vértices
  /// intermedios de un contorno abierto se rechazan porque producirían una
  /// bifurcación. Desde un ambiente cerrado se prepara un ambiente nuevo: el
  /// original permanece intacto y su tramo entre ambas esquinas se convierte
  /// en el límite compartido con el nuevo recorrido.
  RoomModel? prepareOpenRoomContinuation({
    required String roomId,
    required int vertexIndex,
    int? closingVertexIndex,
  }) {
    final room = _completedRooms
        .where((candidate) => candidate.id == roomId)
        .firstOrNull;
    if (room == null || room.points.length < 2) return null;
    if (vertexIndex < 0 || vertexIndex >= room.points.length) return null;
    if (room.isClosed) {
      final closingIndex = closingVertexIndex;
      if (closingIndex == null ||
          closingIndex < 0 ||
          closingIndex >= room.points.length ||
          closingIndex == vertexIndex) {
        return null;
      }
      final continuationPoints = <ARPoint>[];
      var index = closingIndex;
      while (true) {
        continuationPoints.add(room.points[index]);
        if (index == vertexIndex) break;
        index = (index + 1) % room.points.length;
      }
      final reversePoints = <ARPoint>[];
      index = closingIndex;
      while (true) {
        reversePoints.add(room.points[index]);
        if (index == vertexIndex) break;
        index = (index - 1 + room.points.length) % room.points.length;
      }
      double pathLength(List<ARPoint> points) {
        var length = 0.0;
        for (var i = 1; i < points.length; i++) {
          length += GeometryService.calculateDistance(points[i - 1], points[i]);
        }
        return length;
      }
      final sharedPoints = pathLength(reversePoints) < pathLength(continuationPoints)
          ? reversePoints : continuationPoints;
      return RoomModel(
        id: _nextUniqueId(),
        name: room.name,
        type: room.type,
        points: sharedPoints,
        features: const [],
        isClosed: false,
      );
    }
    if (vertexIndex == room.points.length - 1) return room;
    if (vertexIndex != 0) return null;
    return room.copyWith(points: room.points.reversed.toList());
  }

  /// Reemplaza un ambiente abierto que se continuó en el scanner.
  ///
  /// Conserva el ID y la posición del ambiente original. Si el usuario sale
  /// del scanner sin cerrarlo, esta operación no se ejecuta y el contorno
  /// abierto permanece intacto en el plano.
  Future<bool> replaceCompletedRoom(
    RoomModel room, {
    RoomModel? expectedOpenRoom,
  }) async {
    final index = _completedRooms.indexWhere(
      (existing) => existing.id == room.id,
    );
    if (index == -1) return false;

    if (expectedOpenRoom != null &&
        jsonEncode(_completedRooms[index].toJson()) !=
            jsonEncode(expectedOpenRoom.toJson()) &&
        !_matchesContinuationSource(
          _completedRooms[index],
          expectedOpenRoom,
        )) {
      return false;
    }

    if (!canPlaceScannedRoom(room)) return false;
    final before = List<RoomModel>.from(_completedRooms);
    _completedRooms[index] = room;
    notifyListeners();
    return _persistRoomChange(before);
  }

  bool _matchesContinuationSource(RoomModel current, RoomModel prepared) {
    if (current.isClosed || current.points.length != prepared.points.length ||
        current.id != prepared.id ||
        current.name != prepared.name ||
        current.type != prepared.type ||
        jsonEncode(current.features.map((f) => f.toJson()).toList()) !=
            jsonEncode(prepared.features.map((f) => f.toJson()).toList())) {
      return false;
    }
    const tolerance = 0.000001;
    return prepared.points.every(
      (point) => current.points.any(
        (candidate) =>
            (candidate.x - point.x).abs() <= tolerance &&
            (candidate.y - point.y).abs() <= tolerance &&
            (candidate.z - point.z).abs() <= tolerance,
      ),
    );
  }

  /// Guarda un ambiente escaneado desde una puerta o ventana existente.
  ///
  /// El contorno recibido utiliza coordenadas locales del scanner:
  ///
  /// - el origen local se alinea con el extremo A o B elegido;
  /// - +Z apunta hacia el lado elegido para el nuevo ambiente;
  /// - +X conserva la dirección de 90° hacia la derecha.
  ///
  /// La operación actualiza los dos ambientes antes de notificar o persistir,
  /// evitando estados intermedios con una conexión incompleta.
  Future<bool> addCompletedRoomFromContinuation({
    required RoomModel room,
    required ScanContinuationReference reference,
  }) async {
    final sourceRoomIndex = _completedRooms.indexWhere(
      (existing) => existing.id == reference.sourceRoomId,
    );

    if (sourceRoomIndex == -1) {
      return false;
    }

    final sourceRoom = _completedRooms[sourceRoomIndex];
    final sourceFeatureIndex = sourceRoom.features.indexWhere(
      (feature) => feature.id == reference.featureId,
    );

    if (sourceFeatureIndex == -1 ||
        sourceRoom.features[sourceFeatureIndex].isConnected) {
      return false;
    }

    var roomToAdd = room;

    if (roomToAdd.id.trim().isEmpty ||
        _completedRooms.any(
          (existing) => existing.id == roomToAdd.id,
        )) {
      roomToAdd = roomToAdd.copyWith(
        id: _nextUniqueId(),
      );
    }

    roomToAdd = _alignRoomToContinuation(
      roomToAdd,
      reference,
    );

    final sourceFeatures = List<WallFeature>.from(
      sourceRoom.features,
    );
    final sourceFeature = sourceFeatures[sourceFeatureIndex];

    sourceFeatures[sourceFeatureIndex] = sourceFeature.copyWith(
      connectedRoomId: roomToAdd.id,
      connectionSide: reference.side,
    );

    final oppositeSide =
        reference.side == OpeningConnectionSide.left
            ? OpeningConnectionSide.right
            : OpeningConnectionSide.left;

    final sharedFeature = WallFeature(
      id: sourceFeature.id,
      type: sourceFeature.type,
      start: sourceFeature.start,
      end: sourceFeature.end,
      connectedRoomId: sourceRoom.id,
      connectionSide: oppositeSide,
      doorHingeSide: sourceFeature.doorHingeSide,
      doorSwingSide: sourceFeature.doorSwingSide,
      doorOpeningDirection: sourceFeature.doorOpeningDirection,
      openingHeightMeters: sourceFeature.openingHeightMeters,
      sillHeightMeters: sourceFeature.sillHeightMeters,
    );

    final newFeatures = List<WallFeature>.from(
      roomToAdd.features,
    );
    final existingSharedIndex = newFeatures.indexWhere(
      (feature) => feature.id == sharedFeature.id,
    );

    if (existingSharedIndex == -1) {
      newFeatures.add(sharedFeature);
    } else {
      newFeatures[existingSharedIndex] = sharedFeature;
    }

    roomToAdd = roomToAdd.copyWith(
      features: newFeatures,
    );

    if (!canPlaceScannedRoom(roomToAdd)) return false;
    final before = List<RoomModel>.from(_completedRooms);
    _completedRooms[sourceRoomIndex] = sourceRoom.copyWith(
      features: sourceFeatures,
    );
    _completedRooms.add(roomToAdd);

    notifyListeners();
    return _persistRoomChange(before);
  }

  RoomModel _alignRoomToContinuation(
    RoomModel room,
    ScanContinuationReference reference,
  ) {
    final openingDx =
        reference.globalEnd.x - reference.globalStart.x;
    final openingDz =
        reference.globalEnd.z - reference.globalStart.z;
    final openingLength = math.sqrt(
      openingDx * openingDx + openingDz * openingDz,
    );

    if (openingLength <= 0.000001) {
      return room;
    }

    final tangentX = openingDx / openingLength;
    final tangentZ = openingDz / openingLength;

    final forwardX =
        reference.side == OpeningConnectionSide.left
            ? -tangentZ
            : tangentZ;
    final forwardZ =
        reference.side == OpeningConnectionSide.left
            ? tangentX
            : -tangentX;

    final rightX = forwardZ;
    final rightZ = -forwardX;
    final origin = reference.origin;

    ARPoint transformPoint(ARPoint point) {
      return ARPoint(
        x: origin.x + point.x * rightX + point.z * forwardX,
        y: origin.y + point.y,
        z: origin.z + point.x * rightZ + point.z * forwardZ,
      );
    }

    return room.copyWith(
      points: room.points.map(transformPoint).toList(),
      features: room.features
          .map(
            (feature) => feature.copyWith(
              start: transformPoint(feature.start),
              end: transformPoint(feature.end),
            ),
          )
          .toList(),
    );
  }

  Future<bool> loadExistingRooms(
    List<RoomModel> rooms,
    String projectName,
  ) async {
    final uuid = _projectUuid;
    final previousName = _projectName;
    final before = List<RoomModel>.from(_completedRooms);
    final normalized =
        _normalizeRoomIds(
      rooms,
    );

    _completedRooms
      ..clear()
      ..addAll(
        normalized.rooms,
      );

    _projectName = projectName;

    notifyListeners();

    final imported = List<RoomModel>.from(_completedRooms);
    if (!await _persist()) {
      if (_projectUuid == uuid && _projectName == projectName &&
          _sameRoomSnapshot(imported, _completedRooms)) {
        _completedRooms..clear()..addAll(before);
        _projectName = previousName;
        notifyListeners();
      }
      return false;
    }
    if (_projectUuid == uuid && _sameRoomSnapshot(imported, _completedRooms)) {
      _clearTransformHistory();
      notifyListeners();
    }
    return true;
  }

  Future<bool> removeRoom(
    String roomId,
  ) async {
    final before = List<RoomModel>.from(_completedRooms);
    _completedRooms.removeWhere((room) => room.id == roomId);
    for (var i = 0; i < _completedRooms.length; i++) {
      final room = _completedRooms[i];
      _completedRooms[i] = room.copyWith(features: room.features.map((f) {
        if (f.connectedRoomId != roomId) return f;
        return WallFeature.fromJson(f.toJson()..remove('connectedRoomId')..remove('connectionSide'));
      }).toList());
    }
    return _saveTransform(before);
  }

  /// Deletes both copies of a shared opening without deleting room geometry.
  Future<bool> removeOpening(String roomId, String featureId) async {
    final source = _completedRooms.where((r) => r.id == roomId).firstOrNull;
    final feature = source?.features.where((f) => f.id == featureId).firstOrNull;
    if (feature == null) return false;
    final before = List<RoomModel>.from(_completedRooms);
    for (var i = 0; i < _completedRooms.length; i++) {
      final room = _completedRooms[i];
      if (room.id != roomId && room.id != feature.connectedRoomId) continue;
      _completedRooms[i] = room.copyWith(features: room.features.where((f) =>
        !(f.id == featureId && (room.id == roomId || f.connectedRoomId == roomId))).toList());
    }
    return _saveTransform(before);
  }


  Future<void> updateRoomName(
    String roomId,
    String newName,
  ) async {
    final index =
        _completedRooms.indexWhere(
      (room) =>
          room.id == roomId,
    );

    if (index == -1) {
      return;
    }

    final normalized =
        newName.trim();

    if (normalized.isEmpty) {
      return;
    }

    final before = List<RoomModel>.from(_completedRooms);
    _completedRooms[index] =
        _completedRooms[index]
            .copyWith(
      name: normalized,
    );

    _recordTransform(before);
    notifyListeners();

    await _persist();
  }

  // ===========================================================================  // POSICIONAMIENTO GLOBAL  // ===========================================================================

  /// Traslada una habitación completa.
  ///
  /// Se trasladan también todas sus puertas y ventanas.
  RoomModel _translateRoom(
    RoomModel room, {
    required double offsetX,
    required double offsetZ,
  }) {
    final translatedPoints =
        room.points.map(      (point) {        return ARPoint(          x: point.x + offsetX,
          y: point.y,
          z: point.z + offsetZ,
        );
      },
    ).toList();

    final translatedFeatures =
        room.features.map(
      (feature) {
        return feature.copyWith(
          start: ARPoint(
            x:
                feature.start.x +
                    offsetX,
            y: feature.start.y,
            z:
                feature.start.z +
                    offsetZ,
          ),
          end: ARPoint(
            x:
                feature.end.x +
                    offsetX,
            y: feature.end.y,
            z:
                feature.end.z +
                    offsetZ,
          ),
        );
      },
    ).toList();

    return room.copyWith(
      points: translatedPoints,
      features: translatedFeatures,
    );
  }

  /// Posiciona una habitación nueva después de las existentes.
  ///
  /// El comportamiento inicial es deliberadamente simple y predecible:
  ///
  ///   Habitación 1   Habitación 2   Habitación 3
  ///   ┌───────┐      ┌───────┐      ┌───────┐
  ///   │       │ 1 m  │       │ 1 m  │       │
  ///   └───────┘      └───────┘      └───────┘
  RoomModel _placeRoomAfterExisting(
    RoomModel room,
  ) {
    if (_completedRooms.isEmpty ||
        room.points.isEmpty) {
      return room;
    }

    double projectMaxX =
        double.negativeInfinity;

    double projectMinZ =
        double.infinity;    for (final existing
        in _completedRooms) {
      for (final point
          in existing.points) {
        if (point.x >
            projectMaxX) {
          projectMaxX =
              point.x;
        }

        if (point.z <
            projectMinZ) {
          projectMinZ =
              point.z;
        }
      }
    }

    if (!projectMaxX.isFinite) {
      projectMaxX = 0.0;
    }

    if (!projectMinZ.isFinite) {
      projectMinZ = 0.0;
    }
    double roomMinX =
        double.infinity;

    double roomMinZ =
        double.infinity;

    for (final point
        in room.points) {
      if (point.x < roomMinX) {
        roomMinX =
            point.x;      }

      if (point.z < roomMinZ) {
        roomMinZ =
            point.z;
      }
    }
    if (!roomMinX.isFinite) {
      roomMinX = 0.0;
    }

    if (!roomMinZ.isFinite) {
      roomMinZ = 0.0;
    }

    final targetMinX =
        projectMaxX +
            _defaultRoomSpacing;

    final offsetX =
        targetMinX -
            roomMinX;

    final offsetZ =
        projectMinZ -
            roomMinZ;

    return _translateRoom(
      room,
      offsetX: offsetX,
      offsetZ: offsetZ,
    );
  }

  /// Arranges independent groups; connections and shared walls stay rigid.
  /// The first group is the anchor. A single assembled plan is never moved.
  Future<bool> autoArrangeRooms({
    double spacing = _defaultRoomSpacing,
  }) async {
    if (_completedRooms.length <= 1 || !spacing.isFinite || spacing < 0 ||
        _touchTransformBefore != null) {
      return false;
    }
    final before = List<RoomModel>.from(_completedRooms);
    final byId = {for (final room in before) room.id: room};
    final links = {for (final room in before) room.id: <String>{}};
    void connect(String a, String b) {
      if (!links.containsKey(a) || !links.containsKey(b) || a == b) return;
      links[a]!.add(b);
      links[b]!.add(a);
    }
    for (final room in before) {
      for (final feature in room.features) {
        final target = feature.connectedRoomId;
        if (target != null) connect(room.id, target);
      }
    }
    for (final wall in SharedWallService.detect(rooms: before)) {
      final first = byId[wall.firstRoomId]!;
      final second = byId[wall.secondRoomId]!;
      // Coincident legacy scans are not assembled rooms.
      if (!_polygonsHaveInteriorOverlap(first.points, second.points)) {
        connect(first.id, second.id);
      }
    }
    // Real scans can leave a few centimetres between walls that are visually
    // assembled. Keep those rooms in the same rigid group so Arrange never
    // tears apart a plan the user has already positioned.
    for (var firstIndex = 0; firstIndex < before.length; firstIndex++) {
      for (var secondIndex = firstIndex + 1;
          secondIndex < before.length;
          secondIndex++) {
        final first = before[firstIndex];
        final second = before[secondIndex];
        if (!_polygonsHaveInteriorOverlap(first.points, second.points) &&
            _roomsAreVisuallyAttached(first, second)) {
          connect(first.id, second.id);
        }
      }
    }
    final seen = <String>{};
    final groups = <Set<String>>[];
    for (final room in before) {
      if (seen.contains(room.id)) continue;
      final group = <String>{};
      final pending = <String>[room.id];
      while (pending.isNotEmpty) {
        final id = pending.removeLast();
        if (!seen.add(id)) continue;
        group.add(id);
        pending.addAll(links[id]!);
      }
      groups.add(group);
    }
    if (groups.length <= 1) return false;
    // Validate every group before changing any part of the project.
    final bounds = <List<double>>[];
    for (final group in groups) {
      final points = [
        for (final room in before)
          if (group.contains(room.id)) ...room.points,
      ];
      if (points.isEmpty || points.any((p) => !p.x.isFinite || !p.z.isFinite)) {
        return false;
      }
      bounds.add([
        points.map((p) => p.x).reduce(math.min),
        points.map((p) => p.x).reduce(math.max),
        points.map((p) => p.z).reduce(math.min),
      ]);
    }
    final arranged = List<RoomModel>.from(before);
    var nextX = bounds.first[1] + spacing;
    final baselineZ = bounds.first[2];
    var changed = false;
    for (var g = 1; g < groups.length; g++) {
      final offsetX = nextX - bounds[g][0];
      final offsetZ = baselineZ - bounds[g][2];
      if (offsetX.abs() > 0.000001 || offsetZ.abs() > 0.000001) {
        for (var i = 0; i < before.length; i++) {
          if (groups[g].contains(before[i].id)) {
            arranged[i] = _translateRoom(before[i],
                offsetX: offsetX, offsetZ: offsetZ);
          }
        }
        changed = true;
      }
      nextX += bounds[g][1] - bounds[g][0] + spacing;
    }
    if (!changed) return false;
    _completedRooms
      ..clear()
      ..addAll(arranged);
    _recordTransform(before);
    notifyListeners();
    await _persist();
    return true;
  }

  bool _roomsAreVisuallyAttached(
    RoomModel first,
    RoomModel second, {
    double maximumGapMeters = 0.12,
  }) {
    if (first.points.length < 2 || second.points.length < 2) return false;
    final maximumGapSquared = maximumGapMeters * maximumGapMeters;

    bool pointNearRoom(ARPoint point, RoomModel room) {
      for (var index = 0;
          index < PlanEditGeometry.wallCount(room);
          index++) {
        if (_distanceSquaredToSegment(
              point,
              room.points[index],
              room.points[(index + 1) % room.points.length],
            ) <=
            maximumGapSquared) {
          return true;
        }
      }
      return false;
    }

    return first.points.any((point) => pointNearRoom(point, second)) ||
        second.points.any((point) => pointNearRoom(point, first));
  }

  /// Mueve manualmente un ambiente completo.
  ///
  /// Esta API queda preparada para un editor de distribución posterior.
  Future<void> translateRoom({
    required String roomId,
    required double offsetX,
    required double offsetZ,
  }) async {
    if (!offsetX.isFinite ||
        !offsetZ.isFinite ||
        (offsetX.abs() <= 0.000001 &&
            offsetZ.abs() <= 0.000001)) {
      return;
    }

    final connectedIds =
        _connectedRoomIds(roomId);

    if (connectedIds.isEmpty) {
      return;
    }

    final before = List<RoomModel>.from(_completedRooms);

    for (var index = 0;
        index < _completedRooms.length;
        index++) {
      final room = _completedRooms[index];

      if (!connectedIds.contains(room.id)) {
        continue;
      }

      _completedRooms[index] = _translateRoom(
        room,
        offsetX: offsetX,
        offsetZ: offsetZ,
      );
    }

    _recordTransform(before);

    notifyListeners();

    await _persist();
  }

  /// Mueve el ambiente y ajusta automáticamente un hueco pequeño cercano.
  /// Si el ajuste no es seguro, conserva solamente el movimiento solicitado.
  Future<AutomaticRoomMoveResult> translateRoomAutomatically({
    required String roomId,
    required double offsetX,
    required double offsetZ,
  }) async {
    final connectedIds = _connectedRoomIds(roomId);
    final proposedMove = _WallAlignmentCandidate(
      centerX: 0.0,
      centerZ: 0.0,
      rotationRadians: 0.0,
      offsetX: offsetX,
      offsetZ: offsetZ,
      score: 0.0,
    );
    if (connectedIds.isEmpty ||
        _alignmentCreatesInteriorOverlap(
          candidate: proposedMove,
          connectedIds: connectedIds,
        )) {
      return AutomaticRoomMoveResult.rejectedOverlap;
    }

    final historyLengthBefore = _transformUndoHistory.length;
    await translateRoom(
      roomId: roomId,
      offsetX: offsetX,
      offsetZ: offsetZ,
    );

    final correction = await correctSmallWallGap(roomId: roomId);
    if (!correction.isSuccess) {
      return AutomaticRoomMoveResult.moved;
    }

    if (_transformUndoHistory.length >= historyLengthBefore + 2) {
      final correctionEntry = _transformUndoHistory.removeLast();
      final movementEntry = _transformUndoHistory.removeLast();
      _transformUndoHistory.add(
        _TransformHistoryEntry(
          before: movementEntry.before,
          after: correctionEntry.after,
        ),
      );
    }

    return AutomaticRoomMoveResult.movedAndAdjusted;
  }

  /// Rota rígidamente un ambiente y todo su grupo conectado.
  ///
  /// El centro de giro es el centro geométrico común de los puntos del grupo.
  /// Las puertas y ventanas se transforman junto con los contornos, por lo que
  /// las copias de una abertura compartida conservan el mismo ID y posición.
  Future<bool> rotateRoom({
    required String roomId,
    required double angleDegrees,
  }) async {
    if (!angleDegrees.isFinite ||
      angleDegrees.abs() <= 0.000001) {
      return false;
    }

    final connectedIds = _connectedRoomIds(roomId);
    if (connectedIds.isEmpty) {
      return false;
    }

    final groupPoints = <ARPoint>[
      for (final room in _completedRooms)
        if (connectedIds.contains(room.id)) ...room.points,
    ];

    if (groupPoints.isEmpty) {
      return false;
    }

    final before = List<RoomModel>.from(_completedRooms);

    final centerX = groupPoints
            .map((point) => point.x)
            .reduce((value, element) => value + element) /
        groupPoints.length;
    final centerZ = groupPoints
            .map((point) => point.z)
            .reduce((value, element) => value + element) /
        groupPoints.length;
    final radians = angleDegrees * math.pi / 180.0;
    final proposedRotation = _WallAlignmentCandidate(
      centerX: centerX,
      centerZ: centerZ,
      rotationRadians: radians,
      offsetX: 0.0,
      offsetZ: 0.0,
      score: 0.0,
    );
    if (_alignmentCreatesInteriorOverlap(
      candidate: proposedRotation,
      connectedIds: connectedIds,
    )) {
      return false;
    }

    for (var index = 0;
        index < _completedRooms.length;
        index++) {
      final room = _completedRooms[index];

      if (!connectedIds.contains(room.id)) {
        continue;
      }

      _completedRooms[index] = _rotateRoom(
        room,
        centerX: centerX,
        centerZ: centerZ,
        radians: radians,
      );
    }

    _recordTransform(before);

    notifyListeners();
    await _persist();
    return true;
  }

  /// Inicia una corrección táctil de un único ambiente.
  ///
  /// A diferencia de las transformaciones generales, esta operación no mueve
  /// el grupo conectado. Las aberturas compartidas permanecen fijas para que
  /// funcionen como anclajes visuales al volver a unir un ambiente desfasado.
  bool beginTouchRoomTransform(String roomId) {
    if (!_completedRooms.any((room) => room.id == roomId)) {
      return false;
    }
    _touchTransformBefore = List<RoomModel>.from(_completedRooms);
    _touchTransformLastValid = List<RoomModel>.from(_completedRooms);
    _touchTransformRoomId = roomId;
    _touchTransformSnapCount = 0;
    return true;
  }

  bool updateTouchRoomTransform({
    required String roomId,
    required double offsetX,
    required double offsetZ,
    required double angleDegrees,
  }) {
    final before = _touchTransformBefore;
    if (before == null ||
        _touchTransformRoomId != roomId ||
        !offsetX.isFinite ||
        !offsetZ.isFinite ||
        !angleDegrees.isFinite) {
      return false;
    }

    final originalIndex = before.indexWhere((room) => room.id == roomId);
    final currentIndex = _completedRooms.indexWhere((room) => room.id == roomId);
    if (originalIndex == -1 || currentIndex == -1) {
      return false;
    }

    final original = before[originalIndex];
    if (original.points.isEmpty) return false;
    final centerX = original.points
            .map((point) => point.x)
            .reduce((value, element) => value + element) /
        original.points.length;
    final centerZ = original.points
            .map((point) => point.z)
            .reduce((value, element) => value + element) /
        original.points.length;
    final radians = angleDegrees * math.pi / 180.0;
    final rotated = _rotateRoomPreservingConnectedOpenings(
      original,
      centerX: centerX,
      centerZ: centerZ,
      radians: radians,
    );
    _completedRooms[currentIndex] = _translateRoomPreservingConnectedOpenings(
      rotated,
      offsetX: offsetX,
      offsetZ: offsetZ,
    );
    _touchTransformSnapCount = _applyLiveMagneticSnap(roomId);
    final movedRoomIndex =
        _completedRooms.indexWhere((room) => room.id == roomId);
    final hasOverlap = movedRoomIndex == -1 ||
        _completedRooms.indexed.any((entry) {
          if (entry.$1 == movedRoomIndex) return false;
          return _polygonsHaveInteriorOverlap(
            _completedRooms[movedRoomIndex].points,
            entry.$2.points,
          );
        });
    if (!hasOverlap) {
      _touchTransformLastValid = List<RoomModel>.from(_completedRooms);
    }
    notifyListeners();
    return true;
  }

  int _applyLiveMagneticSnap(String roomId) {
    final releaseDistance = _touchTransformSnapCount > 0 ? 0.22 : 0.15;

    // Connected openings remain the strongest anchor and are never displaced.
    if (_snapRoomToConnectedOpening(
      roomId,
      maximumDistance: releaseDistance,
    )) {
      return _sharedWallCountForRoom(roomId, _completedRooms);
    }

    var contactCount = _sharedWallCountForRoom(roomId, _completedRooms);
    for (var pass = 0; pass < 3; pass++) {
      final preview = createWallAlignmentPreview(
        roomId: roomId,
        maximumDistanceMeters: releaseDistance,
        maximumAngleDegrees: 4.0,
        minimumOverlapMeters: 0.20,
      ).preview;
      if (preview == null) break;

      final proposedContacts =
          _sharedWallCountForRoom(roomId, preview.proposedRooms);
      if (proposedContacts == 0 ||
          (pass > 0 && proposedContacts <= contactCount)) {
        break;
      }

      _completedRooms
        ..clear()
        ..addAll(preview.proposedRooms);
      contactCount = proposedContacts;
      if (contactCount >= 3) break;
    }
    return contactCount;
  }

  int _sharedWallCountForRoom(
    String roomId,
    List<RoomModel> rooms,
  ) {
    return SharedWallService.detect(rooms: rooms)
        .where(
          (wall) =>
              wall.firstRoomId == roomId || wall.secondRoomId == roomId,
        )
        .length;
  }

  Future<bool> endTouchRoomTransform({
    required String roomId,
    bool snapToConnectedOpening = true,
  }) async {
    final before = _touchTransformBefore;
    if (before == null || _touchTransformRoomId != roomId) return false;

    if (snapToConnectedOpening) {
      final snappedToOpening =
          _snapRoomToConnectedOpening(roomId, maximumDistance: 0.75);
      if (!snappedToOpening) {
        // The live preview can already show a valid shared wall while the
        // dragged polygon is a few millimetres past it. Apply the same exact
        // wall alignment before the final overlap check so a green join is
        // accepted, without relaxing rejection of genuine interior overlap.
        final wallSnap = createWallAlignmentPreview(
          roomId: roomId,
          maximumDistanceMeters: 0.10,
          maximumAngleDegrees: 2.0,
          minimumOverlapMeters: 0.20,
        ).preview;
        if (wallSnap != null) {
          _completedRooms
            ..clear()
            ..addAll(wallSnap.proposedRooms);
          notifyListeners();
        }
      }
    }

    final roomIndex = _completedRooms.indexWhere((room) => room.id == roomId);
    final invalid = roomIndex == -1 || _completedRooms.indexed.any((entry) {
      if (entry.$1 == roomIndex) return false;
      return _polygonsHaveInteriorOverlap(
        _completedRooms[roomIndex].points,
        entry.$2.points,
      );
    });

    final lastValid = _touchTransformLastValid;
    _touchTransformBefore = null;
    _touchTransformLastValid = null;
    _touchTransformRoomId = null;
    _touchTransformSnapCount = 0;
    if (invalid) {
      _completedRooms
        ..clear()
        ..addAll(lastValid ?? before);
      notifyListeners();
      if (_sameRoomSnapshot(before, _completedRooms)) return false;
      return _saveTransform(before);
    }

    return _saveTransform(before);
  }

  void cancelTouchRoomTransform() {
    final before = _touchTransformBefore;
    _touchTransformBefore = null;
    _touchTransformLastValid = null;
    _touchTransformRoomId = null;
    _touchTransformSnapCount = 0;
    if (before == null) return;
    _completedRooms
      ..clear()
      ..addAll(before);
    notifyListeners();
  }

  /// Aplica una traslación y rotación manuales exactas al grupo conectado.
  ///
  /// La transformación se registra como una sola operación y se rechaza si
  /// produce solapamientos interiores.
  Future<bool> transformRoomPrecisely({
    required String roomId,
    required double offsetX,
    required double offsetZ,
    required double angleDegrees,
  }) async {
    if (!offsetX.isFinite ||
        !offsetZ.isFinite ||
        !angleDegrees.isFinite ||
        (offsetX.abs() <= 0.000001 &&
            offsetZ.abs() <= 0.000001 &&
            angleDegrees.abs() <= 0.000001)) {
      return false;
    }

    final connectedIds = _connectedRoomIds(roomId);
    if (connectedIds.isEmpty) {
      return false;
    }

    final groupPoints = <ARPoint>[
      for (final room in _completedRooms)
        if (connectedIds.contains(room.id)) ...room.points,
    ];
    if (groupPoints.isEmpty) {
      return false;
    }

    final centerX = groupPoints
            .map((point) => point.x)
            .reduce((value, element) => value + element) /
        groupPoints.length;
    final centerZ = groupPoints
            .map((point) => point.z)
            .reduce((value, element) => value + element) /
        groupPoints.length;
    final candidate = _WallAlignmentCandidate(
      centerX: centerX,
      centerZ: centerZ,
      rotationRadians: angleDegrees * math.pi / 180.0,
      offsetX: offsetX,
      offsetZ: offsetZ,
      score: 0,
    );
    if (_alignmentCreatesInteriorOverlap(
      candidate: candidate,
      connectedIds: connectedIds,
    )) {
      return false;
    }

    final before = List<RoomModel>.from(_completedRooms);
    for (var index = 0; index < _completedRooms.length; index++) {
      final room = _completedRooms[index];
      if (!connectedIds.contains(room.id)) {
        continue;
      }
      final rotated = _rotateRoom(
        room,
        centerX: centerX,
        centerZ: centerZ,
        radians: candidate.rotationRadians,
      );
      _completedRooms[index] = _translateRoom(
        rotated,
        offsetX: offsetX,
        offsetZ: offsetZ,
      );
    }

    _recordTransform(before);
    notifyListeners();
    await _persist();
    return true;
  }

  /// Alinea rígidamente el ambiente seleccionado con la pared externa más
  /// cercana que sea paralela y tenga una superposición longitudinal útil.
  /// El grupo conectado se transforma como una sola unidad.
  Future<bool> alignRoomToNearestWall({
    required String roomId,
    double maximumDistanceMeters = 0.30,
    double maximumAngleDegrees = 5.0,
    double minimumOverlapMeters = 0.20,
  }) async {
    final result = await alignRoomToNearestWallDetailed(
      roomId: roomId,
      maximumDistanceMeters: maximumDistanceMeters,
      maximumAngleDegrees: maximumAngleDegrees,
      minimumOverlapMeters: minimumOverlapMeters,
    );
    return result.isSuccess;
  }

  /// Corrige únicamente huecos pequeños entre paredes que deberían coincidir.
  ///
  /// La corrección es rígida, incluye el grupo conectado y utiliza la misma
  /// validación de solapamientos que la alineación general.
  Future<WallAlignmentResult> correctSmallWallGap({
    required String roomId,
    double maximumGapMeters = 0.10,
    double maximumAngleDegrees = 2.0,
    double minimumOverlapMeters = 0.20,
  }) {
    return alignRoomToNearestWallDetailed(
      roomId: roomId,
      maximumDistanceMeters: maximumGapMeters,
      maximumAngleDegrees: maximumAngleDegrees,
      minimumOverlapMeters: minimumOverlapMeters,
    );
  }

  /// Alinea paredes cercanas y permite distinguir entre la ausencia de una
  /// coincidencia geométrica y una corrección rechazada por solapamiento.
  ///
  /// Conserva la API booleana anterior mediante [alignRoomToNearestWall] para
  /// no afectar pantallas ni integraciones existentes.
  Future<WallAlignmentResult> alignRoomToNearestWallDetailed({
    required String roomId,
    String? targetRoomId,
    double maximumDistanceMeters = 0.30,
    double maximumAngleDegrees = 5.0,
    double minimumOverlapMeters = 0.20,
  }) async {
    final previewResult = createWallAlignmentPreview(
      roomId: roomId,
      targetRoomId: targetRoomId,
      maximumDistanceMeters: maximumDistanceMeters,
      maximumAngleDegrees: maximumAngleDegrees,
      minimumOverlapMeters: minimumOverlapMeters,
    );
    final preview = previewResult.preview;
    if (preview == null) {
      return previewResult.status == WallAlignmentPreviewStatus.overlapPrevented
          ? WallAlignmentResult.overlapPrevented
          : WallAlignmentResult.noCandidate;
    }
    return applyWallAlignmentPreview(preview);
  }

  /// Aplica exactamente la geometría confirmada por el usuario.
  ///
  /// La vista previa queda invalidada si el plano cambió desde su creación.
  Future<WallAlignmentResult> applyWallAlignmentPreview(
    WallAlignmentPreview preview,
  ) async {
    if (!_sameRoomSnapshot(preview.currentRooms, _completedRooms)) {
      return WallAlignmentResult.stalePreview;
    }

    final before = List<RoomModel>.from(_completedRooms);
    _completedRooms
      ..clear()
      ..addAll(preview.proposedRooms);
    _recordTransform(before);
    notifyListeners();
    await _persist();
    return WallAlignmentResult.aligned;
  }

  WallAlignmentPreviewResult createWallAlignmentPreview({
    required String roomId,
    String? targetRoomId,
    double maximumDistanceMeters = 0.30,
    double maximumAngleDegrees = 5.0,
    double minimumOverlapMeters = 0.20,
  }) {
    final sourceRoomIndex = _completedRooms.indexWhere(
      (room) => room.id == roomId,
    );
    if (sourceRoomIndex == -1 ||
        targetRoomId == roomId ||
        maximumDistanceMeters <= 0 ||
        maximumAngleDegrees <= 0) {
      return const WallAlignmentPreviewResult.noCandidate();
    }

    final sourceRoom = _completedRooms[sourceRoomIndex];
    final connectedIds = _connectedRoomIds(roomId);
    if (sourceRoom.points.length < 2 || connectedIds.isEmpty) {
      return const WallAlignmentPreviewResult.noCandidate();
    }

    _WallAlignmentCandidate? bestCandidate;
    var overlapPrevented = false;
    final maximumAngleRadians =
        maximumAngleDegrees * math.pi / 180.0;

    for (var sourceIndex = 0;
        sourceIndex < sourceRoom.points.length;
        sourceIndex++) {
      final sourceStart = sourceRoom.points[sourceIndex];
      final sourceEnd = sourceRoom.points[
        (sourceIndex + 1) % sourceRoom.points.length
      ];
      final sourceDx = sourceEnd.x - sourceStart.x;
      final sourceDz = sourceEnd.z - sourceStart.z;
      final sourceLength = math.sqrt(
        sourceDx * sourceDx + sourceDz * sourceDz,
      );
      if (sourceLength <= 0.000001) {
        continue;
      }

      final sourceUnitX = sourceDx / sourceLength;
      final sourceUnitZ = sourceDz / sourceLength;
      final sourceMidX = (sourceStart.x + sourceEnd.x) / 2.0;
      final sourceMidZ = (sourceStart.z + sourceEnd.z) / 2.0;

      for (final targetRoom in _completedRooms) {
        if (connectedIds.contains(targetRoom.id) ||
            (targetRoomId != null && targetRoom.id != targetRoomId) ||
            targetRoom.points.length < 2) {
          continue;
        }

        for (var targetIndex = 0;
            targetIndex < targetRoom.points.length;
            targetIndex++) {
          final targetStart = targetRoom.points[targetIndex];
          final targetEnd = targetRoom.points[
            (targetIndex + 1) % targetRoom.points.length
          ];
          final targetDx = targetEnd.x - targetStart.x;
          final targetDz = targetEnd.z - targetStart.z;
          final targetLength = math.sqrt(
            targetDx * targetDx + targetDz * targetDz,          );
          if (targetLength <= 0.000001) {            continue;
          }

          var targetUnitX = targetDx / targetLength;
          var targetUnitZ = targetDz / targetLength;
          var targetOriginX = targetStart.x;
          var targetOriginZ = targetStart.z;
          var directionDot =
              sourceUnitX * targetUnitX + sourceUnitZ * targetUnitZ;
          if (directionDot < 0) {
            targetUnitX = -targetUnitX;
            targetUnitZ = -targetUnitZ;
            targetOriginX = targetEnd.x;
            targetOriginZ = targetEnd.z;
            directionDot = -directionDot;
          }
          final angleRadians = math.acos(
            directionDot.clamp(-1.0, 1.0).toDouble(),
          );
          if (angleRadians > maximumAngleRadians) {
            continue;
          }

          final targetNormalX = -targetUnitZ;
          final targetNormalZ = targetUnitX;
          final signedDistance =
              (sourceMidX - targetOriginX) * targetNormalX +
                  (sourceMidZ - targetOriginZ) * targetNormalZ;
          if (signedDistance.abs() > maximumDistanceMeters) {
            continue;
          }
          final cross =
              sourceUnitX * targetUnitZ - sourceUnitZ * targetUnitX;
          final rotationRadians = math.atan2(cross, directionDot);
          final sourceProjectionCenter =
              (sourceMidX - targetOriginX) * targetUnitX +
                  (sourceMidZ - targetOriginZ) * targetUnitZ;
          final sourceProjectionStart =
              sourceProjectionCenter - sourceLength / 2.0;
          final sourceProjectionEnd =
              sourceProjectionCenter + sourceLength / 2.0;
          final overlap = math.min(
                sourceProjectionEnd,
                targetLength,
              ) -
              math.max(sourceProjectionStart, 0.0);
          final requiredOverlap = math.min(
            minimumOverlapMeters,
            math.min(sourceLength, targetLength) * 0.25,
          );
          if (overlap < requiredOverlap) {
            continue;
          }

          final sourceCenter = _roomCenter(sourceRoom);
          final targetCenter = _roomCenter(targetRoom);
          final cosine = math.cos(rotationRadians);
          final sine = math.sin(rotationRadians);
          final relativeCenterX = sourceCenter.x - sourceMidX;
          final relativeCenterZ = sourceCenter.z - sourceMidZ;
          final rotatedCenterX = sourceMidX +
              relativeCenterX * cosine - relativeCenterZ * sine;
          final rotatedCenterZ = sourceMidZ +
              relativeCenterX * sine + relativeCenterZ * cosine;
          final offsetX = -signedDistance * targetNormalX;
          final offsetZ = -signedDistance * targetNormalZ;
          final sourceSide =
              (rotatedCenterX + offsetX - targetOriginX) *
                      targetNormalX +
                  (rotatedCenterZ + offsetZ - targetOriginZ) *
                      targetNormalZ;
          final targetSide =
              (targetCenter.x - targetOriginX) * targetNormalX +
                  (targetCenter.z - targetOriginZ) * targetNormalZ;
          if (sourceSide * targetSide >= -0.000001) {
            continue;
          }

          final score =
              signedDistance.abs() + angleRadians * 0.10;
          final candidate = _WallAlignmentCandidate(
            centerX: sourceMidX,
            centerZ: sourceMidZ,
            rotationRadians: rotationRadians,
            offsetX: offsetX,
            offsetZ: offsetZ,
            score: score,
          );
          // A wall that is already aligned must not hide another nearby wall
          // that can add a second or third magnetic contact.
          if (candidate.rotationRadians.abs() <= 0.000001 &&
              candidate.offsetX.abs() <= 0.000001 &&
              candidate.offsetZ.abs() <= 0.000001) {
            continue;
          }
          if (_alignmentCreatesInteriorOverlap(
            candidate: candidate,
            connectedIds: connectedIds,
          )) {
            overlapPrevented = true;
            continue;
          }
          if (bestCandidate == null ||
              score < bestCandidate.score) {
            bestCandidate = candidate;
          }
        }
      }
    }

    final candidate = bestCandidate;
    if (candidate == null ||
        (candidate.rotationRadians.abs() <= 0.000001 &&
            candidate.offsetX.abs() <= 0.000001 &&
            candidate.offsetZ.abs() <= 0.000001)) {
      return overlapPrevented
          ? const WallAlignmentPreviewResult.overlapPrevented()
          : const WallAlignmentPreviewResult.noCandidate();
    }

    final currentRooms = List<RoomModel>.from(_completedRooms);
    final proposedRooms = List<RoomModel>.from(_completedRooms);
    for (var index = 0;
        index < proposedRooms.length;
        index++) {
      final room = proposedRooms[index];
      if (!connectedIds.contains(room.id)) {
        continue;
      }
      final rotated = _rotateRoom(
        room,
        centerX: candidate.centerX,
        centerZ: candidate.centerZ,
        radians: candidate.rotationRadians,
      );
      proposedRooms[index] = _translateRoom(
        rotated,
        offsetX: candidate.offsetX,
        offsetZ: candidate.offsetZ,
      );
    }

    return WallAlignmentPreviewResult.available(
      WallAlignmentPreview._(
        currentRooms: currentRooms,
        proposedRooms: proposedRooms,
        transformedRoomIds: connectedIds,
      ),
    );
  }

  /// Indica si dos ambientes independientes pueden participar en una unión
  /// manual. Los ambientes que ya pertenecen al mismo grupo conectado no se
  /// ofrecen como destino para evitar transformaciones redundantes.
  bool canJoinRoomPair({
    required String sourceRoomId,
    required String targetRoomId,
  }) {
    if (sourceRoomId == targetRoomId ||
        !_completedRooms.any((room) => room.id == sourceRoomId) ||
        !_completedRooms.any((room) => room.id == targetRoomId)) {
      return false;
    }

    return !_connectedRoomIds(sourceRoomId).contains(targetRoomId);
  }

  /// Une de forma explícita el grupo del ambiente origen con una pared del
  /// ambiente destino. Reutiliza las validaciones geométricas de alineación,
  /// incluida la prevención de solapamientos interiores.
  Future<WallAlignmentResult> joinRooms({
    required String sourceRoomId,
    required String targetRoomId,
  }) {
    if (!canJoinRoomPair(
      sourceRoomId: sourceRoomId,
      targetRoomId: targetRoomId,
    )) {
      return Future<WallAlignmentResult>.value(
        WallAlignmentResult.noCandidate,
      );
    }

    return alignRoomToNearestWallDetailed(
      roomId: sourceRoomId,
      targetRoomId: targetRoomId,
    );
  }

  bool _alignmentCreatesInteriorOverlap({
    required _WallAlignmentCandidate candidate,
    required Set<String> connectedIds,
  }) {
    final transformedRooms = <RoomModel>[
      for (final room in _completedRooms)
        if (connectedIds.contains(room.id))
          _translateRoom(
            _rotateRoom(
              room,
              centerX: candidate.centerX,
              centerZ: candidate.centerZ,
              radians: candidate.rotationRadians,
            ),
            offsetX: candidate.offsetX,
            offsetZ: candidate.offsetZ,
          ),
    ];

    for (final transformedRoom in transformedRooms) {
      for (final fixedRoom in _completedRooms) {
        if (connectedIds.contains(fixedRoom.id)) {
          continue;
        }
        if (_polygonsHaveInteriorOverlap(
          transformedRoom.points,
          fixedRoom.points,
        )) {
          return true;
        }
      }
    }
    return false;
  }

  bool _polygonsHaveInteriorOverlap(
    List<ARPoint> first,
    List<ARPoint> second,
  ) {
    if (first.length < 3 || second.length < 3) {
      return false;
    }

    for (var firstIndex = 0;
        firstIndex < first.length;
        firstIndex++) {
      final firstStart = first[firstIndex];
      final firstEnd = first[(firstIndex + 1) % first.length];
      for (var secondIndex = 0;
          secondIndex < second.length;
          secondIndex++) {
        final secondStart = second[secondIndex];
        final secondEnd = second[(secondIndex + 1) % second.length];
        if (_segmentsCrossProperly(
          firstStart,
          firstEnd,
          secondStart,
          secondEnd,
        )) {
          return true;
        }
      }
    }

    if (first.any((point) => _pointStrictlyInsidePolygon(point, second)) ||
        second.any((point) => _pointStrictlyInsidePolygon(point, first))) {
      return true;
    }

    for (var index = 0; index < first.length; index++) {
      final start = first[index];
      final end = first[(index + 1) % first.length];
      final midpoint = ARPoint(
        x: (start.x + end.x) / 2,
        y: (start.y + end.y) / 2,
        z: (start.z + end.z) / 2,
      );
      if (_pointStrictlyInsidePolygon(midpoint, second)) {
        return true;
      }
    }

    for (var index = 0; index < second.length; index++) {
      final start = second[index];
      final end = second[(index + 1) % second.length];
      final midpoint = ARPoint(
        x: (start.x + end.x) / 2,
        y: (start.y + end.y) / 2,
        z: (start.z + end.z) / 2,
      );
      if (_pointStrictlyInsidePolygon(midpoint, first)) {
        return true;
      }
    }

    return _pointStrictlyInsidePolygon(_roomPointsCenter(first), second) ||
        _pointStrictlyInsidePolygon(_roomPointsCenter(second), first);
  }

  bool _segmentsCrossProperly(
    ARPoint firstStart,    ARPoint firstEnd,
    ARPoint secondStart,
    ARPoint secondEnd,
  ) {
    final firstSideStart =
        _crossProduct(firstStart, firstEnd, secondStart);
    final firstSideEnd =
        _crossProduct(firstStart, firstEnd, secondEnd);
    final secondSideStart =
        _crossProduct(secondStart, secondEnd, firstStart);
    final secondSideEnd =
        _crossProduct(secondStart, secondEnd, firstEnd);
    const tolerance = 0.000001;    return firstSideStart * firstSideEnd < -tolerance &&
        secondSideStart * secondSideEnd < -tolerance;
  }

  bool _pointStrictlyInsidePolygon(
    ARPoint point,
    List<ARPoint> polygon,
  ) {
    const boundaryToleranceSquared = 0.000001;
    var inside = false;
    for (var index = 0; index < polygon.length; index++) {
      final start = polygon[index];
      final end = polygon[(index + 1) % polygon.length];
      if (_distanceSquaredToSegment(point, start, end) <=
          boundaryToleranceSquared) {
        return false;
      }
      final crossesRay = (start.z > point.z) != (end.z > point.z);
      if (!crossesRay) {
        continue;
      }
      final crossingX = start.x +
          (point.z - start.z) *
              (end.x - start.x) /
              (end.z - start.z);
      if (crossingX > point.x) {
        inside = !inside;
      }
    }
    return inside;
  }

  double _crossProduct(ARPoint start, ARPoint end, ARPoint point) {
    return (end.x - start.x) * (point.z - start.z) -
        (end.z - start.z) * (point.x - start.x);
  }

  double _distanceSquaredToSegment(
    ARPoint point,    ARPoint start,
    ARPoint end,
  ) {
    final dx = end.x - start.x;
    final dz = end.z - start.z;
    final lengthSquared = dx * dx + dz * dz;
    if (lengthSquared <= 0.000001) {
      final pointDx = point.x - start.x;
      final pointDz = point.z - start.z;
      return pointDx * pointDx + pointDz * pointDz;
    }
    final projection = (((point.x - start.x) * dx +
                (point.z - start.z) * dz) /
            lengthSquared)
        .clamp(0.0, 1.0)
        .toDouble();
    final projectedX = start.x + dx * projection;
    final projectedZ = start.z + dz * projection;
    final distanceX = point.x - projectedX;
    final distanceZ = point.z - projectedZ;
    return distanceX * distanceX + distanceZ * distanceZ;
  }

  ARPoint _roomPointsCenter(List<ARPoint> points) {
    final totalX = points.fold<double>(
      0.0,
      (sum, point) => sum + point.x,
    );
    final totalZ = points.fold<double>(
      0.0,
      (sum, point) => sum + point.z,
    );
    return ARPoint(
      x: totalX / points.length,
      y: 0.0,
      z: totalZ / points.length,
    );
  }

  ARPoint _roomCenter(RoomModel room) {
    final totalX = room.points.fold<double>(
      0.0,
      (sum, point) => sum + point.x,
    );
    final totalZ = room.points.fold<double>(
      0.0,
      (sum, point) => sum + point.z,
    );
    return ARPoint(
      x: totalX / room.points.length,
      y: 0.0,
      z: totalZ / room.points.length,
    );
  }

  Future<bool> undoTransform() async {
    if (!canUndoTransform) {
      _clearTransformHistory();
      return false;
    }

    final uuid = _projectUuid;
    final entry = _transformUndoHistory.last;
    final before = List<RoomModel>.from(_completedRooms);
    _completedRooms
      ..clear()
      ..addAll(entry.before);
    notifyListeners();
    if (!await _persistRoomChange(before)) return false;
    if (_projectUuid == uuid && _sameRoomSnapshot(entry.before, _completedRooms) &&
        _transformUndoHistory.isNotEmpty && identical(_transformUndoHistory.last, entry)) {
      _transformUndoHistory.removeLast();
      _transformRedoHistory.add(entry);
      notifyListeners();
    }
    return true;
  }

  Future<bool> redoTransform() async {
    if (!canRedoTransform) {
      _clearTransformHistory();
      return false;
    }

    final uuid = _projectUuid;
    final entry = _transformRedoHistory.last;
    final before = List<RoomModel>.from(_completedRooms);
    _completedRooms
      ..clear()
      ..addAll(entry.after);
    notifyListeners();
    if (!await _persistRoomChange(before)) return false;
    if (_projectUuid == uuid && _sameRoomSnapshot(entry.after, _completedRooms) &&
        _transformRedoHistory.isNotEmpty && identical(_transformRedoHistory.last, entry)) {
      _transformRedoHistory.removeLast();
      _transformUndoHistory.add(entry);
      notifyListeners();
    }
    return true;
  }

  void _recordTransform(List<RoomModel> before) {
    if (_sameRoomSnapshot(before, _completedRooms)) return;
    _transformUndoHistory.add(
      _TransformHistoryEntry(
        before: before,
        after: List<RoomModel>.from(_completedRooms),
      ),
    );
    if (_transformUndoHistory.length >
        _maximumTransformHistoryEntries) {
      _transformUndoHistory.removeAt(0);
    }
    _transformRedoHistory.clear();
  }

  void _clearTransformHistory() {
    _transformUndoHistory.clear();
    _transformRedoHistory.clear();
  }

  bool _sameRoomSnapshot(
    List<RoomModel> first,
    List<RoomModel> second,
  ) {
    if (first.length != second.length) {
      return false;
    }

    for (var index = 0; index < first.length; index++) {
      if (!identical(first[index], second[index])) {
        return false;
      }    }
    return true;
  }

  RoomModel _rotateRoom(
    RoomModel room, {
    required double centerX,
    required double centerZ,
    required double radians,
  }) {
    final cosine = math.cos(radians);
    final sine = math.sin(radians);

    ARPoint rotatePoint(ARPoint point) {
      final relativeX = point.x - centerX;
      final relativeZ = point.z - centerZ;

      return ARPoint(
        x: centerX + relativeX * cosine - relativeZ * sine,
        y: point.y,
        z: centerZ + relativeX * sine + relativeZ * cosine,
      );
    }

    return room.copyWith(
      points: room.points.map(rotatePoint).toList(),
      features: room.features
          .map(
            (feature) => feature.copyWith(
              start: rotatePoint(feature.start),
              end: rotatePoint(feature.end),
            ),
          )
          .toList(),
    );
  }

  RoomModel _translateRoomPreservingConnectedOpenings(
    RoomModel room, {
    required double offsetX,
    required double offsetZ,
  }) {
    ARPoint translate(ARPoint point) => ARPoint(
          x: point.x + offsetX,
          y: point.y,
          z: point.z + offsetZ,
        );
    return room.copyWith(
      points: room.points.map(translate).toList(),
      features: room.features
          .map(
            (feature) => feature.isConnected
                ? feature
                : feature.copyWith(
                    start: translate(feature.start),
                    end: translate(feature.end),
                  ),
          )
          .toList(),
    );
  }

  RoomModel _rotateRoomPreservingConnectedOpenings(
    RoomModel room, {
    required double centerX,
    required double centerZ,
    required double radians,
  }) {
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    ARPoint rotate(ARPoint point) {
      final x = point.x - centerX;
      final z = point.z - centerZ;
      return ARPoint(
        x: centerX + x * cosine - z * sine,
        y: point.y,
        z: centerZ + x * sine + z * cosine,
      );
    }

    return room.copyWith(
      points: room.points.map(rotate).toList(),
      features: room.features
          .map(
            (feature) => feature.isConnected
                ? feature
                : feature.copyWith(
                    start: rotate(feature.start),
                    end: rotate(feature.end),
                  ),
          )
          .toList(),
    );
  }

  bool _snapRoomToConnectedOpening(
    String roomId, {
    required double maximumDistance,
  }) {
    final roomIndex = _completedRooms.indexWhere((room) => room.id == roomId);
    if (roomIndex == -1) return false;
    final room = _completedRooms[roomIndex];
    final opening = room.features.where((feature) => feature.isConnected).firstOrNull;
    if (opening == null || room.points.length < 2) return false;
    final openingDx = opening.end.x - opening.start.x;
    final openingDz = opening.end.z - opening.start.z;
    if (openingDx * openingDx + openingDz * openingDz < 0.000001) return false;
    final openingMidX = (opening.start.x + opening.end.x) / 2;
    final openingMidZ = (opening.start.z + opening.end.z) / 2;
    final openingAngle = math.atan2(openingDz, openingDx);
    RoomModel? best;
    var nearestDistance = maximumDistance;
    final count = room.isClosed ? room.points.length : room.points.length - 1;
    for (var index = 0; index < count; index++) {
      final wall = _WallProjection.create(
        room.points[index], room.points[(index + 1) % room.points.length],
      );
      if (wall == null) continue;
      var rotation = openingAngle - math.atan2(wall.dz, wall.dx);
      while (rotation > math.pi / 2) { rotation -= math.pi; }
      while (rotation < -math.pi / 2) { rotation += math.pi; }
      // Snapping is a small correction, never an unexpected quarter turn.
      if (rotation.abs() > 15 * math.pi / 180) continue;
      final t = ((openingMidX - wall.start.x) * wall.dx +
          (openingMidZ - wall.start.z) * wall.dz) / wall.lengthSquared;
      if (t < 0 || t > 1) continue;
      final anchor = wall.pointAt(t);
      final dx = openingMidX - anchor.x;
      final dz = openingMidZ - anchor.z;
      final distance = math.sqrt(dx * dx + dz * dz);
      if (distance > nearestDistance) continue;
      // Rotate about the projected opening, not the wall midpoint.
      // This translation is perpendicular to the wall, preserving the
      // user-selected position along it and off-centre door placement.
      var candidate = _rotateRoomPreservingConnectedOpenings(
        room, centerX: anchor.x, centerZ: anchor.z, radians: rotation,
      );
      candidate = _translateRoomPreservingConnectedOpenings(
        candidate, offsetX: dx, offsetZ: dz,
      );
      final alignedWall = _WallProjection.create(candidate.points[index],
          candidate.points[(index + 1) % candidate.points.length]);
      if (alignedWall == null || !alignedWall.contains(opening.start) ||
          !alignedWall.contains(opening.end)) {
        continue;
      }
      // Do not fix one connection by dislodging another.
      final allAnchorsFit = candidate.features.where((f) => f.isConnected).every((f) {
        for (var j = 0; j < count; j++) {
          final segment = _WallProjection.create(candidate.points[j],
              candidate.points[(j + 1) % candidate.points.length]);
          if (segment != null && segment.contains(f.start) && segment.contains(f.end)) {
            return true;
          }
        }
        return false;
      });
      if (!allAnchorsFit) continue;
      best = candidate;
      nearestDistance = distance;
    }
    if (best == null) return false;
    _completedRooms[roomIndex] = best;
    return true;
  }

  Set<String> _connectedRoomIds(String initialRoomId) {
    if (!_completedRooms.any((room) => room.id == initialRoomId)) {
      return <String>{};
    }

    final knownRoomIds = _completedRooms.map((room) => room.id).toSet();
    final connectedIds = <String>{initialRoomId};
    final pending = <String>[initialRoomId];

    while (pending.isNotEmpty) {
      final currentId = pending.removeLast();
      final room = _completedRooms.firstWhere(
        (candidate) => candidate.id == currentId,
      );

      for (final feature in room.features) {        final connectedRoomId = feature.connectedRoomId;

        if (connectedRoomId == null ||
            !knownRoomIds.contains(connectedRoomId) ||
            !connectedIds.add(connectedRoomId)) {
          continue;
        }

        pending.add(connectedRoomId);
      }
    }

    return connectedIds;
  }

  // ===========================================================================
  // PUERTAS Y VENTANAS
  // ===========================================================================

  /// Busca una puerta o ventana persistida dentro de un ambiente.
  ///
  /// La búsqueda utiliza los identificadores estables del proyecto y no
  /// depende de coordenadas de pantalla ni de una sesión AR determinada.
  WallFeature? findFeature({    required String roomId,
    required String featureId,
  }) {
    final roomIndex =
        _completedRooms.indexWhere(
      (room) => room.id == roomId,
    );

    if (roomIndex == -1) {
      return null;
    }

    final room =
        _completedRooms[roomIndex];

    for (final feature in room.features) {
      if (feature.id == featureId) {
        return feature;
      }
    }

    return null;
  }

  /// Actualiza la representación de una puerta en todos los ambientes que
  /// comparten su identificador y la persiste como una única abertura.
  Future<bool> updateDoorOrientation({
    required String featureId,
    DoorHingeSide? hingeSide,
    DoorSwingSide? swingSide,
    DoorOpeningDirection? openingDirection,
  }) async {    var changed = false;
    final before = List<RoomModel>.from(_completedRooms);

    for (var roomIndex = 0;
        roomIndex < _completedRooms.length;
        roomIndex++) {
      final room = _completedRooms[roomIndex];
      final featureIndex = room.features.indexWhere(
        (feature) =>
            feature.id == featureId &&
            feature.type == FeatureType.door,
      );

      if (featureIndex == -1) {
        continue;
      }

      final features = List<WallFeature>.from(room.features);
      final feature = features[featureIndex];
      features[featureIndex] = feature.copyWith(
        doorHingeSide: hingeSide,
        doorSwingSide: swingSide,
        doorOpeningDirection: openingDirection,
      );
      _completedRooms[roomIndex] = room.copyWith(
        features: features,
      );
      changed = true;
    }

    if (!changed) {
      return false;
    }

    _recordTransform(before);
    notifyListeners();
    await _persist();
    return true;
  }

  OpeningPlacement? getOpeningPlacement({
    required String roomId,
    required String featureId,
  }) {
    final roomIndex = _completedRooms.indexWhere(
      (room) => room.id == roomId,
    );
    if (roomIndex == -1) return null;

    final room = _completedRooms[roomIndex];
    final feature = findFeature(
      roomId: roomId,
      featureId: featureId,
    );
    if (feature == null) return null;

    final wall = _nearestWallProjection(room, feature);
    if (wall == null) return null;

    final first = wall.projection(feature.start);
    final second = wall.projection(feature.end);
    return OpeningPlacement(
      widthMeters: GeometryService.calculateDistance(
        feature.start,
        feature.end,
      ),
      distanceFromWallStartMeters:
          math.min(first, second) * wall.length,
      wallLengthMeters: wall.length,
      openingHeightMeters: feature.openingHeightMeters,
      sillHeightMeters: feature.sillHeightMeters,
    );
  }

  /// Edita el ancho y la posición sin sacar la abertura de su pared.
  /// También actualiza cualquier copia compartida que conserve el mismo ID.
  Future<OpeningGeometryUpdateResult> updateOpeningGeometry({
    required String roomId,
    required String featureId,
    required double widthMeters,
    required double distanceFromWallStartMeters,
    double? openingHeightMeters,
    double? sillHeightMeters,
  }) async {
    if (!widthMeters.isFinite || widthMeters < 0.20) {
      return const OpeningGeometryUpdateResult.invalid(
        'El ancho debe ser de al menos 0,20 metros.',
      );
    }
    if (!distanceFromWallStartMeters.isFinite ||
        distanceFromWallStartMeters < 0) {
      return const OpeningGeometryUpdateResult.invalid(
        'La distancia desde la esquina no puede ser negativa.',
      );
    }
    if (openingHeightMeters != null &&
        (!openingHeightMeters.isFinite ||
            openingHeightMeters < 0.20)) {
      return const OpeningGeometryUpdateResult.invalid(
        'La altura debe ser de al menos 0,20 metros.',
      );
    }
    if (sillHeightMeters != null &&
        (!sillHeightMeters.isFinite || sillHeightMeters < 0)) {
      return const OpeningGeometryUpdateResult.invalid(
        'La altura desde el piso no puede ser negativa.',
      );
    }

    final roomIndex = _completedRooms.indexWhere(
      (room) => room.id == roomId,
    );
    if (roomIndex == -1) {
      return const OpeningGeometryUpdateResult.invalid(
        'El ambiente seleccionado ya no está disponible.',
      );
    }

    final room = _completedRooms[roomIndex];
    final featureIndex = room.features.indexWhere(
      (feature) => feature.id == featureId,
    );
    if (featureIndex == -1) {
      return const OpeningGeometryUpdateResult.invalid(
        'La abertura seleccionada ya no está disponible.',
      );
    }

    final feature = room.features[featureIndex];
    final wall = _nearestWallProjection(room, feature);
    if (wall == null) {
      return const OpeningGeometryUpdateResult.invalid(
        'No se pudo identificar la pared de la abertura.',
      );
    }

    final openingEndDistance =
        distanceFromWallStartMeters + widthMeters;
    if (openingEndDistance > wall.length + 0.000001) {
      return OpeningGeometryUpdateResult.invalid(
        'La abertura termina fuera de la pared de '
        '${_formatLength(wall.length)}.',
      );
    }

    final startT = distanceFromWallStartMeters / wall.length;
    final endT = openingEndDistance / wall.length;
    for (final existing in room.features) {
      if (existing.id == featureId ||
          !wall.contains(existing.start) ||
          !wall.contains(existing.end)) {
        continue;
      }

      final existingStart = math.min(
            wall.projection(existing.start),
            wall.projection(existing.end),
          ) *
          wall.length;
      final existingEnd = math.max(
            wall.projection(existing.start),
            wall.projection(existing.end),
          ) *
          wall.length;
      const minimumSeparation = 0.02;
      final overlaps = distanceFromWallStartMeters <
              existingEnd - minimumSeparation &&
          existingStart < openingEndDistance - minimumSeparation;
      if (overlaps) {
        return const OpeningGeometryUpdateResult.invalid(
          'La abertura se superpone con otra puerta o ventana.',
        );
      }
    }

    final preservesDirection = wall.projection(feature.start) <=
        wall.projection(feature.end);
    final lowerPoint = wall.pointAt(startT);
    final upperPoint = wall.pointAt(endT);
    final updatedStart = preservesDirection ? lowerPoint : upperPoint;
    final updatedEnd = preservesDirection ? upperPoint : lowerPoint;
    var changed = false;

    final before = List<RoomModel>.from(_completedRooms);

    for (var index = 0;
        index < _completedRooms.length;
        index++) {
      final candidateRoom = _completedRooms[index];
      final candidateFeatureIndex = candidateRoom.features.indexWhere(
        (candidate) => candidate.id == featureId,
      );
      if (candidateFeatureIndex == -1) continue;

      final features = List<WallFeature>.from(candidateRoom.features);
      features[candidateFeatureIndex] =
          features[candidateFeatureIndex].copyWith(
        start: updatedStart,
        end: updatedEnd,
        openingHeightMeters: openingHeightMeters,
        sillHeightMeters: sillHeightMeters,
      );
      _completedRooms[index] = candidateRoom.copyWith(
        features: features,
      );
      changed = true;
    }

    if (!changed) {
      return const OpeningGeometryUpdateResult.invalid(
        'No se pudo actualizar la abertura.',
      );
    }

    _recordTransform(before);
    notifyListeners();
    await _persist();
    return const OpeningGeometryUpdateResult.success();
  }

  _WallProjection? _nearestWallProjection(
    RoomModel room,
    WallFeature feature,
  ) {
    final points = room.points;
    if (points.length < 2) return null;

    final midpoint = ARPoint(
      x: (feature.start.x + feature.end.x) / 2,
      y: (feature.start.y + feature.end.y) / 2,
      z: (feature.start.z + feature.end.z) / 2,
    );
    _WallProjection? nearest;
    var nearestDistanceSquared = double.infinity;

    for (var index = 0; index < PlanEditGeometry.wallCount(room); index++) {
      final candidate = _WallProjection.create(
        points[index],
        points[(index + 1) % points.length],
      );
      if (candidate == null) continue;

      final projected = candidate.pointAt(
        candidate.projection(midpoint),
      );
      final dx = midpoint.x - projected.x;
      final dz = midpoint.z - projected.z;
      final distanceSquared = dx * dx + dz * dz;
      if (distanceSquared < nearestDistanceSquared) {
        nearestDistanceSquared = distanceSquared;
        nearest = candidate;
      }
    }
    return nearest;
  }

  /// Construye la referencia común que utilizarán el plano 2D, Basic Scanner,
  /// ARCore y ARKit para continuar el relevamiento desde una abertura.
  ///
  /// Devuelve `null` si el ambiente o la abertura ya no existen. Esto evita
  /// iniciar un escaneo con una selección desactualizada.
  ScanContinuationReference? createContinuationReference({
    required String roomId,
    required String featureId,
    required OpeningConnectionSide side,
    required ContinuationStartEndpoint startEndpoint,
  }) {
    final feature = findFeature(
      roomId: roomId,
      featureId: featureId,
    );

    if (feature == null) {
      return null;
    }
    return ScanContinuationReference.fromFeature(
      sourceRoomId: roomId,
      feature: feature,
      side: side,
      startEndpoint: startEndpoint,
    );
  }
  /// Creates or relocates an opening on an explicitly selected wall.
  /// Validation finishes before any room is changed, including shared copies.
  Future<OpeningGeometryUpdateResult> placeOpeningOnWall({
    required String roomId,
    required FeatureType type,
    required int wallIndex,
    required ARPoint location,
    required double widthMeters,
    required double openingHeightMeters,
    required double sillHeightMeters,
    String? featureId,
  }) async {
    const invalid = OpeningGeometryUpdateResult.invalid(
      'Elegí una pared y medidas válidas para la abertura.',
    );
    final index = _completedRooms.indexWhere((r) => r.id == roomId);
    if (index < 0 || !widthMeters.isFinite || widthMeters < 0.20 ||
        !openingHeightMeters.isFinite || openingHeightMeters <= 0 ||
        !sillHeightMeters.isFinite || sillHeightMeters < 0 ||
        !location.x.isFinite || !location.z.isFinite) {
      return invalid;
    }
    final room = _completedRooms[index];
    final count = PlanEditGeometry.wallCount(room);
    if (wallIndex < 0 || wallIndex >= count) return invalid;
    final wall = _WallProjection.create(room.points[wallIndex],
        room.points[(wallIndex + 1) % room.points.length]);
    if (wall == null || widthMeters > wall.length) return invalid;
    final original = room.features.where((f) => f.id == featureId).firstOrNull;
    if (featureId != null && original == null) return invalid;
    final startDistance = (wall.projection(location) * wall.length - widthMeters / 2)
        .clamp(0.0, wall.length - widthMeters).toDouble();
    final lower = wall.pointAt(startDistance / wall.length);
    final upper = wall.pointAt((startDistance + widthMeters) / wall.length);
    final reversed = original != null &&
        (original.end.x - original.start.x) * wall.dx +
            (original.end.z - original.start.z) * wall.dz < 0;
    final start = reversed ? upper : lower;
    final end = reversed ? lower : upper;
    final affected = <int>[index];
    if (original != null) {
      for (var i = 0; i < _completedRooms.length; i++) {
        if (i != index && _completedRooms[i].features.any((f) => f.id == original.id)) {
          affected.add(i);
        }
      }
    }
    for (final i in affected) {
      final target = _completedRooms[i];
      _WallProjection? targetWall;
      for (var j = 0; j < target.points.length; j++) {
        final candidate = _WallProjection.create(target.points[j],
            target.points[(j + 1) % target.points.length]);
        if (candidate != null && candidate.contains(start) && candidate.contains(end)) {
          targetWall = candidate;
          break;
        }
      }
      if (targetWall == null) {
        return const OpeningGeometryUpdateResult.invalid(
          'La abertura conectada debe permanecer sobre una pared de ambos ambientes.',
        );
      }
      final lo = math.min(targetWall.projection(start), targetWall.projection(end)) * targetWall.length;
      final hi = math.max(targetWall.projection(start), targetWall.projection(end)) * targetWall.length;
      for (final existing in target.features) {
        if (existing.id == featureId || !targetWall.contains(existing.start) ||
            !targetWall.contains(existing.end)) {
          continue;
        }
        final a = math.min(targetWall.projection(existing.start),
            targetWall.projection(existing.end)) * targetWall.length;
        final b = math.max(targetWall.projection(existing.start),
            targetWall.projection(existing.end)) * targetWall.length;
        if (lo < b - 0.000001 && a < hi - 0.000001) {
          return const OpeningGeometryUpdateResult.invalid(
            'La abertura se superpone con otra puerta o ventana.',
          );
        }
      }
    }
    final before = List<RoomModel>.from(_completedRooms);
    final created = original == null ? WallFeature(
      id: _nextUniqueId(), type: type, start: start, end: end,
      openingHeightMeters: openingHeightMeters, sillHeightMeters: sillHeightMeters,
    ) : null;
    for (final i in affected) {
      final target = _completedRooms[i];
      final features = List<WallFeature>.from(target.features);
      if (created != null) {
        features.add(created);
      } else {
        final at = features.indexWhere((f) => f.id == featureId);
        features[at] = features[at].copyWith(
          start: start, end: end, openingHeightMeters: openingHeightMeters,
          sillHeightMeters: sillHeightMeters,
        );
      }
      _completedRooms[i] = target.copyWith(features: features);
    }
    _recordTransform(before);
    notifyListeners();
    await _persist();
    return const OpeningGeometryUpdateResult.success();
  }

  Future<void> addFeatureToRoom(
    String roomId, FeatureType type, ARPoint startLocation, [ARPoint? endLocation]
  ) async {
    final room = _completedRooms.where((r) => r.id == roomId).firstOrNull;
    if (room == null) return;
    final end = endLocation ?? ARPoint(
      x: startLocation.x + 0.8, y: startLocation.y, z: startLocation.z,
    );
    final probe = WallFeature(id: '', type: type, start: startLocation, end: end);
    final wall = _nearestWallProjection(room, probe);
    if (wall == null) return;
    await placeOpeningOnWall(
      roomId: roomId, type: type, wallIndex: room.points.indexOf(wall.start),
      location: ARPoint(x: (startLocation.x + end.x) / 2,
          y: startLocation.y, z: (startLocation.z + end.z) / 2),
      widthMeters: GeometryService.calculateDistance(startLocation, end),
      openingHeightMeters: probe.openingHeightMeters,
      sillHeightMeters: probe.sillHeightMeters,
    );
  }

  // ===========================================================================
  // MÉTRICAS
  // ===========================================================================

  double wallLength(
    RoomModel room,
    int wallIndex,
  ) {
    final points =        room.points;

    if (points.length < 2 ||
        wallIndex < 0 ||
        wallIndex >=
            points.length) {
      return 0.0;
    }

    final start =
        points[wallIndex];

    final end =
        points[
          (wallIndex + 1) %
              points.length
        ];

    return GeometryService
        .calculateDistance(
      start,
      end,
    );
  }

  double get totalProjectArea {
    double total = 0.0;

    for (final room
        in _completedRooms) {
      if (!room.isClosed) continue;
      total +=
          GeometryService
              .calculateArea(
        room.points,
      );
    }

    return total;  }

  List<Map<String, dynamic>>
      get roomSummaries {
    return _completedRooms
        .map(
          (room) => {
            'id': room.id,
            'name': room.name,
            'type':
                room.type.name,
            'area': PlanEditGeometry.area(room).toStringAsFixed(2),
            'perimeter': PlanEditGeometry.perimeter(room).toStringAsFixed(2),
            'pointsCount':
                room.points.length,
          },
        )
        .toList();
  }  // ===========================================================================
  // REAJUSTE DE ABERTURAS
  // ===========================================================================


  String _formatLength(double meters) => MeasurementUnits.formatLength(
    meters, measurementSystem, metersLabel: 'metros', feetLabel: 'pies',
    inchesLabel: 'pulgadas', decimalSeparator: ',',
  );

  Future<ValidationResult> updateWallLength({
    required String roomId, int? roomIndex, required int wallIndex,
    required double lengthMeters,
  }) async {
    final room = _completedRooms.where((r) => r.id == roomId).firstOrNull;
    if (room == null) return ValidationResult.invalid('No se encontró el ambiente.');
    final points = PlanEditGeometry.resizeWall(room, wallIndex, lengthMeters);
    if (points == null) return ValidationResult.invalid('La medida no es válida.');
    final proposal = previewGeometry(room, points);
    if (proposal.error != null) {
      return ValidationResult.invalid(
        'El cambio genera un cruce, solapamiento o modifica una conexión. Revisá el plano.');
    }
    await applyPlanEdit(proposal);
    return ValidationResult.valid;
  }

  // ===========================================================================
  // RESET
  // ===========================================================================

  void clearProject() {
    _projectUuid = null;
    _completedRooms.clear();
    _clearTransformHistory();
    _projectName =
        'Mi Casa Completa';

    notifyListeners();
  }
}

enum PlanEditError { invalid, connection, overlap, noClosure, stale }

class PlanEditProposal {
  final List<RoomModel> before;
  final List<RoomModel> after;
  final List<ARPoint> returnPath;
  final PlanEditError? error;
  PlanEditProposal(List<RoomModel> before, List<RoomModel> after,
      {List<ARPoint> returnPath = const []})
      : before = List.unmodifiable(before), after = List.unmodifiable(after),
        returnPath = List.unmodifiable(returnPath), error = null;
  const PlanEditProposal.failed(this.error)
      : before = const [], after = const [], returnPath = const [];
}

class _TransformHistoryEntry {
  final List<RoomModel> before;
  final List<RoomModel> after;

  const _TransformHistoryEntry({
    required this.before,
    required this.after,
  });
}

class _WallAlignmentCandidate {
  final double centerX;
  final double centerZ;
  final double rotationRadians;
  final double offsetX;
  final double offsetZ;
  final double score;

  const _WallAlignmentCandidate({
    required this.centerX,
    required this.centerZ,
    required this.rotationRadians,
    required this.offsetX,
    required this.offsetZ,
    required this.score,  });
}

class _RoomNormalizationResult {
  final List<RoomModel> rooms;

  final bool changed;

  const _RoomNormalizationResult({
    required this.rooms,
    required this.changed,
  });
}

class OpeningPlacement {
  final double widthMeters;
  final double distanceFromWallStartMeters;
  final double wallLengthMeters;
  final double openingHeightMeters;
  final double sillHeightMeters;

  const OpeningPlacement({
    required this.widthMeters,
    required this.distanceFromWallStartMeters,    required this.wallLengthMeters,
    required this.openingHeightMeters,    required this.sillHeightMeters,
  });
}

class OpeningGeometryUpdateResult {
  final bool isSuccess;
  final String? errorMessage;

  const OpeningGeometryUpdateResult.success()
      : isSuccess = true,
        errorMessage = null;

  const OpeningGeometryUpdateResult.invalid(this.errorMessage)
      : isSuccess = false;}

class _WallProjection {
  final ARPoint start;
  final ARPoint end;
  final double dx;
  final double dz;
  final double lengthSquared;
  final double length;

  const _WallProjection._({
    required this.start,
    required this.end,
    required this.dx,
    required this.dz,
    required this.lengthSquared,
    required this.length,  });

  static _WallProjection? create(ARPoint start, ARPoint end) {
    final dx = end.x - start.x;
    final dz = end.z - start.z;
    final lengthSquared = dx * dx + dz * dz;
    if (lengthSquared <= 0.000001) return null;

    return _WallProjection._(
      start: start,
      end: end,
      dx: dx,
      dz: dz,
      lengthSquared: lengthSquared,
      length: math.sqrt(lengthSquared),
    );
  }

  double projection(ARPoint point) {
    return (((point.x - start.x) * dx +
                (point.z - start.z) * dz) /
            lengthSquared)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  ARPoint pointAt(double t) {
    return ARPoint(
      x: start.x + dx * t,
      y: start.y + (end.y - start.y) * t,
      z: start.z + dz * t,
    );
  }

  bool contains(ARPoint point) {
    final rawProjection =
        ((point.x - start.x) * dx +
                (point.z - start.z) * dz) /
            lengthSquared;
    if (rawProjection < -0.01 || rawProjection > 1.01) {
      return false;
    }

    final projected = pointAt(rawProjection);
    final distanceX = point.x - projected.x;
    final distanceZ = point.z - projected.z;
    return distanceX * distanceX + distanceZ * distanceZ <=
        0.0025;
  }
}
