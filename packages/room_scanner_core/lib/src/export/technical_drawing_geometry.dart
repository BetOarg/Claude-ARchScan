import 'dart:math' as math;

import '../models/room_model.dart';
import '../utils/geometry_tolerance.dart';

/// Prepara una copia geométrica para salidas técnicas sin modificar la
/// medición original que se conserva en el proyecto y sus metadatos.
class TechnicalDrawingGeometry {
  const TechnicalDrawingGeometry._();

  static RoomModel normalizeRoom(RoomModel room) {
    final snappedPoints = _snapNearRightAngles(room.points, room.isClosed);
    if (snappedPoints.length != room.points.length) return room;

    final wallCount = room.isClosed
        ? room.points.length
        : math.max(0, room.points.length - 1).toInt();
    final features = room.features.map((feature) {
      var bestWall = -1;
      var bestError = double.infinity;
      for (var index = 0; index < wallCount; index++) {
        final a = room.points[index];
        final b = room.points[(index + 1) % room.points.length];
        final error =
            _pointSegmentDistance(feature.start, a, b) +
            _pointSegmentDistance(feature.end, a, b);
        if (error < bestError) {
          bestError = error;
          bestWall = index;
        }
      }
      if (bestWall < 0 || bestError > 0.20) return feature;
      final originalStart = room.points[bestWall];
      final originalEnd = room.points[(bestWall + 1) % room.points.length];
      final snappedStart = snappedPoints[bestWall];
      final snappedEnd = snappedPoints[(bestWall + 1) % snappedPoints.length];
      return feature.copyWith(
        start: _mapPointAlongSegment(
          feature.start,
          originalStart,
          originalEnd,
          snappedStart,
          snappedEnd,
        ),
        end: _mapPointAlongSegment(
          feature.end,
          originalStart,
          originalEnd,
          snappedStart,
          snappedEnd,
        ),
        // The technical exporters draw in the mirrored 2D coordinate frame
        // used by the generated plan. Keep the persisted project semantics
        // untouched and compensate only in this drawing copy.
        doorSwingSide: feature.doorSwingSide == DoorSwingSide.left
            ? DoorSwingSide.right
            : DoorSwingSide.left,
      );
    }).toList();
    return room.copyWith(points: snappedPoints, features: features);
  }

  static List<ARPoint> _snapNearRightAngles(
    List<ARPoint> points,
    bool isClosed,
  ) {
    if (points.length < 3) return List<ARPoint>.from(points);
    final result = <ARPoint>[points.first, points[1]];
    for (var index = 2; index < points.length; index++) {
      final previousOriginal = points[index - 1];
      final current = points[index];
      final incoming = result[index - 1];
      final before = result[index - 2];
      final firstDx = incoming.x - before.x;
      final firstDz = incoming.z - before.z;
      final rawDx = current.x - previousOriginal.x;
      final rawDz = current.z - previousOriginal.z;
      final firstLength = math.sqrt(firstDx * firstDx + firstDz * firstDz);
      final rawLength = math.sqrt(rawDx * rawDx + rawDz * rawDz);
      if (firstLength < kGeometryEpsilon || rawLength < kGeometryEpsilon) {
        result.add(current);
        continue;
      }
      final cosine =
          ((-firstDx * rawDx) + (-firstDz * rawDz)) / (firstLength * rawLength);
      final angle = math.acos(cosine.clamp(-1.0, 1.0)) * 180 / math.pi;
      if (angle < 88 || angle > 92) {
        result.add(current);
        continue;
      }
      final leftX = -firstDz / firstLength;
      final leftZ = firstDx / firstLength;
      final direction = (leftX * rawDx) + (leftZ * rawDz) >= 0 ? 1.0 : -1.0;
      result.add(
        ARPoint(
          x: incoming.x + leftX * rawLength * direction,
          y: current.y,
          z: incoming.z + leftZ * rawLength * direction,
        ),
      );
    }

    if (isClosed && result.length > 3) {
      final first = result.first;
      final second = result[1];
      final beforeLast = result[result.length - 2];
      final last = result.last;
      final closingAngle = _cornerAngle(beforeLast, last, first);
      final firstAngle = _cornerAngle(last, first, second);
      if (closingAngle >= 88 &&
          closingAngle <= 92 &&
          firstAngle >= 88 &&
          firstAngle <= 92) {
        final intersection = _lineIntersection(
          beforeLast,
          last,
          first,
          ARPoint(
            x: first.x - (second.z - first.z),
            y: last.y,
            z: first.z + (second.x - first.x),
          ),
        );
        if (intersection != null) result[result.length - 1] = intersection;
      }
    }
    return result;
  }

  static double _cornerAngle(ARPoint a, ARPoint vertex, ARPoint b) {
    final ax = a.x - vertex.x;
    final az = a.z - vertex.z;
    final bx = b.x - vertex.x;
    final bz = b.z - vertex.z;
    final denominator =
        math.sqrt(ax * ax + az * az) * math.sqrt(bx * bx + bz * bz);
    if (denominator < kGeometryEpsilon) return 0;
    return math.acos(((ax * bx + az * bz) / denominator).clamp(-1.0, 1.0)) *
        180 /
        math.pi;
  }

  static ARPoint? _lineIntersection(
    ARPoint a,
    ARPoint b,
    ARPoint c,
    ARPoint d,
  ) {
    final abX = b.x - a.x;
    final abZ = b.z - a.z;
    final cdX = d.x - c.x;
    final cdZ = d.z - c.z;
    final denominator = abX * cdZ - abZ * cdX;
    if (denominator.abs() < kGeometryEpsilon) return null;
    final t = ((c.x - a.x) * cdZ - (c.z - a.z) * cdX) / denominator;
    return ARPoint(x: a.x + t * abX, y: b.y, z: a.z + t * abZ);
  }

  static double _pointSegmentDistance(ARPoint p, ARPoint a, ARPoint b) {
    final dx = b.x - a.x;
    final dz = b.z - a.z;
    final lengthSquared = dx * dx + dz * dz;
    if (lengthSquared < kGeometryEpsilon) {
      return math.sqrt((p.x - a.x) * (p.x - a.x) + (p.z - a.z) * (p.z - a.z));
    }
    final t = (((p.x - a.x) * dx + (p.z - a.z) * dz) / lengthSquared).clamp(
      0.0,
      1.0,
    );
    final projectedX = a.x + t * dx;
    final projectedZ = a.z + t * dz;
    return math.sqrt(
      (p.x - projectedX) * (p.x - projectedX) +
          (p.z - projectedZ) * (p.z - projectedZ),
    );
  }

  static ARPoint _mapPointAlongSegment(
    ARPoint point,
    ARPoint originalStart,
    ARPoint originalEnd,
    ARPoint snappedStart,
    ARPoint snappedEnd,
  ) {
    final dx = originalEnd.x - originalStart.x;
    final dz = originalEnd.z - originalStart.z;
    final lengthSquared = dx * dx + dz * dz;
    final t = lengthSquared < kGeometryEpsilon
        ? 0.0
        : (((point.x - originalStart.x) * dx +
                      (point.z - originalStart.z) * dz) /
                  lengthSquared)
              .clamp(0.0, 1.0);
    return ARPoint(
      x: snappedStart.x + (snappedEnd.x - snappedStart.x) * t,
      y: point.y,
      z: snappedStart.z + (snappedEnd.z - snappedStart.z) * t,
    );
  }
}
