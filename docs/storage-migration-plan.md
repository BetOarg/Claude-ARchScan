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

## Endurecimiento completado

Los siguientes controles ya fueron ejecutados en esta rama:
1. pruebas de round-trip y reemplazo sin duplicados;
2. persistencia en SQLite real con cierre, reapertura y reinicio;
3. prueba de ciclo de vida con 40 ambientes, 2.000 puntos y 400 vanos;
4. integración de ProjectProvider con Drift;
5. continuidad con vanos compartidos y persistencia de ambos lados;
6. Undo/Redo y persistencia del resultado restaurado;
7. validación de build Android e iOS en CI;
8. auditoría de referencias Isar con guard automático en Housekeeping.

Pendientes que requieren entorno físico o datos de producción:
- validar ARCore sobre dispositivo Android real;
- validar ARKit/RoomPlan sobre dispositivo Apple compatible;
- determinar si alguna instalación pública anterior contiene datos Isar que deban recuperarse.

## Regla de seguridad

La migración de almacenamiento no debe mezclarse con cambios del motor CAD, escaneo AR, exportadores o UX. Si una regresión aparece, se corrige en esta capa antes de continuar con otras reformas.

Estado: backend Drift implementado; auditoría de referencias Isar añadida al gate de housekeeping en el commit 305d4425362fe72d0c6662d7244296322b04cd4f.
