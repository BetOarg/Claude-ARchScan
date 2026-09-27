# ARchScan — Architecture Migration

## Objective

ARchScan is moving from the current mixed application structure to a
Feature-first architecture with explicit boundaries between presentation,
domain, data and platform integrations.

The migration is intentionally incremental. Existing behavior is preserved
while each boundary is introduced and verified. Persistence has now moved to
Drift/SQLite behind `ProjectRepository`.

## Target structure

```
packages/room_scanner_app/lib/
  app/
  core/
  features/
    scanner/
      presentation/
      domain/
      data/
    projects/
      presentation/
      domain/
      data/
    floor_plan/
      presentation/
      domain/
      data/
    measurements/
    openings/
    exports/
    settings/
  infrastructure/
    ar/
    persistence/
    filesystem/
    sharing/
  shared/
```

This is a target architecture, not a requirement to create empty folders or
move files mechanically.

## Migration rules

1. Preserve observable behavior and persisted project compatibility.
2. Introduce one architectural boundary at a time.
3. Keep hardware/plugin code behind interfaces.
4. Keep persistence behind repositories before changing the database engine.
5. Do not split files solely because they are large; split by responsibility.
6. Avoid unrelated UX changes during architectural migration.
7. Require analysis, tests and platform builds to pass before advancing a
   migration stage.

## Current first-stage findings

- Scanner already has a useful adapter/engine/factory seam.
- AR-specific code is isolated behind the Scanner adapter/session boundary.
- Project, floor-plan and scanner state are currently provided from a common
  application-level Provider composition.
- `FloorPlanProvider` currently contains state, geometry/edit operations,
  history and persistence coordination; it is a primary decomposition target.
- `DriftProjectRepository` owns the concrete Drift/SQLite runtime behind the
  `ProjectRepository` boundary; the former Isar service and models were removed.
- `ar_flutter_plugin_plus` is now isolated behind the AR adapter/session boundary;
  the legacy `ar_flutter_plugin_2` dependency has been removed.

## Stage 1

The first implementation step introduces the Scanner feature public boundary
without moving working implementation files. Existing imports remain valid.

Next stages will migrate Scanner presentation/domain/data behind this boundary,
then apply the same pattern to projects and floor plans.

## Estado (rama `refactor/archscan-stabilization-v2`)

| Etapa | Estado |
|---|---|
| Seguridad de firma (ver `SECURITY_INCIDENT_2026-09-signing.md`) | hecho |
| Persistencia Drift/SQLite + generación reproducible | hecho, CI verde |
| CI: ratchet de formato y auditoría 16 KB en cada build | hecho, pendiente CI |
| Frontera de persistencia: `ProjectRepository` / `ProjectSummary` | hecho, pendiente CI |
| Frontera AR: la UI no importa `ar_flutter_plugin_2` | hecho, pendiente CI |
| `FloorPlanProvider`: tipos movidos a `floor_plan_provider_types.dart` | hecho, pendiente CI |
| `FloorPlanProvider`: división de la clase por responsabilidad | siguiente bloque |
| `floor_plan_viewer_screen`: painters, modelos y widgets en `part` | hecho, pendiente CI |
| `floor_plan_viewer_screen`: división del `State` | siguiente bloque |
| Exportaciones: la UI usa `ImportExportService`; los builders viven en core | sin cambios necesarios por ahora |
| Actualización de dependencias (una por PR) | siguiente bloque, después de estabilizar AR |

Regla: no se avanza a la siguiente etapa con CI en rojo.
