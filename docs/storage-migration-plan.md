# Migración de persistencia local — ARchScan

## Estado actual

ARchScan utiliza Drift sobre SQLite como backend de persistencia local en la rama de migración. La aplicación mantiene una interfaz ProjectRepository, de modo que la capa de UI y dominio no depende directamente de SQLite.

La persistencia sigue siendo deliberadamente local: no hay sincronización con servidor ni cuentas de usuario.

## Objetivo de esta migración

Sustituir la implementación anterior basada en Isar por Drift/SQLite sin modificar el comportamiento funcional del producto.

Se preservan:
- proyectos, UUID, nombre y fechas;
- ambientes y su estado abierto/cerrado;
- puntos 3D;
- puertas y ventanas;
- IDs y metadatos de conexión entre ambientes;
- lectura/escritura y eliminación de proyectos;
- escaneo, geometría, Undo/Redo, continuidad y exportaciones;
- UI, UX y localización.

## Estrategia aplicada

La migración se realiza por capas y con cambios acotados:
1. ProjectRepository define el contrato de persistencia.
2. DriftProjectRepository implementa ese contrato.
3. ArchScanDatabase define el esquema SQLite mediante Drift.
4. Los tests de repositorio verifican round-trip de proyectos, puntos, aberturas, metadatos de conexión, reemplazo sin duplicados y eliminación de dependencias.
5. ProjectProvider utiliza el repositorio Drift; no accede directamente a tablas SQLite.
6. El código generado por Drift se produce con build_runner en CI.

## Esquema Drift

La versión inicial del esquema es schemaVersion = 1 e incluye Projects, Rooms, RoomPoints y WallFeaturesTable.

Las relaciones se representan mediante claves internas SQLite. Los valores de enums se almacenan por nombre para evitar depender de posiciones numéricas.

## Datos históricos

Antes de publicar una compilación que utilice Drift, debe determinarse si existe alguna instalación real de ARchScan que contenga datos persistidos con el backend anterior.

- Si no existe una versión pública con datos persistidos anteriores, no hay una migración de datos de usuario que ejecutar.
- Si existen instalaciones reales con datos anteriores, la entrega debe incluir una migración explícita o una ruta de importación/recuperación mediante JSON antes de eliminar definitivamente el backend anterior.

No se debe asumir que un cambio de backend conserva automáticamente una base de datos instalada.

## Próximo endurecimiento

Después de estabilizar compilación y tests:
1. generar snapshots de esquema Drift;
2. añadir pruebas de migración schemaVersion;
3. probar apertura con bases SQLite de versiones anteriores;
4. validar rendimiento con proyectos grandes;
5. validar físicamente Android e iOS;
6. ejecutar regresión de proyectos, continuidad, exportaciones y recuperación;
7. conservar un procedimiento de rollback y copias JSON de los proyectos de prueba.

## Regla de seguridad

La migración de almacenamiento no debe mezclarse con cambios del motor CAD, escaneo AR, exportadores o UX. Si una regresión aparece, se corrige en esta capa antes de continuar con otras reformas.

Estado: backend Drift implementado; CI automatizado verde en el commit f6680c871a0c7d18d22a368d387c26d73cd49b63.
