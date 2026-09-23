import 'dart:math' as math;

import '../utils/geometry_tolerance.dart';

/// CAD dimension classification.
enum DimensionKind { opening, wall, total }

class DimensionSegment {
  final double x1, y1, x2, y2;
  final DimensionKind kind;
  final String id;
  final double? centerX, centerY;
  final double normalDirection;
  final double labelHalfWidth;

  const DimensionSegment({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.kind,
    required this.id,
    this.centerX,
    this.centerY,
    this.normalDirection = 1.0,
    this.labelHalfWidth = 19.0,
  });

  double get dx => x2 - x1;
  double get dy => y2 - y1;
  double get length => math.sqrt(dx * dx + dy * dy);
}

class DimensionPlacement {
  final DimensionSegment segment;
  final double offset;
  final int level;
  final double normalX;
  final double normalY;
  final double tangentX;
  final double tangentY;

  const DimensionPlacement({
    required this.segment,
    required this.offset,
    required this.level,
    required this.normalX,
    required this.normalY,
    required this.tangentX,
    required this.tangentY,
  });
}

/// Deterministic CAD dimension engine.
/// Openings are closest to the geometry, wall dimensions follow, and totals
/// are pushed outward. Each accepted dimension reserves its complete corridor.
class DimensionLayout {
  static const double defaultBaseOffset = 22.0;
  static const double defaultGap = 12.0;
  static const double defaultTextHeight = 14.0;

  const DimensionLayout._();

  static List<DimensionSegment> deduplicate(Iterable<DimensionSegment> input) {
    final byGeometry = <String, DimensionSegment>{};
    for (final dimension in input) {
      if (!_isFiniteGeometry(dimension) || dimension.length < kGeometryEpsilon) continue;
      final key = _canonicalGeometryKey(dimension);
      final current = byGeometry[key];
      if (current == null || _comparePriority(dimension, current) < 0) {
        byGeometry[key] = dimension;
      }
    }
    return byGeometry.values.toList();
  }

  static List<DimensionSegment> sort(Iterable<DimensionSegment> input) {
    final result = deduplicate(input);
    result.sort((a, b) {
      final kind = _kindOrder(a.kind).compareTo(_kindOrder(b.kind));
      if (kind != 0) return kind;
      final length = a.length.compareTo(b.length);
      if (length != 0) return length;
      return a.id.compareTo(b.id);
    });
    return result;
  }

  static List<DimensionPlacement> layout(
    Iterable<DimensionSegment> input, {
    double baseOffset = defaultBaseOffset,
    double gap = defaultGap,
    double textHeight = defaultTextHeight,
    double? labelHalfWidth,
    int maxLevels = 64,
    bool suppressRedundantOverallSegments = false,
    bool strictHierarchy = false,
  }) {
    var ordered = sort(input);
    if (suppressRedundantOverallSegments) {
      ordered = _removeRedundantOverallSegments(ordered);
    }

    // Dimension strings are laid out independently per facade/normal.
    // This prevents a top string from forcing a right-side string outward and
    // makes the visual hierarchy deterministic: openings, wall segments,
    // then overall dimensions.
    final bySide = <String, List<DimensionSegment>>{};
    for (final dimension in ordered) {
      final side = _sideKey(dimension);
      (bySide[side] ??= <DimensionSegment>[]).add(dimension);
    }

    final spacing = math.max(gap, textHeight + gap).toDouble();
    final result = <DimensionPlacement>[];
    final allWalls = ordered
        .where((dimension) => dimension.kind == DimensionKind.wall)
        .toList(growable: false);

    for (final dimensions in bySide.values) {
      dimensions.sort(_compareLayoutOrder);
      final occupied = <_DimensionCorridor>[];

      for (final dimension in dimensions) {
        final normal = _outwardNormal(dimension);
        final tangent = _tangent(dimension);
        var placed = false;
        final minimumLevel = strictHierarchy ? _minimumLevel(dimension.kind) : 0;

        for (var level = minimumLevel; level < maxLevels; level++) {
          final offset = baseOffset + level * spacing;
          final corridor = _DimensionCorridor.from(
            dimension,
            normal,
            tangent,
            offset,
            labelHalfWidth ?? dimension.labelHalfWidth,
            textHeight,
          );

          if (occupied.any((other) => other.overlaps(corridor))) {
            continue;
          }

          if (_crossesAnotherWall(
            dimension,
            corridor,
            allWalls,
          )) {
            continue;
          }

          occupied.add(corridor);
          result.add(DimensionPlacement(
            segment: dimension,
            offset: offset,
            level: level,
            normalX: normal.x,
            normalY: normal.y,
            tangentX: tangent.x,
            tangentY: tangent.y,
          ));
          placed = true;
          break;
        }

        // A pathological geometry must not make the painter/exporter loop
        // forever. The dimension is omitted rather than producing an invalid
        // placement.
        if (!placed) continue;
      }
    }

    // Preserve the deterministic global dimension order for renderers and
    // tests while keeping collision resolution isolated per facade.
    result.sort((a, b) {
      final length = a.segment.length.compareTo(b.segment.length);
      if (length != 0) return length;
      final kind = _kindOrder(a.segment.kind).compareTo(_kindOrder(b.segment.kind));
      if (kind != 0) return kind;
      return a.segment.id.compareTo(b.segment.id);
    });
    return result;
  }

