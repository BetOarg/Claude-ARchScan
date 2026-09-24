import 'package:test/test.dart';

import 'package:room_scanner_core/src/export/dimension_layout.dart';

void main() {
  test('orders openings, wall segments, then totals', () {
    final dimensions = [
      const DimensionSegment(
        x1: 0,
        y1: 0,
        x2: 4,
        y2: 0,
        kind: DimensionKind.total,
        id: 'total',
      ),
      const DimensionSegment(
        x1: 0,
        y1: 0,
        x2: 2,
        y2: 0,
        kind: DimensionKind.wall,
        id: 'wall',
      ),
      const DimensionSegment(
        x1: 0,
        y1: 0,
        x2: 0.8,
        y2: 0,
        kind: DimensionKind.opening,
        id: 'door',
      ),
    ];

    expect(DimensionLayout.sort(dimensions).map((d) => d.id).toList(), [
      'door',
      'wall',
      'total',
    ]);
  });

  test('removes reversed duplicates on the same axis', () {
    const original = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 2,
      y2: 0,
      kind: DimensionKind.wall,
      id: 'a',
    );
    const reversed = DimensionSegment(
      x1: 2,
      y1: 0,
      x2: 0,
      y2: 0,
      kind: DimensionKind.wall,
      id: 'b',
    );

    expect(DimensionLayout.deduplicate([original, reversed]), hasLength(1));
  });

  test('prefers opening over a redundant wall dimension on the same axis', () {
    const wall = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 0.8,
      y2: 0,
      kind: DimensionKind.wall,
      id: 'wall',
    );
    const opening = DimensionSegment(
      x1: 0.8,
      y1: 0,
      x2: 0,
      y2: 0,
      kind: DimensionKind.opening,
      id: 'opening',
    );

    final result = DimensionLayout.sort([wall, opening]);

    expect(result, hasLength(1));
    expect(result.single.kind, DimensionKind.opening);
  });

  test('moves a colliding parallel dimension to the next level', () {
    const first = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 3,
      y2: 0,
      kind: DimensionKind.wall,
      id: 'first',
      centerX: 1.5,
      centerY: 1,
    );
    const second = DimensionSegment(
      x1: 0.5,
      y1: 0,
      x2: 2.5,
      y2: 0,
      kind: DimensionKind.wall,
      id: 'second',
      centerX: 1.5,
      centerY: 1,
    );

    final placements = DimensionLayout.layout([first, second]);

    expect(placements, hasLength(2));
    expect(placements[0].level, 0);
    expect(placements[1].level, greaterThan(0));
    expect(placements[1].offset, greaterThan(placements[0].offset));
  });

  test('keeps shorter dimensions closer than totals', () {
    const opening = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 0.8,
      y2: 0,
      kind: DimensionKind.opening,
      id: 'opening',
      centerX: 2,
      centerY: 2,
    );
    const total = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 4,
      y2: 0,
      kind: DimensionKind.total,
      id: 'total',
      centerX: 2,
      centerY: 2,
    );

    final placements = DimensionLayout.layout([total, opening]);

    expect(placements.first.segment.id, 'opening');
    expect(placements.last.segment.id, 'total');
    expect(placements.last.offset, greaterThan(placements.first.offset));
  });

  test('keeps a total dimension distinct from coincident wall geometry', () {
    const wall = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 4,
      y2: 0,
      kind: DimensionKind.wall,
      id: 'wall',
    );
    const total = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 4,
      y2: 0,
      kind: DimensionKind.total,
      id: 'total',
    );

    final result = DimensionLayout.deduplicate([wall, total]);

    expect(result, hasLength(2));
    expect(
      result.map((d) => d.kind),
      containsAll([DimensionKind.wall, DimensionKind.total]),
    );
  });

  test(
    'does not collide only because rotated corridor bounding boxes overlap',
    () {
      const first = DimensionSegment(
        x1: 0,
        y1: 0,
        x2: 10,
        y2: 10,
        kind: DimensionKind.opening,
        id: 'diagonal-a',
      );
      const second = DimensionSegment(
        x1: 0,
        y1: 8,
        x2: 10,
        y2: 18,
        kind: DimensionKind.opening,
        id: 'diagonal-b',
      );

      final placements = DimensionLayout.layout(
        [first, second],
        baseOffset: 0,
        gap: 1,
        textHeight: 1,
        labelHalfWidth: 0.5,
      );

      expect(placements, hasLength(2));
      expect(placements.map((p) => p.level), [0, 0]);
    },
  );

  test('moves a dimension outward when its corridor crosses another wall', () {
    const dimension = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 2,
      y2: 0,
      kind: DimensionKind.wall,
      id: 'dimension',
      centerX: 1,
      centerY: 1,
    );
    const crossingWall = DimensionSegment(
      x1: 1,
      y1: -25,
      x2: 1,
      y2: -15,
      kind: DimensionKind.wall,
      id: 'crossing-wall',
      centerX: 1,
      centerY: 1,
    );

    final placements = DimensionLayout.layout(
      [dimension, crossingWall],
      baseOffset: 22,
      gap: 12,
      textHeight: 14,
    );

    final placement = placements.firstWhere(
      (item) => item.segment.id == 'dimension',
    );

    expect(placement.level, greaterThan(0));
    expect(placement.offset, greaterThan(22));
  });
  test('moves a dimension when its text corridor intersects another wall', () {
    const dimension = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 4,
      y2: 0,
      kind: DimensionKind.opening,
      id: 'dimension',
    );
    const nearbyWall = DimensionSegment(
      x1: 1.5,
      y1: 2.5,
      x2: 2.5,
      y2: 2.5,
      kind: DimensionKind.wall,
      id: 'nearby-wall',
    );

    final placements = DimensionLayout.layout(
      [dimension, nearbyWall],
      baseOffset: 0,
      gap: 1,
      textHeight: 2,
      labelHalfWidth: 0.5,
    );

    final placement = placements.firstWhere(
      (item) => item.segment.id == 'dimension',
    );

    expect(placement.level, greaterThan(0));
  });

  test('moves a dimension when a wall only touches the corridor corner', () {
    const dimension = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 4,
      y2: 0,
      kind: DimensionKind.opening,
      id: 'dimension',
    );
    const cornerWall = DimensionSegment(
      x1: 8.5,
      y1: 3,
      x2: 9.5,
      y2: 3,
      kind: DimensionKind.wall,
      id: 'corner-wall',
    );

    final placements = DimensionLayout.layout(
      [dimension, cornerWall],
      baseOffset: 0,
      gap: 1,
      textHeight: 2,
      labelHalfWidth: 0.5,
    );

    final placement = placements.firstWhere(
      (item) => item.segment.id == 'dimension',
    );

    expect(placement.level, greaterThan(0));
  });

  test('detects collinear wall contact with a corridor edge', () {
    const dimension = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 4,
      y2: 0,
      kind: DimensionKind.opening,
      id: 'dimension',
    );
    const edgeWall = DimensionSegment(
      x1: -3,
      y1: 3,
      x2: 7,
      y2: 3,
      kind: DimensionKind.wall,
      id: 'edge-wall',
    );

    final placements = DimensionLayout.layout(
      [dimension, edgeWall],
      baseOffset: 0,
      gap: 1,
      textHeight: 2,
      labelHalfWidth: 0.5,
    );

    final placement = placements.firstWhere(
      (item) => item.segment.id == 'dimension',
    );

    expect(placement.level, greaterThan(0));
  });

  test('geometry matrix preserves rectangular perimeter dimensions', () {
    const rectangle = [
      DimensionSegment(
        x1: 0,
        y1: 0,
        x2: 6,
        y2: 0,
        kind: DimensionKind.wall,
        id: 'bottom',
      ),
      DimensionSegment(
        x1: 6,
        y1: 0,
        x2: 6,
        y2: 4,
        kind: DimensionKind.wall,
        id: 'right',
      ),
      DimensionSegment(
        x1: 6,
        y1: 4,
        x2: 0,
        y2: 4,
        kind: DimensionKind.wall,
        id: 'top',
      ),
      DimensionSegment(
        x1: 0,
        y1: 4,
        x2: 0,
        y2: 0,
        kind: DimensionKind.wall,
        id: 'left',
      ),
    ];
    final result = DimensionLayout.deduplicate(rectangle);
    expect(result, hasLength(4));
    expect(
      result.map((d) => d.id),
      containsAll(['bottom', 'right', 'top', 'left']),
    );
  });

  test('geometry matrix preserves an L-shaped perimeter', () {
    const lShape = [
      DimensionSegment(
        x1: 0,
        y1: 0,
        x2: 5,
        y2: 0,
        kind: DimensionKind.wall,
        id: 'bottom',
      ),
      DimensionSegment(
        x1: 5,
        y1: 0,
        x2: 5,
        y2: 3,
        kind: DimensionKind.wall,
        id: 'right',
      ),
      DimensionSegment(
        x1: 5,
        y1: 3,
        x2: 2,
        y2: 3,
        kind: DimensionKind.wall,
        id: 'step',
      ),
      DimensionSegment(
        x1: 2,
        y1: 3,
        x2: 2,
        y2: 6,
        kind: DimensionKind.wall,
        id: 'inner',
      ),
      DimensionSegment(
        x1: 2,
        y1: 6,
        x2: 0,
        y2: 6,
        kind: DimensionKind.wall,
        id: 'top',
      ),
      DimensionSegment(
        x1: 0,
        y1: 6,
        x2: 0,
        y2: 0,
        kind: DimensionKind.wall,
        id: 'left',
      ),
    ];
    final result = DimensionLayout.sort(lShape);
    expect(result, hasLength(6));
    expect(result.every((d) => d.kind == DimensionKind.wall), isTrue);
  });

  test('geometry matrix keeps slanted wall dimensions distinct', () {
    const slanted = [
      DimensionSegment(
        x1: 0,
        y1: 0,
        x2: 4,
        y2: 3,
        kind: DimensionKind.wall,
        id: 'diagonal-a',
      ),
      DimensionSegment(
        x1: 0,
        y1: 4,
        x2: 4,
        y2: 7,
        kind: DimensionKind.wall,
        id: 'diagonal-b',
      ),
    ];
    final result = DimensionLayout.deduplicate(slanted);
    expect(result, hasLength(2));
    expect(result.every((d) => (d.length - 5).abs() < 0.000001), isTrue);
  });

  test('geometry matrix preserves opening, wall and total semantics', () {
    const opening = DimensionSegment(
      x1: 1,
      y1: 0,
      x2: 2,
      y2: 0,
      kind: DimensionKind.opening,
      id: 'door',
    );
    const wall = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 4,
      y2: 0,
      kind: DimensionKind.wall,
      id: 'wall',
    );
    const total = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 4,
      y2: 0,
      kind: DimensionKind.total,
      id: 'total',
    );
    final result = DimensionLayout.sort([total, wall, opening]);
    expect(result.map((d) => d.kind), [
      DimensionKind.opening,
      DimensionKind.wall,
      DimensionKind.total,
    ]);
  });

  test('geometry matrix deduplicates a shared wall between adjacent rooms', () {
    const roomA = DimensionSegment(
      x1: 4,
      y1: 0,
      x2: 4,
      y2: 4,
      kind: DimensionKind.wall,
      id: 'room-a-shared',
    );
    const roomB = DimensionSegment(
      x1: 4,
      y1: 4,
      x2: 4,
      y2: 0,
      kind: DimensionKind.wall,
      id: 'room-b-shared',
    );
    final result = DimensionLayout.deduplicate([roomA, roomB]);
    expect(result, hasLength(1));
  });

  test(
    'geometry integrity keeps distinct segments closer than one centimeter',
    () {
      const first = DimensionSegment(
        x1: 0,
        y1: 0,
        x2: 1,
        y2: 0,
        kind: DimensionKind.wall,
        id: 'first',
      );
      const second = DimensionSegment(
        x1: 0,
        y1: 0.004,
        x2: 1,
        y2: 0.004,
        kind: DimensionKind.wall,
        id: 'second',
      );

      final result = DimensionLayout.deduplicate([first, second]);

      expect(result, hasLength(2));
    },
  );

  test(
    'geometry integrity ignores non-finite segments without poisoning layout',
    () {
      const invalid = DimensionSegment(
        x1: double.nan,
        y1: 0,
        x2: 1,
        y2: 0,
        kind: DimensionKind.wall,
        id: 'invalid',
      );
      const valid = DimensionSegment(
        x1: 0,
        y1: 0,
        x2: 2,
        y2: 0,
        kind: DimensionKind.wall,
        id: 'valid',
      );

      final result = DimensionLayout.layout([invalid, valid]);

      expect(result, hasLength(1));
      expect(result.single.segment.id, 'valid');
    },
  );

  test('strict hierarchy creates separate facade bands', () {
    const opening = DimensionSegment(
      x1: 0.5,
      y1: 0,
      x2: 1.5,
      y2: 0,
      kind: DimensionKind.opening,
      id: 'opening',
      centerX: 2,
      centerY: 2,
    );
    const wall = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 4,
      y2: 0,
      kind: DimensionKind.wall,
      id: 'wall',
      centerX: 2,
      centerY: 2,
    );
    const total = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 4,
      y2: 0,
      kind: DimensionKind.total,
      id: 'total',
      centerX: 2,
      centerY: 2,
    );

    final placements = DimensionLayout.layout([
      total,
      wall,
      opening,
    ], strictHierarchy: true);

    final byId = <String, DimensionPlacement>{
      for (final placement in placements) placement.segment.id: placement,
    };
    expect(byId['opening']!.level, 0);
    expect(byId['wall']!.level, greaterThan(byId['opening']!.level));
    expect(byId['total']!.level, greaterThan(byId['wall']!.level));
  });

  test('optional redundancy suppression removes wall segments equal to overall size', () {
    const wall = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 4,
      y2: 0,
      kind: DimensionKind.wall,
      id: 'wall',
    );
    const total = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 4,
      y2: 0,
      kind: DimensionKind.total,
      id: 'total',
    );

    final placements = DimensionLayout.layout(
      [wall, total],
      suppressRedundantOverallSegments: true,
      strictHierarchy: true,
    );

    expect(placements, hasLength(1));
    expect(placements.single.segment.kind, DimensionKind.total);
  });

  test(
    'renderer placement exposes the resolved tangent and outward normal',
    () {
      const segment = DimensionSegment(
        x1: 0,
        y1: 0,
        x2: 0,
        y2: 4,
        kind: DimensionKind.wall,
        id: 'vertical',
        centerX: 1,
        centerY: 2,
      );

      final placement = DimensionLayout.layout(
        [segment],
        baseOffset: 2,
        gap: 1,
        textHeight: 1,
        labelHalfWidth: 0.5,
      ).single;

      expect(placement.tangentX, closeTo(0, 0.000001));
      expect(placement.tangentY, closeTo(1, 0.000001));
      expect(placement.normalX, closeTo(-1, 0.000001));
      expect(placement.normalY, closeTo(0, 0.000001));
      expect(placement.offset, 2);
    },
  );
}
