# ARchScan

**Mobile space surveying, 2D floor-plan editing, and technical exports for Android and iOS.**

ARchScan records room geometry using supported augmented-reality capabilities or a basic camera-guided workflow with manual measurements. Edit connected spaces in a shared 2D plan, preserve projects locally, and export technical documents.

> **Measurement disclaimer:** Mobile measurements are indicative. Verify dimensions physically before using them for construction, estimates, or professional decisions.

## Release status

- **Documented candidate:** `2.7.2+6` — not a statement that this version has been published.
- **Distribution status:** Google Play and App Store publication is not confirmed.
- **Beta scope:** free, no ads, no in-app purchases, and no feature locks.
- **Persistence:** local Drift/SQLite storage; no ARchScan account or app-owned cloud sync.
- **Pro:** a possible future one-time unlock; not implemented or available for purchase.
- **Release gate:** final signed Android App Bundle and iOS distribution artifact, physical-device validation, store metadata, and privacy declarations must be checked before publication.

The [final repository audit](docs/FINAL_REPOSITORY_AUDIT.md) and [release-readiness checklist](docs/RELEASE_READINESS_CHECKLIST.md) distinguish automated checks from device and store validation.

## Features

### Capture and room continuity

- Basic Scanner with camera guidance and manually entered distances when AR is unavailable.
- ARCore on compatible Android devices and ARKit on compatible Apple devices.
- Room corners, walls, doors, windows, dimensions, and shared-wall relationships.
- Continue open contours from their endpoints and create a new room between selected corners of an existing room.
- AR continuation calibration using known vertices to align a new session.
- Undo/redo for supported scan and editing actions.

### Shared 2D plan editor

- Select and edit walls and corners, drag walls, and snap to nearby points or walls.
- Preview and confirm valid room closures.
- Add and position doors and windows from the overall plan.
- Move, rotate, and align rooms and connected groups.
- Pan and zoom the plan, including dedicated zoom controls.
- Rename or close a project without losing its local identity and room data.
- Protect connected openings when editing walls; editing history is session-based, not a permanent backup.

### Import and export

| Format | Export | Import |
|---|:---:|:---:|
| JSON project | Yes | Yes |
| ARchScan SVG with embedded project metadata | Yes | Yes* |
| PDF technical plan | Yes | No |
| 2D DXF for CAD software | Yes | No |
| PNG plan image | Yes | No |
| JPG plan image | Yes | No |

- Files can be saved through the device file interface or shared with installed apps.
- SVG import accepts only valid ARchScan project metadata; generic SVG drawings are rejected.
- Project geometry is stored internally in meters. The interface supports metric and imperial units.
- DXF is 2D; it is not DWG. DXF import and DWG export are not provided.
- Exported files saved outside ARchScan are managed by the user and their chosen destination.

See the [2D DXF notes](docs/dxf-2d.md) and the [touch editor guide](docs/plan-touch-editor.md).

## Privacy and local data

ARchScan does not require an account and does not operate its own project-sync service. Projects are stored locally with Drift/SQLite. Exported or shared files may be stored outside the app, and sharing may create temporary cache copies.

Before uninstalling the app or installing a build signed with a different key, export important projects to JSON and store the backup outside ARchScan. Uninstalling or clearing app data can remove local projects.

- [Public privacy policy](docs/PUBLIC_PRIVACY_POLICY.md)
- [Local data deletion information](docs/ACCOUNT_DELETION_PAGE.md)
- [Privacy data audit](docs/PRIVACY_DATA_AUDIT.md)

## Documentation and website

