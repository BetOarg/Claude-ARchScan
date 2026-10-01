# Changelog — room_scanner_core

## 1.0.0

- Extracción inicial desde `room_scanner_ar` (monorepo `claude-room-scanner`).
- Modelos de dominio (`RoomModel`, `ARPoint`, `WallFeature`) y persistencia local mediante Drift/SQLite.
- `GeometryService` y `SharedWallService`.
- `ProjectRepository` y `DriftProjectRepository` para persistencia local de proyectos, ambientes, puntos 3D y aberturas.
- `PlanExportBuilder`, extraído de la parte pura de `ImportExportService`
  (construcción de JSON, nombre de archivo, SVG del plano y documento PDF).
- `MeasurementUnits` y `ScanValidator`.
