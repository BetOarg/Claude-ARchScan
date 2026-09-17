import 'dart:math' as math;

/// Dimension classification used by technical and interactive plan renderers.
enum DimensionKind {
  opening,
  wall,
  total,
}

class DimensionSegment {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final DimensionKind kind;
  final String id;

  const DimensionSegment({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.kind,
    required this.id,
  });

  double get dx => x2 - x1;
  double get dy => y2 - y1;
  double get length => math.sqrt(dx * dx + dy * dy);

  double get angle => math.atan2(dy, dx);

  DimensionSegment reversed() => DimensionSegment(
        x1: x2,
        y1: y2,
        x2: x1,
        y2: y1,
        kind: kind,
        id: id,
      );
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

/// Deterministic CAD-style dimension layout.
///
/// Ordering is semantic first (openings, wall segments, totals), then physical
/// length. Placement reserves a corridor for the complete dimension line,
/// including its label, before the next dimension is accepted.
class DimensionLayout {
  static const double defaultBaseOffset = 22.0;
  static const double defaultGap = 12.0;
  static const double defaultTextHeight = 14.0;
  static const double parallelTolerance = 0.0175; // about one degree.
  static const double axisTolerance = 2.0;

  const DimensionLayout._();

  static List<DimensionSegment> deduplicate(
    Iterable<DimensionSegment> dimensions,
  ) {
    final result = <DimensionSegment>[];
    final keys = <String>{};

    for (final dimension in dimensions) {
      final key = _canonicalKey(dimension);
      if (keys.add(key)) {
        result.add(dimension);
      }
    }

    return result;
  }

  static List<DimensionSegment> sort(
    Iterable<DimensionSegment> dimensions,
  ) {
    final result = deduplicate(dimensions);
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
    Iterable<DimensionSegment> dimensions, {
    double baseOffset = defaultBaseOffset,
    double gap = defaultGap,
    double textHeight = defaultTextHeight,
  }) {
    final ordered = sort(dimensions);
    final occupied = <_DimensionCorridor>[];
    final spacing = math.max(gap, textHeight + gap);
    final result = <DimensionPlacement>[];

    for (final dimension in ordered) {
      final normal = _normal(dimension);
      final tangent = _tangent(dimension);
      final halfText = _labelExtent(dimension.length) / 2.0;
      var level = 0;

      while (true) {
        final offset = baseOffset + level * spacing;
        final candidate = _DimensionCorridor.from(
          dimension,
          normal,
          tangent,
          offset,
          halfText,
          textHeight,
        );

        final collides = occupied.any(
          (existing) => existing.overlaps(candidate),
        );

        if (!collides) {
          occupied.add(candidate);
          result.add(
            DimensionPlacement(
              segment: dimension,
              offset: offset,
              level: level,
            ),
          );
          break;
        }

        level++;
      }
    }

    return result;
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

  static String _canonicalKey(DimensionSegment d) {
    final a = '${d.x1.toStringAsFixed(2)},${d.y1.toStringAsFixed(2)}';
    final b = '${d.x2.toStringAsFixed(2)},${d.y2.toStringAsFixed(2)}';
    final points = [a, b]..sort();
    return '${d.kind.index}:${points[0]}|${points[1]}';
  }

  static _Vector _tangent(DimensionSegment d) {
    final length = math.max(d.length, 0.000001);
    return _Vector(d.dx / length, d.dy / length);
  }

  static _Vector _normal(DimensionSegment d) {
    final tangent = _tangent(d);
    return _Vector(-tangent.y, tangent.x);
  }

  static double _labelExtent(double length) {
    // Keeps the collision corridor conservative without depending on font
    // metrics that differ between Canvas, SVG and PDF.
    return math.max(30.0, length * 0.0 + 30.0);
  }
}

class _Vector {
  final double x;
  final double y;

  const _Vector(this.x, this.y);
}

class _DimensionCorridor {
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

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
    double halfText,
    double textHeight,
  ) {
    final cx1 = d.x1 + normal.x * offset;
    final cy1 = d.y1 + normal.y * offset;
    final cx2 = d.x2 + normal.x * offset;
    final cy2 = d.y2 + normal.y * offset;

    final margin = halfText + 4.0;
    final points = <List<double>>[
      [cx1, cy1],
      [cx2, cy2],
      [cx1 + tangent.x * margin, cy1 + tangent.y * margin],
      [cx1 - tangent.x * margin, cy1 - tangent.y * margin],
      [cx2 + tangent.x * margin, cy2 + tangent.y * margin],
      [cx2 - tangent.x * margin, cy2 - tangent.y * margin],
    ];

    return _DimensionCorridor(
      minX: points.map((p) => p[0]).reduce(math.min) - 2,
      minY: points.map((p) => p[1]).reduce(math.min) - textHeight / 2,
      maxX: points.map((p) => p[0]).reduce(math.max) + 2,
      maxY: points.map((p) => p[1]).reduce(math.max) + textHeight / 2,
    );
  }

  bool overlaps(_DimensionCorridor other) {
    return minX < other.maxX &&
        maxX > other.minX &&
        minY < other.maxY &&
        maxY > other.minY;
  }
}
