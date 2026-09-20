# Estrategia futura de persistencia local

## Estado actual

ARchScan utiliza Isar como persistencia local de proyectos y datos de escaneo. La dependencia actual es `isar ^3.1.0+1`.

Esta capa es deliberadamente local: no hay sincronización con servidor ni cuentas de usuario.

## Decisión para la beta

No migrar la base de datos antes de la beta.

La persistencia existente es parte del flujo funcional de ARchScan y una migración previa al lanzamiento introduciría riesgo innecesario sobre proyectos existentes, generación de modelos, exportaciones y recuperación de borradores.

## Criterios para una migración futura

Antes de sustituir Isar se debe verificar:

1. mantenimiento activo y compatibilidad con la versión de Flutter/Dart adoptada;
2. soporte Android e iOS para las versiones objetivo;
3. equivalencia de consultas, índices y relaciones utilizadas por ARchScan;
4. migración de datos existentes sin pérdida de proyectos;
5. compatibilidad con los modelos generados actualmente;
6. rendimiento con proyectos grandes y múltiples habitaciones;
7. recuperación de borradores y continuidad del escaneo;
8. exportación JSON/DXF/SVG/PDF/PNG/JPG después de migrar;
9. pruebas de regresión y rollback.

## Estrategia recomendada

La migración debe realizarse en una fase independiente:

- introducir una interfaz de repositorio de persistencia;
- mantener Isar detrás de esa interfaz;
- implementar el nuevo backend en paralelo;
- probar lectura/escritura y migración sobre copias de datos;
- validar físicamente Android e iOS;
- activar el nuevo backend únicamente después de completar la matriz de regresión.

No se debe modificar el formato persistido ni eliminar Isar durante esta fase documental.

## Regla de seguridad

Una migración de almacenamiento no debe mezclarse con cambios del motor CAD, escaneo AR, exportadores o UX. Debe ser una iniciativa independiente con rollback definido.
