import 'plan_edit_geometry.dart';
import '../models/room_model.dart';

/// A complete, visible return path. Never substitutes an invisible diagonal.
class PlanClosure {
  final RoomModel room;
  final List<ARPoint> returnPath;
  final double distanceToTarget;
  const PlanClosure(this.room, this.returnPath, this.distanceToTarget);

  static PlanClosure? nearest(RoomModel open, List<RoomModel> others) {
    if (open.isClosed || open.points.length < 2) return null;
    final first = open.points.first, last = open.points.last;
    final segments = <({ARPoint a, ARPoint b})>[];
    for (final r in others.where((r) => r.id != open.id && r.isClosed)) {
      for (var i = 0; i < PlanEditGeometry.wallCount(r); i++) {
        segments.add((a: r.points[i], b: r.points[(i + 1) % r.points.length]));
      }
    }
    final targets = <ARPoint>[first];
    for (final s in segments) {
      targets.addAll([
        s.a,
        s.b,
        PlanEditGeometry.interpolate(
          s.a,
          s.b,
          PlanEditGeometry.fraction(last, s.a, s.b).clamp(0.0, 1.0).toDouble(),
        ),
      ]);
    }
    targets.sort(
      (a, b) => PlanEditGeometry.distance(
        last,
        a,
      ).compareTo(PlanEditGeometry.distance(last, b)),
    );
    final seen = <String>{};
    for (final target in targets) {
      final key =
          '${target.x.toStringAsFixed(5)},${target.z.toStringAsFixed(5)}';
      if (!seen.add(key)) continue;
      final route = PlanEditGeometry.distance(first, target) < 1e-5
          ? <ARPoint>[first]
          : _path(target, first, segments);
      if (route == null) continue;
      final combined = List<ARPoint>.from(open.points);
      for (final p in route) {
        if (PlanEditGeometry.distance(combined.last, p) > 1e-5) combined.add(p);
      }
      if (PlanEditGeometry.distance(combined.last, first) < 1e-5) {
        combined.removeLast();
      }
      if (!PlanEditGeometry.validPath(combined, true)) continue;
      final result = open.copyWith(points: combined, isClosed: true);
      if (others.any(
        (r) => r.id != open.id && PlanEditGeometry.overlaps(result, r),
      )) {
        continue;
      }
      // Every reference opening must still have a wall in the closed polygon.
      if (result.features
          .where((f) => f.isConnected)
          .any((f) => PlanEditGeometry.featureWall(result, f) < 0)) {
        continue;
      }
      return PlanClosure(result, [
        last,
        ...route,
      ], PlanEditGeometry.distance(last, target));
    }
    return null;
  }

  static List<ARPoint>? _path(
    ARPoint from,
    ARPoint to,
    List<({ARPoint a, ARPoint b})> segments,
  ) {
    final nodes = <ARPoint>[];
    int node(ARPoint p) {
      final found = nodes.indexWhere(
        (q) => PlanEditGeometry.distance(p, q) < 1e-5,
      );
      if (found >= 0) return found;
      nodes.add(p);
      return nodes.length - 1;
    }

    final start = node(from), end = node(to);
    for (final s in segments) {
      node(s.a);
      node(s.b);
    }
    final edges = List.generate(nodes.length, (_) => <int, double>{});
    for (final s in segments) {
      final ids = <int>[];
      for (var i = 0; i < nodes.length; i++) {
        if (PlanEditGeometry.onSegment(nodes[i], s.a, s.b)) ids.add(i);
      }
      ids.sort(
        (a, b) => PlanEditGeometry.fraction(
          nodes[a],
          s.a,
          s.b,
        ).compareTo(PlanEditGeometry.fraction(nodes[b], s.a, s.b)),
      );
      for (var i = 1; i < ids.length; i++) {
        final a = ids[i - 1],
            b = ids[i],
            distance = PlanEditGeometry.distance(nodes[a], nodes[b]);
        edges[a][b] = distance;
        edges[b][a] = distance;
      }
    }
    final distances = List.filled(nodes.length, double.infinity),
        previous = List.filled(nodes.length, -1);
    final visited = <int>{};
    distances[start] = 0;
    while (visited.length < nodes.length) {
      var current = -1;
      for (var i = 0; i < nodes.length; i++) {
        if (!visited.contains(i) &&
            (current < 0 || distances[i] < distances[current])) {
          current = i;
        }
      }
      if (current < 0 || !distances[current].isFinite) return null;
      if (current == end) break;
      visited.add(current);
      for (final edge in edges[current].entries) {
        final d = distances[current] + edge.value;
        if (d < distances[edge.key]) {
          distances[edge.key] = d;
          previous[edge.key] = current;
        }
      }
    }
    final route = <ARPoint>[];
    for (var i = end; i != -1; i = previous[i]) {
      route.add(nodes[i]);
      if (i == start) break;
    }
    return route.reversed.toList();
  }
}