- [User Guide — English first, Spanish second](docs/USER_GUIDE.md)
- [Website copy for Google Sites — English first, Spanish second](docs/WEBSITE_CONTENT_ES_EN.md)
- [Public ARchScan website](https://sites.google.com/view/archscan/inicio)
- [Support page](https://sites.google.com/view/archscan/soporte-support)
- [Privacy page](https://sites.google.com/view/archscan/privacidad-privacy)

The repository contains the reviewed website copy. Google Sites must be updated and published separately; a repository change does not itself publish the website.

## Repository architecture

| Package | Responsibility |
|---|---|
| `packages/room_scanner_core` | Domain models, geometry, Drift/SQLite persistence, JSON/SVG import and export, PDF and DXF generation |
| `packages/room_scanner_app` | Flutter UI and state, localization, camera, and AR adapters |

Persistence is Drift/SQLite. Do not reintroduce Isar.

## Development

The CI and release workflows define the authoritative toolchain versions. Android uses Java 17; iOS builds require macOS, Xcode, and CocoaPods.

From the repository root:

```bash
cd packages/room_scanner_core
dart pub get
dart run build_runner build --delete-conflicting-outputs
dart analyze --fatal-infos
dart test

cd ../room_scanner_app
flutter pub get
flutter gen-l10n
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter run
```

Generated Drift code and localization resources must be regenerated when their sources change. Melos can also be used according to `melos.yaml`.

## Store release checklist

The Google Play delivery is a **signed Android App Bundle (.aab)**; a debug APK is for installation and device testing, not the final store upload.

Before publication:

1. Confirm CI is green for the exact commit being released.
2. Generate and verify the signed AAB; record its SHA-256, package identity (`com.bet0.ARchScan`), version/build, signature, manifest permissions, native libraries, and 16 KB page compatibility.
3. Test that exact artifact on target Android devices, including ARCore and permission recovery.
4. Prepare and verify the signed iOS distribution artifact on compatible hardware, including ARKit/RoomPlan where supported.
5. Complete store listings, screenshots from the tested build, privacy declarations, support URLs, and beta requirements.
6. Promote the same tested artifacts without rebuilding them after validation.

See [production release instructions](docs/PRODUCTION_RELEASE.md), [store listing copy](docs/STORE_LISTING_ES_EN.md), and the [release checklist](docs/RELEASE_READINESS_CHECKLIST.md).

## Contact

- Developer: **Bet0**
- Responsible party: **Alberto Lucchetta**, Argentina
- Support and privacy: **bet0.archscan@gmail.com**
- Published response target: 20 business days, without replacing any applicable legal deadlines.

No phone number or home address is published in this documentation.

## License

MIT. See [LICENSE](LICENSE).

---

# ARchScan — Español

**Relevamiento móvil de espacios, edición de planos 2D y exportación de documentación técnica para Android e iOS.**

ARchScan registra la geometría de ambientes mediante realidad aumentada compatible o un flujo básico con cámara de referencia e ingreso manual de medidas. Permite editar espacios conectados en un plano 2D común, conservar proyectos localmente y exportar documentación técnica.

> **Aviso sobre las medidas:** las mediciones móviles son orientativas. Verificá las dimensiones físicamente antes de utilizarlas en obra, presupuestos o decisiones profesionales.

## Estado de la versión

- **Candidata documentada:** `2.7.2+6`; esto no significa que esté publicada.
- **Distribución:** no está confirmada la publicación en Google Play ni App Store.
- **Alcance de la beta:** gratuita, sin anuncios, sin compras integradas y sin funciones bloqueadas.
- **Persistencia:** almacenamiento local con Drift/SQLite; sin cuentas ni sincronización propia en la nube.
- **Pro:** posible desbloqueo único futuro; todavía no está implementado ni disponible para comprar.
- **Requisitos previos a publicar:** validar los paquetes firmados definitivos, las pruebas físicas, las fichas de tienda y las declaraciones de privacidad.

La [auditoría final del repositorio](docs/FINAL_REPOSITORY_AUDIT.md) y la [lista de preparación](docs/RELEASE_READINESS_CHECKLIST.md) distinguen las comprobaciones automáticas de las pruebas en dispositivos y de los requisitos de las tiendas.

## Funciones

### Captura y continuidad de ambientes

- Basic Scanner con cámara de referencia y distancias ingresadas manualmente cuando no hay AR.
- ARCore en Android compatible y ARKit en dispositivos Apple compatibles.
- Esquinas, paredes, puertas, ventanas, cotas y relaciones entre paredes compartidas.
- Continuación de contornos abiertos desde sus extremos y creación de un ambiente nuevo entre esquinas seleccionadas de otro ambiente.
- Calibración de la continuación AR con vértices conocidos para alinear una nueva sesión.
- Deshacer/rehacer para las acciones compatibles de escaneo y edición.

### Editor de plano 2D

- Seleccionar y editar paredes y esquinas, arrastrar paredes y ajustar a puntos o paredes cercanos.
- Previsualizar y confirmar cierres válidos.
- Agregar y ubicar puertas y ventanas desde el plano general.
- Mover, rotar y alinear ambientes y grupos conectados.
- Desplazar y ampliar/reducir la vista del plano.
- Renombrar o cerrar un proyecto sin perder su identidad local ni los datos de sus ambientes.
- Proteger aberturas conectadas al editar paredes. El historial de edición pertenece a la sesión y no sustituye una copia de seguridad permanente.

### Importación y exportación

| Formato | Exportar | Importar |
|---|:---:|:---:|
| Proyecto JSON | Sí | Sí |
| SVG ARchScan con metadatos del proyecto | Sí | Sí* |
| Plano técnico PDF | Sí | No |
| DXF 2D para CAD | Sí | No |
| Imagen del plano PNG | Sí | No |
| Imagen del plano JPG | Sí | No |

- Los archivos se pueden guardar mediante el selector del dispositivo o compartir con aplicaciones instaladas.
- La importación SVG acepta únicamente metadatos válidos de proyectos ARchScan; rechaza SVG genéricos.
- La geometría se almacena internamente en metros. La interfaz permite unidades métricas e imperiales.
- DXF es 2D y no equivale a DWG. No se ofrece importación DXF ni exportación DWG.
- Los archivos exportados fuera de ARchScan quedan bajo el control de la persona usuaria y del destino elegido.

Consultá las [notas de DXF 2D](docs/dxf-2d.md) y la [guía del editor táctil](docs/plan-touch-editor.md).

## Privacidad y datos locales

ARchScan no requiere una cuenta ni ofrece un servicio propio de sincronización de proyectos. Los proyectos se guardan localmente con Drift/SQLite. Los archivos exportados o compartidos pueden guardarse fuera de la app, y la compartición puede crear copias temporales en caché.

Antes de desinstalar la aplicación o instalar una compilación firmada con otra clave, exportá los proyectos importantes a JSON y guardá la copia fuera de ARchScan. Desinstalar o borrar los datos de la aplicación puede eliminar los proyectos locales.

- [Política de privacidad](docs/PUBLIC_PRIVACY_POLICY.md)
- [Información sobre eliminación de datos locales](docs/ACCOUNT_DELETION_PAGE.md)
- [Auditoría de privacidad](docs/PRIVACY_DATA_AUDIT.md)

## Documentación y sitio web

- [Guía de uso — inglés primero, español después](docs/USER_GUIDE.md)
- [Texto revisado para Google Sites — inglés primero, español después](docs/WEBSITE_CONTENT_ES_EN.md)
- [Sitio público de ARchScan](https://sites.google.com/view/archscan/inicio)
- [Página de soporte](https://sites.google.com/view/archscan/soporte-support)
- [Página de privacidad](https://sites.google.com/view/archscan/privacidad-privacy)

El repositorio contiene el texto revisado para el sitio. Google Sites debe actualizarse y publicarse por separado; modificar el repositorio no publica automáticamente el sitio web.

## Arquitectura

| Paquete | Responsabilidad |
|---|---|
| `packages/room_scanner_core` | Modelos, geometría, persistencia Drift/SQLite, importación/exportación JSON/SVG y generación PDF/DXF |
| `packages/room_scanner_app` | Interfaz Flutter y estado, localización, cámara y adaptadores AR |

La persistencia utiliza Drift/SQLite. No reintroducir Isar.

## Desarrollo

Las versiones de herramientas definidas en CI y en los workflows de publicación son la referencia. Android utiliza Java 17; las compilaciones iOS requieren macOS, Xcode y CocoaPods.

Desde la raíz del repositorio:

```bash
cd packages/room_scanner_core
dart pub get
dart run build_runner build --delete-conflicting-outputs
dart analyze --fatal-infos
dart test

cd ../room_scanner_app
flutter pub get
flutter gen-l10n
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter run
```

Hay que regenerar el código de Drift y los recursos de localización cuando cambien sus fuentes. También se puede utilizar Melos según `melos.yaml`.

## Lista previa a la publicación

La entrega de Google Play es un **Android App Bundle firmado (.aab)**. Un APK de depuración sirve para instalar y probar la app, no como paquete final de publicación.

Antes de publicar:

1. Confirmar CI verde para el commit exacto de la versión.
2. Generar y verificar el AAB firmado; registrar SHA-256, identidad del paquete (`com.bet0.ARchScan`), versión/build, firma, permisos del manifiesto, bibliotecas nativas y compatibilidad con páginas de 16 KB.
3. Probar ese mismo artefacto en dispositivos Android objetivo, incluidos ARCore y la recuperación de permisos.
4. Preparar y verificar el artefacto iOS firmado en hardware compatible, incluidos ARKit/RoomPlan cuando estén disponibles.
5. Completar fichas, capturas de la compilación probada, declaraciones de privacidad, URLs de soporte y requisitos de beta.
6. Distribuir exactamente los artefactos probados, sin reconstruirlos después de la validación.

Consultar las [instrucciones de publicación](docs/PRODUCTION_RELEASE.md), las [fichas de tienda](docs/STORE_LISTING_ES_EN.md) y la [lista de preparación](docs/RELEASE_READINESS_CHECKLIST.md).

## Contacto

- Desarrollador: **Bet0**
- Responsable: **Alberto Lucchetta**, Argentina
- Soporte y privacidad: **bet0.archscan@gmail.com**
- Plazo de respuesta informado: 20 días hábiles, sin sustituir plazos legales aplicables.

Esta documentación no publica teléfono ni domicilio particular.

## Licencia

MIT. Consultá [LICENSE](LICENSE).
