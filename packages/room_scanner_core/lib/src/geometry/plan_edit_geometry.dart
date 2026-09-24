import 'dart:math' as math;

import 'geometry_service.dart';
import '../models/room_model.dart';
import '../utils/scan_validator.dart';

/// Editing keeps the historical ordered-point model. No implicit closing edge.
class PlanEditGeometry {
  static double area(RoomModel room) =>
      room.isClosed ? GeometryService.calculateArea(room.points) : 0;
  static double perimeter(RoomModel room) {
    var result = 0.0;
    for (var i = 0; i < wallCount(room); i++) {
      result += distance(
        room.points[i],
        room.points[(i + 1) % room.points.length],
      );
    }
    return result;
  }

  static int wallCount(RoomModel room) =>
      math.max(0, room.isClosed ? room.points.length : room.points.length - 1);
  static double distance(ARPoint a, ARPoint b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.z - b.z, 2));
  static double fraction(ARPoint p, ARPoint a, ARPoint b) {
    final dx = b.x - a.x, dz = b.z - a.z;
    final squared = dx * dx + dz * dz;
    return squared < 1e-12
        ? 0
        : ((p.x - a.x) * dx + (p.z - a.z) * dz) / squared;
  }

  static ARPoint interpolate(ARPoint a, ARPoint b, double t) => ARPoint(
    x: a.x + (b.x - a.x) * t,
    y: a.y + (b.y - a.y) * t,
    z: a.z + (b.z - a.z) * t,
  );
  static bool onSegment(
    ARPoint p,
    ARPoint a,
    ARPoint b, {
    double tolerance = 1e-5,
  }) {
    final t = fraction(p, a, b).clamp(0.0, 1.0).toDouble();
    return distance(p, interpolate(a, b, t)) <= tolerance;
  }

  static int featureWall(RoomModel room, WallFeature feature) {
    for (var i = 0; i < wallCount(room); i++) {
      final a = room.points[i], b = room.points[(i + 1) % room.points.length];
      if (onSegment(feature.start, a, b, tolerance: 0.05) &&
          onSegment(feature.end, a, b, tolerance: 0.05)) {
        return i;
      }
    }
    return -1;
  }

  /// Snaps a dragged corner to the nearest real boundary within touch range.
  static ARPoint snapPoint(
    ARPoint point,
    Iterable<RoomModel> neighbours,
    double radius,
  ) {
    var nearest = point, best = radius;
    for (final room in neighbours) {
      final candidates = <ARPoint>[...room.points];
      for (var i = 0; i < wallCount(room); i++) {
        final a = room.points[i], b = room.points[(i + 1) % room.points.length];
        candidates.add(
          interpolate(a, b, fraction(point, a, b).clamp(0.0, 1.0).toDouble()),
        );
      }
      for (final candidate in candidates) {
        final d = distance(point, candidate);
        if (d <= best) {
          best = d;
          nearest = ARPoint(x: candidate.x, y: point.y, z: candidate.z);
        }
      }
    }
    return nearest;
  }

  /// Translates a selected wall along its normal, keeping it parallel.
  static List<ARPoint> moveWall(
    RoomModel room,
    int index,
    double dx,
    double dz,
  ) {
    final points = List<ARPoint>.from(room.points);
    if (index < 0 || index >= wallCount(room)) return points;
    final next = (index + 1) % points.length;
    final a = points[index], b = points[next];
    final length = distance(a, b);
    if (length < 1e-8) return points;
    final nx = -(b.z - a.z) / length, nz = (b.x - a.x) / length;
    final offset = dx * nx + dz * nz;
    for (final i in [index, next]) {
      final p = points[i];
      points[i] = ARPoint(x: p.x + nx * offset, y: p.y, z: p.z + nz * offset);
    }
    return points;
  }

  static List<ARPoint>? resizeWall(RoomModel room, int index, double meters) {
    if (index < 0 ||
        index >= wallCount(room) ||
        !meters.isFinite ||
        meters < 0.05) {
      return null;
    }
    final result = List<ARPoint>.from(room.points);
    final next = (index + 1) % result.length;
    final length = distance(result[index], result[next]);
    if (length < 1e-8) return null;
    // Keep the start corner anchored, including on the closing wall.
    result[next] = interpolate(result[index], result[next], meters / length);
    return result;
  }

  /// Features move with their original wall, retaining their width and side.
  /// Orphans are preserved so they can still be selected and deleted.
  static RoomModel? reshape(RoomModel room, List<ARPoint> points) {
    if (points.length != room.points.length ||
        !validPath(points, room.isClosed)) {
      return null;
    }
    final features = <WallFeature>[];
    for (final f in room.features) {
      final i = featureWall(room, f);
      if (i < 0) {
        features.add(f);
        continue;
      }
      final j = (i + 1) % points.length;
      final width = distance(f.start, f.end),
          length = distance(points[i], points[j]);
      if (width > length + 1e-6) return null;
      final t1 = fraction(f.start, room.points[i], room.points[j]);
      final t2 = fraction(f.end, room.points[i], room.points[j]);
      final half = width / (2 * length);
      final center = ((t1 + t2) / 2).clamp(half, 1 - half).toDouble();
      final sign = t2 >= t1 ? 1.0 : -1.0;
      final a = interpolate(points[i], points[j], center - sign * half);
      final b = interpolate(points[i], points[j], center + sign * half);
      features.add(
        f.copyWith(
          start: ARPoint(x: a.x, y: f.start.y, z: a.z),
          end: ARPoint(x: b.x, y: f.end.y, z: b.z),
        ),
      );
    }
    final result = room.copyWith(points: points, features: features);
    for (var i = 0; i < features.length; i++) {
      final wall = featureWall(result, features[i]);
      if (wall < 0) continue;
      final a = points[wall], b = points[(wall + 1) % points.length];
      final first = [
        fraction(features[i].start, a, b),
        fraction(features[i].end, a, b),
      ]..sort();
      for (var j = i + 1; j < features.length; j++) {
        if (featureWall(result, features[j]) != wall) continue;
        final second = [
          fraction(features[j].start, a, b),
          fraction(features[j].end, a, b),
        ]..sort();
        if (math.min(first.last, second.last) -
                math.max(first.first, second.first) >
            0.02 / distance(a, b)) {
          return null;
        }
      }
    }
    return result;
  }

  /// An internal cut of an open path creates separate open fragments.
  /// The caller assigns fresh IDs and repairs counterpart connection IDs.
  static List<RoomModel> deleteWall(RoomModel room, int index) {
    if (index < 0 || index >= wallCount(room)) return [];
    final removed = room.features
        .where((f) => featureWall(room, f) == index)
        .map((f) => f.id)
        .toSet();
    final chunks = <List<ARPoint>>[];
    if (room.isClosed) {
      chunks.add([
        ...room.points.skip(index + 1),
        ...room.points.take(index + 1),
      ]);
    } else {
      chunks.addAll([
        room.points.take(index + 1).toList(),
        room.points.skip(index + 1).toList(),
      ]);
      chunks.removeWhere((p) => p.length < 2);
      if (chunks.isEmpty) chunks.add([room.points.first]);
    }
    final fragments = chunks
        .map((p) => room.copyWith(points: p, isClosed: false, features: []))
        .toList();
    for (final f in room.features.where((f) => !removed.contains(f.id))) {
      var target = fragments.indexWhere((r) => featureWall(r, f) >= 0);
      if (target < 0) target = 0;
      fragments[target] = fragments[target].copyWith(
        features: [...fragments[target].features, f],
      );
    }
    return fragments;
  }

  static bool validPath(List<ARPoint> points, bool closed) {
    if (points.any((p) => !p.x.isFinite || !p.y.isFinite || !p.z.isFinite)) {
      return false;
    }
    if (points.length < (closed ? 3 : 1)) return false;
    if (closed && !ScanValidator.validateClosure(points).isValid) return false;
    // Plan editing is precise: scanner's 35 cm capture threshold does not
    // apply to short returns on a shared wall.
    final count = closed ? points.length : points.length - 1;
    for (var i = 0; i < count; i++) {
      final a = points[i], b = points[(i + 1) % points.length];
      if (distance(a, b) < 0.05) return false;
      for (var j = i + 1; j < count; j++) {
        final c = points[j], d = points[(j + 1) % points.length];
        final adjacent = j == i + 1 || (closed && i == 0 && j == count - 1);
        if (adjacent) {
          // Adjacent edges may share only their common endpoint, not retrace.
          final shared = j == i + 1 ? b : a;
          final left = j == i + 1 ? a : b;
          final right = j == i + 1 ? d : c;
          if (onSegment(left, shared, right) ||
              onSegment(right, shared, left)) {
            return false;
          }
        } else if (_crosses(a, b, c, d) ||
            onSegment(a, c, d) ||
            onSegment(b, c, d) ||
            onSegment(c, a, b) ||
            onSegment(d, a, b)) {
          return false;
        }
      }
    }
    return true;
  }

  static bool inside(ARPoint p, List<ARPoint> polygon) {
    var result = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i], b = polygon[j];
      if (onSegment(p, a, b)) return false;
      if ((a.z > p.z) != (b.z > p.z) &&
          p.x < (b.x - a.x) * (p.z - a.z) / (b.z - a.z) + a.x) {
        result = !result;
      }
    }
    return result;
  }

  static double _cross(ARPoint a, ARPoint b, ARPoint p) =>
      (b.x - a.x) * (p.z - a.z) - (b.z - a.z) * (p.x - a.x);
  static bool _crosses(ARPoint a, ARPoint b, ARPoint c, ARPoint d) =>
      _cross(a, b, c) * _cross(a, b, d) < -1e-10 &&
      _cross(c, d, a) * _cross(c, d, b) < -1e-10;

  static bool overlaps(RoomModel room, RoomModel other) {
    if (!other.isClosed || other.points.length < 3) return false;
    for (var i = 0; i < wallCount(room); i++) {
      final a = room.points[i], b = room.points[(i + 1) % room.points.length];
      if (inside(a, other.points) ||
          inside(interpolate(a, b, 0.5), other.points)) {
        return true;
      }
      for (var j = 0; j < wallCount(other); j++) {
        if (_crosses(
          a,
          b,
          other.points[j],
          other.points[(j + 1) % other.points.length],
        )) {
          return true;
        }
      }
    }
    if (room.isClosed) {
      // Also detect coincident boundaries with different subdivisions.
      for (var i = 0; i < wallCount(room); i++) {
        final a = room.points[i], b = room.points[(i + 1) % room.points.length];
        final mid = interpolate(a, b, 0.5), length = distance(a, b);
        if (length < 1e-8) continue;
        for (final sign in [-1.0, 1.0]) {
          final sample = ARPoint(
            x: mid.x - sign * (b.z - a.z) / length * 0.0001,
            y: 0,
            z: mid.z + sign * (b.x - a.x) / length * 0.0001,
          );
          if (inside(sample, room.points) && inside(sample, other.points)) {
            return true;
          }
        }
      }
      for (var j = 0; j < wallCount(other); j++) {
        final a = other.points[j],
            b = other.points[(j + 1) % other.points.length];
        if (inside(a, room.points) ||
            inside(interpolate(a, b, 0.5), room.points)) {
          return true;
        }
      }
      // Identical boundaries have no strictly interior vertices.
      if (room.points.every(
        (p) => other.points.any((q) => distance(p, q) < 1e-5),
      )) {
        return true;
      }
    }
    return false;
  }
}
