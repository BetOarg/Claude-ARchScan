# Migración de persistencia a Drift

ARchScan reemplaza Isar Community por Drift/SQLite.

## Objetivo

La aplicación conserva la frontera ProjectRepository. El scanner, la geometría, los proyectos y la UI no dependen directamente del motor de base de datos.

## Primera versión del esquema

La tabla projects contiene: id, uuid único, name, created_at, updated_at y rooms_json.
Los ambientes se serializan mediante los toJson/fromJson existentes para no cambiar el modelo de dominio durante esta primera etapa.

Guardar un proyecto reemplaza atómicamente su fila y conserva created_at.

## Herramientas

La generación usa drift_dev + build_runner. Drift proporciona generación tipada, análisis del esquema y herramientas de migración verificables.

## Compatibilidad de datos

La versión 2.7.0 no fue publicada con Isar. Por lo tanto, no existe una base Isar de una versión publicada de ARchScan que deba convertirse como parte de esta migración.

Las instalaciones internas o de prueba que hayan usado Isar no forman parte de una actualización publicada. Si fuera necesario recuperar esos datos, puede utilizarse una exportación/importación explícita mediante JSON o SVG.

Para una instalación nueva, Drift crea directamente el esquema inicial.

## Próximas etapas

1. Mantener ProjectRepository como única frontera de persistencia.
2. Añadir pruebas de esquema y migraciones antes de cambiar schemaVersion.
3. Auditar recuperación de proyectos, borradores y continuidad del escaneo.
4. Solo después evaluar una normalización de ambientes, paredes y aberturas en tablas separadas si existe una necesidad funcional o de rendimiento.

No mezclar estos cambios con UX ni con la sustitución del adaptador AR.