  static int _minimumLevel(DimensionKind kind) {
    switch (kind) {
      case DimensionKind.opening:
        return 0;
      case DimensionKind.wall:
        return 1;
      case DimensionKind.total:
        return 2;
    }
  }

  static String _sideKey(DimensionSegment dimension) {
    final normal = _outwardNormal(dimension);
    final x = normal.x.abs() < 0.0005 ? 0.0 : normal.x;
    final y = normal.y.abs() < 0.0005 ? 0.0 : normal.y;
    return '${x.toStringAsFixed(3)},${y.toStringAsFixed(3)}';
  }

  static int _compareLayoutOrder(
    DimensionSegment a,
    DimensionSegment b,
  ) {
    final kind = _kindOrder(a.kind).compareTo(_kindOrder(b.kind));
    if (kind != 0) return kind;

    final tangentA = _tangent(a);
    final tangentB = _tangent(b);
    final positionA =
        ((a.x1 + a.x2) / 2.0) * tangentA.x +
        ((a.y1 + a.y2) / 2.0) * tangentA.y;
    final positionB =
        ((b.x1 + b.x2) / 2.0) * tangentB.x +
        ((b.y1 + b.y2) / 2.0) * tangentB.y;
    final position = positionA.compareTo(positionB);
    if (position != 0) return position;

    final length = a.length.compareTo(b.length);
    if (length != 0) return length;
    return a.id.compareTo(b.id);
  }

  static List<DimensionSegment> _removeRedundantOverallSegments(
    List<DimensionSegment> dimensions,
  ) {
    final totals = dimensions
        .where((dimension) => dimension.kind == DimensionKind.total)
        .toList(growable: false);
    if (totals.isEmpty) return dimensions;

    return dimensions.where((dimension) {
      if (dimension.kind != DimensionKind.wall) return true;
      final tangent = _tangent(dimension);
      return !totals.any((total) {
        final totalTangent = _tangent(total);
        final parallel =
            (tangent.x * totalTangent.x + tangent.y * totalTangent.y).abs() >
            0.9999;
        final sameLength = (dimension.length - total.length).abs() < kGeometryEpsilon;
        return parallel && sameLength;
      });
    }).toList(growable: false);
  }

  static bool _crossesAnotherWall(
    DimensionSegment dimension,
    _DimensionCorridor corridor,
    List<DimensionSegment> walls,
  ) {
    for (final wall in walls) {
      if (_sameGeometry(dimension, wall)) continue;
      if (corridor.intersectsSegment(wall.x1, wall.y1, wall.x2, wall.y2)) {
        return true;
      }
    }
    return false;
  }

