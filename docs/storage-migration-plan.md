# Estrategia de persistencia local

## Estado actual

ARchScan utiliza **Drift/SQLite** como persistencia local. La aplicación mantiene la frontera `ProjectRepository`, por lo que las pantallas y el dominio no dependen directamente del motor de base de datos.

Esta capa es deliberadamente local: no hay sincronización propia con servidor ni cuentas de usuario.

## Migración realizada

La rama de estabilización reemplazó Isar Community por Drift. La primera versión conserva el modelo de dominio existente y almacena los ambientes serializados en `projects.rooms_json` para minimizar cambios funcionales durante la transición.

El esquema inicial contiene:

- `id`: clave interna autoincremental;
- `uuid`: identificador estable y único del proyecto;
- `name`: nombre del proyecto;
- `created_at` y `updated_at`: fechas de creación y modificación;
- `rooms_json`: ambientes serializados mediante `RoomModel.toJson/fromJson`.

Las escrituras de proyecto se realizan dentro de una transacción y conservan `created_at` al actualizar un proyecto existente.

## Compatibilidad con instalaciones históricas

La versión 2.7.0 no fue publicada con Isar. Por ello, no existe una base Isar de una versión publicada de ARchScan que deba convertirse para esta migración. Las instalaciones internas o de prueba que hayan usado Isar no forman parte de una actualización publicada; si se necesitara conservar esos datos, puede utilizarse una exportación/importación explícita mediante JSON/SVG.

Para una instalación nueva, Drift crea directamente el esquema inicial.

## Próximas etapas

1. Mantener `ProjectRepository` como única frontera de persistencia.
2. Añadir pruebas de esquema y migraciones antes de cambiar `schemaVersion`.
3. Auditar recuperación de proyectos, borradores y continuidad del escaneo.
4. Solo después evaluar una normalización de ambientes, paredes y aberturas en tablas separadas si aporta una necesidad funcional o de rendimiento.

No mezclar estos cambios con UX ni con la sustitución del adaptador AR.