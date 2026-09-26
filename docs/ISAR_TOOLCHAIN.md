# Toolchain de generación Isar

## Decisión

`isar_models.g.dart` se genera con **Flutter 3.41.4 (Dart 3.11)** mediante
`.github/actions/isar-codegen`. Análisis, tests y builds siguen usando
`FLUTTER_VERSION` (3.47.0). El código generado no depende de la versión del
SDK que lo ejecuta.

Las tres piezas de Isar se fijan a la misma versión exacta (`3.3.2`), como
indica el quickstart oficial de `isar_community`.

No se usan `dependency_overrides` ni pins de `analyzer`/`dart_style`.

## Por qué

- `isar_community_generator 3.3.2` declara `analyzer >=8.0.0 <11.0.0`.
- Flutter 3.47 trae Dart 3.13; el ecosistema que lo soporta está en analyzer
  13+ (`build_runner 2.16.1` exige `analyzer >=13.3.0`).
- En CI, con Flutter 3.47, `pub get` resuelve pero el paso de generación falla
  en todas las corridas desde la migración a Isar Community (265–271).
- La misma combinación (generator 3.3.2, build_runner 2.15.1, analyzer 10.0.1,
  dart_style 3.1.7, source_gen 4.2.4) genera correctamente con Flutter 3.41.4
  en un proyecto público: https://github.com/arcbyte-lab/Santian
- Intentos descartados (rama `refactor/feature-first-foundation`): pinear
  `analyzer 8.4.1` + `dart_style 3.1.3`, override a `analyzer 11.0.0`,
  bajar el generador a 3.3.0. Todos rompen la resolución o la generación.

## Desarrollo local

```bash
# con Flutter 3.41.x activo (fvm, puro o instalación paralela)
cd packages/room_scanner_core
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

Después se puede volver a Flutter 3.47 para correr, analizar y compilar.

## Cuándo eliminar esta restricción

Cuando se publique un `isar_community_generator` con soporte de analyzer
>=12 (upstream: issue #130, PR #139 en isar-community/isar-community).
En ese momento: subir las tres piezas de Isar juntas, borrar la acción
`isar-codegen` y volver a generar con `FLUTTER_VERSION`.

## Riesgos conocidos de Isar Community 3.3.2 (upstream)

| Issue | Estado | Impacto |
|---|---|---|
| #135 crash Scudo en Android 16 al liberar resultados | abierto | `targetSdk` 36 |
| #115 autoincrement no persiste entre reinicios (fix #131 sin publicar) | abierto | bajo: las rooms se reescriben completas y se identifican por UUID |
| #113 / #121 "Incorrect Isar Core version" | abiertos | mitigado con versión exacta |
| #126 placeholder `KGP_VERSION` en `flutter_libs` publicado | cerrado | el tag 3.3.2 está limpio; lo detecta el build Android |
| #138 dudas de mantenimiento | abierto | justifica aislar la persistencia detrás de un repositorio |