  static bool _sameGeometry(
    DimensionSegment a,
    DimensionSegment b,
  ) {
    const epsilon = 0.00001;
    bool same(double x1, double y1, double x2, double y2) =>
        (x1 - x2).abs() < epsilon && (y1 - y2).abs() < epsilon;
    return same(a.x1, a.y1, b.x1, b.y1) &&
            same(a.x2, a.y2, b.x2, b.y2) ||
        same(a.x1, a.y1, b.x2, b.y2) &&
            same(a.x2, a.y2, b.x1, b.y1);
  }

  static bool _segmentsIntersect(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy,
    double dx,
    double dy,
  ) {
    const epsilon = 0.000000001;

    final abx = bx - ax;
    final aby = by - ay;
    final acx = cx - ax;
    final acy = cy - ay;
    final adx = dx - ax;
    final ady = dy - ay;
    final cdx = dx - cx;
    final cdy = dy - cy;
    final cax = ax - cx;
    final cay = ay - cy;
    final cbx = bx - cx;
    final cby = by - cy;

    final abAc = abx * acy - aby * acx;
    final abAd = abx * ady - aby * adx;
    final cdCa = cdx * cay - cdy * cax;
    final cdCb = cdx * cby - cdy * cbx;

    bool nearZero(double value) => value.abs() <= epsilon;
    bool onSegment(
      double px,
      double py,
      double sx,
      double sy,
      double ex,
      double ey,
    ) {
      return px >= math.min(sx, ex) - epsilon &&
          px <= math.max(sx, ex) + epsilon &&
          py >= math.min(sy, ey) - epsilon &&
          py <= math.max(sy, ey) + epsilon;
    }

    if (nearZero(abAc) && onSegment(cx, cy, ax, ay, bx, by)) return true;
    if (nearZero(abAd) && onSegment(dx, dy, ax, ay, bx, by)) return true;
    if (nearZero(cdCa) && onSegment(ax, ay, cx, cy, dx, dy)) return true;
    if (nearZero(cdCb) && onSegment(bx, by, cx, cy, dx, dy)) return true;

    return abAc * abAd < -epsilon && cdCa * cdCb < -epsilon;
  }

  static int _comparePriority(DimensionSegment a, DimensionSegment b) {
    final kind = _deduplicationPriority(a.kind).compareTo(
      _deduplicationPriority(b.kind),
    );
    if (kind != 0) return kind;
    return a.id.compareTo(b.id);
  }

  static int _deduplicationPriority(DimensionKind kind) {
    switch (kind) {
      case DimensionKind.opening:
        return 0;
      case DimensionKind.total:
        return 1;
      case DimensionKind.wall:
        return 2;
    }
  }

  static int _kindOrder(DimensionKind kind) {
    switch (kind) {
      case DimensionKind.opening:
        return 0;
      case DimensionKind.wall:
        return 1;
      case DimensionKind.total:
        return 2;
    }
  }

  static String _canonicalGeometryKey(DimensionSegment d) {
    final a = '${d.x1.toStringAsFixed(6)},${d.y1.toStringAsFixed(6)}';
    final b = '${d.x2.toStringAsFixed(6)},${d.y2.toStringAsFixed(6)}';
    final points = [a, b]..sort();

    // Overall dimensions are a distinct semantic measure from wall/opening
    // dimensions. They must remain visible even when their endpoints coincide
    // with the bounding wall; reversed duplicates of the same total still
    // collapse because the kind remains part of the key.
    final kind = d.kind == DimensionKind.total ? 'total:' : '';
    return '$kind${points[0]}|${points[1]}';
  }

  static bool _isFiniteGeometry(DimensionSegment d) {
    return d.x1.isFinite &&
        d.y1.isFinite &&
        d.x2.isFinite &&
        d.y2.isFinite &&
        (d.centerX == null || d.centerX!.isFinite) &&
        (d.centerY == null || d.centerY!.isFinite) &&
        d.normalDirection.isFinite &&
        d.labelHalfWidth.isFinite;
  }

  static _Vector _tangent(DimensionSegment d) {
    final length = math.max(d.length, kGeometryEpsilon).toDouble();
    return _Vector(d.dx / length, d.dy / length);
  }

