import 'dart:math' as math;

import '../models/room_model.dart';
import 'dimension_layout.dart';

/// Converts persisted room geometry into dimension segments without mutating it.
/// The caller supplies the target coordinate transform, allowing the same
/// layout rules to be reused by CustomPainter and file exporters.
class TechnicalDimensionLayout {
  const TechnicalDimensionLayout._();

  static List<DimensionSegment> forRoom({
    required RoomModel room,
    required double Function(ARPoint point) x,
    required double Function(ARPoint point) y,
    bool includeTotals = true,
    Set<int> hiddenWallIndexes = const <int>{},
  }) {
    final points = room.points;
    if (points.length < 2) return const <DimensionSegment>[];

    final center = _center(points, x, y);
    final segments = <DimensionSegment>[];
    final wallCount = room.isClosed ? points.length : points.length - 1;

    for (var index = 0; index < wallCount; index++) {
      if (hiddenWallIndexes.contains(index)) continue;
      final start = points[index];
      final end = points[(index + 1) % points.length];

      // A wall segment that contains a door opening is not dimensioned as a
      // separate wall fragment. The opening dimension remains the precise
      // reference, avoiding stacked/fragmented dimensions around doors.
      final hasDoorOpening = room.features.any(
        (feature) =>
            feature.type == FeatureType.door &&
            _segmentContainsFeature(start, end, feature.start, feature.end),
      );
      if (hasDoorOpening) continue;

      segments.add(
        DimensionSegment(
          x1: x(start),
          y1: y(start),
          x2: x(end),
          y2: y(end),
          kind: DimensionKind.wall,
          id: '${room.id}:wall:$index',
          centerX: center.x,
          centerY: center.y,
        ),
      );
    }

    for (final feature in room.features) {
      segments.add(
        DimensionSegment(
          x1: x(feature.start),
          y1: y(feature.start),
          x2: x(feature.end),
          y2: y(feature.end),
          kind: DimensionKind.opening,
          id: '${room.id}:opening:${feature.id}',
          centerX: center.x,
          centerY: center.y,
          normalDirection: -1.0,
        ),
      );
    }

    if (includeTotals && room.isClosed && points.length >= 3) {
      var minX = double.infinity;
      var maxX = double.negativeInfinity;
      var minY = double.infinity;
      var maxY = double.negativeInfinity;
      for (final point in points) {
        final px = x(point);
        final py = y(point);
        minX = math.min(minX, px);
        maxX = math.max(maxX, px);
        minY = math.min(minY, py);
        maxY = math.max(maxY, py);
      }

      segments.add(
        DimensionSegment(
          x1: minX,
          y1: minY,
          x2: maxX,
          y2: minY,
          kind: DimensionKind.total,
          id: '${room.id}:total:horizontal',
          centerX: center.x,
          centerY: center.y,
        ),
      );
      segments.add(
        DimensionSegment(
          x1: maxX,
          y1: minY,
          x2: maxX,
          y2: maxY,
          kind: DimensionKind.total,
          id: '${room.id}:total:vertical',
          centerX: center.x,
          centerY: center.y,
        ),
      );
    }

    return DimensionLayout.sort(segments);
  }

  static bool _segmentContainsFeature(
    ARPoint wallStart,
    ARPoint wallEnd,
    ARPoint featureStart,
    ARPoint featureEnd,
  ) {
    const epsilon = 0.00005;
    final wallDx = wallEnd.x - wallStart.x;
    final wallDz = wallEnd.z - wallStart.z;
    final wallLengthSquared = wallDx * wallDx + wallDz * wallDz;
    if (wallLengthSquared <= epsilon) return false;

    double cross(ARPoint point) =>
        (point.x - wallStart.x) * wallDz -
        (point.z - wallStart.z) * wallDx;

    if (cross(featureStart).abs() > epsilon ||
        cross(featureEnd).abs() > epsilon) {
      return false;
    }

    double projection(ARPoint point) =>
        ((point.x - wallStart.x) * wallDx +
                (point.z - wallStart.z) * wallDz) /
            wallLengthSquared;

    final startT = projection(featureStart);
    final endT = projection(featureEnd);
    return startT >= -epsilon &&
        startT <= 1 + epsilon &&
        endT >= -epsilon &&
        endT <= 1 + epsilon;
  }

  static _Point _center(
    List<ARPoint> points,
    double Function(ARPoint point) x,
    double Function(ARPoint point) y,
  ) {
    var centerX = 0.0;
    var centerY = 0.0;
    for (final point in points) {
      centerX += x(point);
      centerY += y(point);
    }
    return _Point(centerX / points.length, centerY / points.length);
  }
}

class _Point {
  final double x;
  final double y;

  const _Point(this.x, this.y);
}
