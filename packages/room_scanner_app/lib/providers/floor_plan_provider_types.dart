part of 'floor_plan_provider.dart';

// Tipos públicos y privados usados por FloorPlanProvider: resultados de
// operaciones, propuestas de edición y entradas de historial.

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