  static _Vector _outwardNormal(DimensionSegment d) {
    final tangent = _tangent(d);
    var normal = _Vector(-tangent.y, tangent.x);
    if (d.centerX != null && d.centerY != null) {
      final mx = (d.x1 + d.x2) / 2.0;
      final my = (d.y1 + d.y2) / 2.0;
      if (normal.x * (d.centerX! - mx) + normal.y * (d.centerY! - my) > 0) {
        normal = _Vector(-normal.x, -normal.y);
      }
    }
    return _Vector(
      normal.x * d.normalDirection,
      normal.y * d.normalDirection,
    );
  }
}

class _Point {
  final double x, y;
  const _Point(this.x, this.y);
}

class _Vector {
  final double x, y;
  const _Vector(this.x, this.y);
}

class _DimensionCorridor {
  final _Point center;
  final _Vector tangent;
  final _Vector normal;
  final double halfTangent;
  final double halfNormal;

  const _DimensionCorridor({
    required this.center,
    required this.tangent,
    required this.normal,
    required this.halfTangent,
    required this.halfNormal,
  });

  factory _DimensionCorridor.from(
    DimensionSegment d,
    _Vector normal,
    _Vector tangent,
    double offset,
    double halfLabelWidth,
    double textHeight,
  ) {
    final midpoint = _Point(
      (d.x1 + d.x2) / 2.0 + normal.x * offset,
      (d.y1 + d.y2) / 2.0 + normal.y * offset,
    );
    final margin = halfLabelWidth + 4.0;
    return _DimensionCorridor(
      center: midpoint,
      tangent: tangent,
      normal: normal,
      halfTangent: d.length / 2.0 + margin + 2.0,
      halfNormal: textHeight / 2.0 + 2.0,
    );
  }

  bool overlaps(_DimensionCorridor other) {
    final axes = <_Vector>[
      tangent,
      normal,
      other.tangent,
      other.normal,
    ];

    for (final axis in axes) {
      final thisRadius =
          halfTangent * _dot(tangent, axis).abs() +
          halfNormal * _dot(normal, axis).abs();
      final otherRadius =
          other.halfTangent * _dot(other.tangent, axis).abs() +
          other.halfNormal * _dot(other.normal, axis).abs();
      final centerDistance = _dot(
        _Vector(
          center.x - other.center.x,
          center.y - other.center.y,
        ),
        axis,
      ).abs();

      if (centerDistance >= thisRadius + otherRadius) {
        return false;
      }
    }
    return true;
  }

  bool intersectsSegment(
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    final corners = <_Point>[
      _Point(
        center.x + tangent.x * halfTangent + normal.x * halfNormal,
        center.y + tangent.y * halfTangent + normal.y * halfNormal,
      ),
      _Point(
        center.x - tangent.x * halfTangent + normal.x * halfNormal,
        center.y - tangent.y * halfTangent + normal.y * halfNormal,
      ),
      _Point(
        center.x - tangent.x * halfTangent - normal.x * halfNormal,
        center.y - tangent.y * halfTangent - normal.y * halfNormal,
      ),
      _Point(
        center.x + tangent.x * halfTangent - normal.x * halfNormal,
        center.y + tangent.y * halfTangent - normal.y * halfNormal,
      ),
    ];

    for (var i = 0; i < corners.length; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % corners.length];
      if (DimensionLayout._segmentsIntersect(
        x1, y1, x2, y2, a.x, a.y, b.x, b.y,
      )) {
        return true;
      }
    }

    final midpoint = _Point((x1 + x2) / 2.0, (y1 + y2) / 2.0);
    final localX = _dot(
      _Vector(midpoint.x - center.x, midpoint.y - center.y),
      tangent,
    );
    final localY = _dot(
      _Vector(midpoint.x - center.x, midpoint.y - center.y),
      normal,
    );
    return localX.abs() <= halfTangent &&
        localY.abs() <= halfNormal;
  }

  static double _dot(_Vector a, _Vector b) => a.x * b.x + a.y * b.y;
}
