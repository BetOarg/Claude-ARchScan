import 'dart:math' as math;

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

  const DimensionPlacement({
    required this.segment,
    required this.offset,
    required this.level,
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
      if (dimension.length < 0.000001) continue;
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
  }) {
    final ordered = sort(input);
    final occupied = <_DimensionCorridor>[];
    final walls = ordered
        .where((dimension) => dimension.kind == DimensionKind.wall)
        .toList(growable: false);
    final spacing = math.max(gap, textHeight + gap).toDouble();
    final result = <DimensionPlacement>[];

    for (final dimension in ordered) {
      final normal = _outwardNormal(dimension);
      final tangent = _tangent(dimension);
      var placed = false;

      for (var level = 0; level < maxLevels; level++) {
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
          normal,
          offset,
          walls,
        )) {
          continue;
        }

        occupied.add(corridor);
        result.add(DimensionPlacement(
          segment: dimension,
          offset: offset,
          level: level,
        ));
        placed = true;
        break;
      }

      // A pathological geometry must not make the painter/exporter loop
      // forever. The dimension is omitted rather than producing an invalid
      // placement.
      if (!placed) continue;
    }
    return result;
  }

  static bool _crossesAnotherWall(
    DimensionSegment dimension,
    _Vector normal,
    double offset,
    List<DimensionSegment> walls,
  ) {
    final start = _Point(
      dimension.x1 + normal.x * offset,
      dimension.y1 + normal.y * offset,
    );
    final end = _Point(
      dimension.x2 + normal.x * offset,
      dimension.y2 + normal.y * offset,
    );

    for (final wall in walls) {
      if (_sameGeometry(dimension, wall)) continue;
      if (_segmentsIntersect(
        start.x,
        start.y,
        end.x,
        end.y,
        wall.x1,
        wall.y1,
        wall.x2,
        wall.y2,
      )) {
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
    final a = '${d.x1.toStringAsFixed(2)},${d.y1.toStringAsFixed(2)}';
    final b = '${d.x2.toStringAsFixed(2)},${d.y2.toStringAsFixed(2)}';
    final points = [a, b]..sort();

    // Overall dimensions are a distinct semantic measure from wall/opening
    // dimensions. They must remain visible even when their endpoints coincide
    // with the bounding wall; reversed duplicates of the same total still
    // collapse because the kind remains part of the key.
    final kind = d.kind == DimensionKind.total ? 'total:' : '';
    return '$kind${points[0]}|${points[1]}';
  }

  static _Vector _tangent(DimensionSegment d) {
    final length = math.max(d.length, 0.000001).toDouble();
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
  final double minX, minY, maxX, maxY;
  const _DimensionCorridor({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  factory _DimensionCorridor.from(
    DimensionSegment d,
    _Vector normal,
    _Vector tangent,
    double offset,
    double halfLabelWidth,
    double textHeight,
  ) {
    final x1 = d.x1 + normal.x * offset;
    final y1 = d.y1 + normal.y * offset;
    final x2 = d.x2 + normal.x * offset;
    final y2 = d.y2 + normal.y * offset;
    final longitudinalMargin = halfLabelWidth + 4.0;
    final transverseMargin = textHeight / 2.0 + 4.0;
    final points = <List<double>>[
      [x1, y1],
      [x2, y2],
      [x1 + tangent.x * longitudinalMargin + normal.x * transverseMargin,
       y1 + tangent.y * longitudinalMargin + normal.y * transverseMargin],
      [x1 - tangent.x * longitudinalMargin - normal.x * transverseMargin,
       y1 - tangent.y * longitudinalMargin - normal.y * transverseMargin],
      [x2 + tangent.x * longitudinalMargin + normal.x * transverseMargin,
       y2 + tangent.y * longitudinalMargin + normal.y * transverseMargin],
      [x2 - tangent.x * longitudinalMargin - normal.x * transverseMargin,
       y2 - tangent.y * longitudinalMargin - normal.y * transverseMargin],
    ];
    final minX = points.map((p) => p[0]).reduce((a, b) => math.min(a, b));
    final minY = points.map((p) => p[1]).reduce((a, b) => math.min(a, b));
    final maxX = points.map((p) => p[0]).reduce((a, b) => math.max(a, b));
    final maxY = points.map((p) => p[1]).reduce((a, b) => math.max(a, b));
    return _DimensionCorridor(
      minX: minX - 2.0,
      minY: minY - textHeight / 2.0,
      maxX: maxX + 2.0,
      maxY: maxY + textHeight / 2.0,
    );
  }

  bool overlaps(_DimensionCorridor other) =>
      minX < other.maxX &&
      maxX > other.minX &&
      minY < other.maxY &&
      maxY > other.minY;
}
