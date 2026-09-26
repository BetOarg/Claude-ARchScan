import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:test/test.dart';

void main() {
  test('convierte IsarProject en ProjectSummary sin perder datos', () {
    final createdAt = DateTime(2026, 9, 1, 10, 30);
    final updatedAt = DateTime(2026, 9, 20, 18, 5);
    final project = IsarProject();
    project.uuid = 'project-1';
    project.name = 'Departamento Colegiales';
    project.createdAt = createdAt;
    project.updatedAt = updatedAt;

    final summary = IsarProjectRepository.toSummary(project);

    final expected = ProjectSummary(
      uuid: 'project-1',
      name: 'Departamento Colegiales',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
    expect(summary, expected);
  });

  test('ProjectSummary compara por valor', () {
    final date = DateTime(2026, 1, 1);
    final a = ProjectSummary(
      uuid: 'a',
      name: 'A',
      createdAt: date,
      updatedAt: date,
    );
    final b = ProjectSummary(
      uuid: 'a',
      name: 'A',
      createdAt: date,
      updatedAt: date,
    );
    final renamed = ProjectSummary(
      uuid: 'a',
      name: 'B',
      createdAt: date,
      updatedAt: date,
    );

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == renamed, isFalse);
  });
}
