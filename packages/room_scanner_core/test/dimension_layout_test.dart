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

    expect(
      DimensionLayout.sort(dimensions).map((d) => d.id).toList(),
      ['door', 'wall', 'total'],
    );
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
    expect(result.map((d) => d.kind), containsAll([
      DimensionKind.wall,
      DimensionKind.total,
    ]));
  });

  test('does not collide only because rotated corridor bounding boxes overlap', () {
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
  });

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

}
