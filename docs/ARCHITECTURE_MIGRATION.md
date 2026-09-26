# ARchScan — Architecture Migration

## Objective

ARchScan is moving from the current mixed application structure to a
Feature-first architecture with explicit boundaries between presentation,
domain, data and platform integrations.

The migration is intentionally incremental. Existing behavior is preserved
while each boundary is introduced and verified.

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
- AR-specific code is still imported directly by scanner UI/adapters.
- Project, floor-plan and scanner state are currently provided from a common
  application-level Provider composition.
- `FloorPlanProvider` currently contains state, geometry/edit operations,
  history and persistence coordination; it is a primary decomposition target.
- `LocalDatabaseService` currently owns the concrete Isar Community runtime;
  persistence will be isolated before the next database migration step.
- `ar_flutter_plugin_2` remains a concrete platform dependency and will be
  replaced only after the AR boundary is stable.

## Stage 1

The first implementation step introduces the Scanner feature public boundary
without moving working implementation files. Existing imports remain valid.

Next stages will migrate Scanner presentation/domain/data behind this boundary,
then apply the same pattern to projects and floor plans.

## Estado (rama `refactor/archscan-stabilization`)

| Etapa | Estado |
|---|---|
| Seguridad de firma (ver `SECURITY_INCIDENT_2026-09-signing.md`) | hecho |
| Toolchain Isar reproducible (ver `ISAR_TOOLCHAIN.md`) | hecho, pendiente CI |
| CI: ratchet de formato y auditoría 16 KB en cada build | hecho, pendiente CI |
| Frontera de persistencia: `ProjectRepository` / `ProjectSummary` | hecho, pendiente CI |
| Frontera AR: la UI no importa `ar_flutter_plugin_2` | hecho, pendiente CI |
| `FloorPlanProvider`: tipos movidos a `floor_plan_provider_types.dart` | hecho, pendiente CI |
| `FloorPlanProvider`: división de la clase por responsabilidad | bloqueada hasta CI verde + tests de caracterización |
| `floor_plan_viewer_screen`: painters, modelos y widgets en `part` | hecho, pendiente CI |
| `floor_plan_viewer_screen`: división del `State` | bloqueada hasta CI verde |
| Exportaciones: la UI usa `ImportExportService`; los builders viven en core | sin cambios necesarios por ahora |
| Actualización de dependencias (una por PR) | bloqueada hasta CI verde |

Regla: no se avanza a la siguiente etapa con CI en rojo.
