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

## Próxima etapa

Antes de publicar una versión con datos persistidos existentes, se debe decidir si hace falta una herramienta explícita Isar → Drift para instalaciones que ya contengan datos. Para una instalación nueva de beta, Drift crea su base SQLite desde el esquema versión 1.

Las futuras modificaciones de tablas deberán incrementar schemaVersion y conservar snapshots de esquema para validar migraciones.
