# ARchScan

Relevamiento de espacios, edición de planos 2D y documentación técnica en Android e iOS.

ARchScan permite medir ambientes, paredes, puertas y ventanas; conectar espacios y conservar proyectos localmente. Selecciona ARCore o ARKit cuando el dispositivo es compatible, y Basic Scanner con cámara y medidas manuales cuando no dispone de realidad aumentada.

> Las mediciones móviles son orientativas. Verificá las dimensiones físicamente antes de utilizarlas en obra, presupuestos o documentación profesional. Una compilación en verde no sustituye las pruebas en dispositivos.

## Estado y modelo comercial

- Versión declarada: **2.7.0+4**. Núcleo de dominio: **1.0.0**.
- Candidato de beta abierta: gratuito, sin anuncios y sin compras integradas. La publicación depende del AAB/IPA firmado y de la configuración de las tiendas.
- Modelo previsto: **freemium sin anuncios**, con funciones locales esenciales gratuitas y un desbloqueo Pro opcional.
- **Pro todavía no está implementado ni a la venta.** Funciones, precio y modalidad de cobro requieren definición antes de integrar compras.
- No se agregaron límites a los proyectos ni bloqueos a las funciones existentes.
- No se declara publicación aprobada en Google Play ni App Store.

La preparación comercial y los pasos de Google Play están en [Freemium y Google Play](docs/GOOGLE_PLAY_FREEMIUM.md). La guía completa, primero en inglés y luego en español, está en [User Guide / Guía de uso](docs/USER_GUIDE.md).

## Funciones implementadas

### Escaneo y continuidad

- Basic Scanner para dispositivos sin ARCore/ARKit: cámara de referencia e ingreso manual de distancias y direcciones.
- Escaneo AR en dispositivos compatibles; el hardware y las condiciones del entorno afectan la precisión.
- Nombres libres para espacios y sugerencias rápidas; los nombres personalizados no se traducen.
- Puertas y ventanas con ancho, altura y antepecho; orientación de puertas conservada.
- El escaneo se concentra en medir el contorno. Puertas y ventanas se agregan
  después desde el plano general tocando su pared; este flujo es común a Basic,
  ARCore y ARKit.
- Continuación desde aberturas y referencia del plano anterior.
- Continuación de contornos abiertos desde cualquiera de sus extremos.
- Continuación desde ambientes cerrados mediante selección táctil de la esquina
  inicial y la esquina final. El recorrido crea un ambiente nuevo y conserva
  intactos el ambiente original, sus aberturas y la pared compartida.
- En ARCore/ARKit, calibración con el vértice anterior y el vértice inicial para conservar traslación, orientación y paredes inclinadas al reanudar una sesión.
- Deshacer/rehacer del escaneo y protección frente a aberturas que pierden su pared.

### Plano general compartido

Las siguientes herramientas se aplican a proyectos provenientes de Basic, ARCore y ARKit:

- Tocar una pared o esquina para seleccionarla y editar sobre el mismo plano.
- Arrastrar paredes en paralelo y mover esquinas con ajuste a puntos o paredes cercanos.
- Modificar longitudes con vista previa y confirmación.
- Borrar paredes sin dibujar un cierre inexistente; conservar los fragmentos abiertos.
- Proponer un cierre válido al punto o pared cercano mostrando el recorrido completo.
- Botones de ambientes registrados, puerta, ventana, deshacer y rehacer.
- Ubicación táctil de aberturas sobre paredes reales, incluida la pared de cierre.
- Movimiento y rotación de ambientes, grupos conectados y alineación de paredes.
- Navegación con dos dedos y controles de acercar, alejar y restablecer la vista
  para mantener visible el plano durante la edición.
- Acciones organizadas en pares consistentes: puerta/ventana y deshacer/rehacer.
- Detección de paredes compartidas completas y parciales.
- Historial reversible de edición; los contornos abiertos no suman superficie.

Las conexiones se protegen: no se desplaza silenciosamente una abertura conectada al editar su pared. El historial de edición es por sesión, no una copia de seguridad permanente. Consultá la [guía de edición táctil](docs/plan-touch-editor.md).

### Archivos y unidades

| Formato | Exportar | Importar | Contenido |
|---|:---:|:---:|---|
| JSON | Sí | Sí | Proyecto, puntos, medidas, aberturas y conexiones |
| SVG | Sí | Sí* | Plano vectorial editable y respaldo ARchScan embebido |
| PDF | Sí | No | Plano vectorial e informe técnico |
| DXF 2D | Sí | No | Geometría editable para herramientas CAD |
| PNG | Sí | No | Imagen del plano en alta resolución |
| JPG | Sí | No | Imagen del plano con fondo blanco |

- Todos los formatos se pueden **guardar en Archivos** o **compartir** mediante las aplicaciones instaladas.
- Los archivos guardados fuera de ARchScan permanecen en el dispositivo aunque se desinstale la aplicación.
- *La importación SVG acepta únicamente archivos con metadatos ARchScan válidos; los SVG genéricos se rechazan sin modificar el proyecto abierto.
- Los proyectos y el JSON conservan coordenadas internas en **metros**.
- La interfaz permite sistema métrico o imperial con preferencia persistente.
- El DXF en español exporta en metros; en inglés, las coordenadas se convierten a pulgadas y las cotas se muestran en pies/pulgadas. No se modifica el proyecto original.
- DXF no es DWG: la conversión posterior depende del programa CAD.
- No se ofrece importación DXF ni georreferenciación topográfica.
- Detalles: [DXF 2D](docs/dxf-2d.md).

## Privacidad y proyectos históricos

ARchScan no requiere cuenta ni sincronización propia en la nube. Guarda los proyectos localmente con Isar. JSON, SVG, PDF, DXF, PNG y JPG pueden guardarse fuera de la app o compartirse; su ubicación queda bajo control del usuario.

No incorpora SDK publicitario ni compras integradas en sus dependencias directas actuales. Antes de publicar debe auditarse también el artefacto final y sus dependencias transitivas.

Se conserva el formato histórico y el orden de las enumeraciones persistidas. Antes de instalar una versión con otra firma o desinstalar la app, exportá los proyectos a JSON o SVG y guardalos fuera de ARchScan. Una actualización de prueba a Google Play puede requerir reinstalación por diferencia de firmas: **no desinstales sin copia**.

- Sitio público bilingüe: [ARchScan](https://sites.google.com/view/archscan/inicio)
- [Política de privacidad](docs/PUBLIC_PRIVACY_POLICY.md)
- [Eliminación de datos locales](docs/ACCOUNT_DELETION_PAGE.md)
- [Auditoría de privacidad](docs/PRIVACY_DATA_AUDIT.md)

## Arquitectura

| Paquete | Responsabilidad |
|---|---|
| `packages/room_scanner_core` | Modelos, geometría, persistencia Isar y exportaciones/importaciones JSON/SVG, PDF y DXF |
| `packages/room_scanner_app` | Flutter, estado, pantallas, localización, cámara y adaptadores AR |

Las herramientas de geometría y el editor común no dependen del modo de captura. Basic, ARCore y ARKit comparten el modelo del plano y las herramientas posteriores; RoomPlan se integra como captura nativa compatible cuando está disponible. La disponibilidad y precisión dependen del dispositivo.

## Desarrollo

- Flutter **3.35.0 o superior**, conforme a `pubspec.yaml`; usar una versión compatible con las dependencias resueltas.
- Java 17 para Android; macOS/Xcode y CocoaPods para iOS.
- Android: mínimo API 28, compilación y destino API 36; ARCore opcional.
- Identificadores actuales: Android e iOS `com.bet0.ARchScan`. No cambiarlos al publicar sin evaluar identidad de tienda y compatibilidad de actualizaciones.

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

Los archivos generados de Isar y localización se regeneran antes de compilar. También se puede utilizar Melos según `melos.yaml`.

## Preparación para Google Play

La entrega de tienda es un **Android App Bundle firmado (.aab)**, no el APK de depuración. El repositorio separa la firma de pruebas y la de producción.

1. Verificar en Play Console las URL públicas de soporte y privacidad del [sitio oficial](https://sites.google.com/view/archscan/inicio), y completar ficha, capturas y formularios.
2. Configurar la clave de carga privada y Play App Signing; nunca usar el keystore público de pruebas.
3. Asignar un `versionCode` no utilizado, superior al de la entrega anterior.
4. Verificar API objetivo, permisos del manifiesto fusionado y compatibilidad de bibliotecas nativas con páginas de 16 KB.
5. Probar el AAB instalado desde el canal de pruebas, incluyendo importación de proyectos históricos.
6. Completar los requisitos de pruebas y acceso a producción que correspondan a la cuenta.

Ver [guía de publicación](docs/PRODUCTION_RELEASE.md), [lista de preparación](docs/RELEASE_READINESS_CHECKLIST.md) y [fichas ES/EN](docs/STORE_LISTING_ES_EN.md).

No se ejecutan ni supervisan workflows automáticamente como parte de esta documentación. Los secretos de firma, la cuenta de Play Console y la aprobación de Google requieren intervención del titular.

## Estado de lanzamiento

El titular confirmó el funcionamiento de los flujos principales y el último CI quedó verde. Las correcciones de persistencia, continuación entre esquinas, conservación de paredes, navegación del plano, acciones 2×2, compartir en iPad e importación segura están integradas en `main`.

Antes de enviar la beta a revisión todavía corresponde:

- crear y custodiar la clave privada de carga de Android;
- configurar los cuatro secretos de firma en GitHub Actions;
- generar el AAB firmado mediante `ARchScan - Android Store Build` y conservar su auditoría;
- comprobar en el AAB final firma, permisos, versión y bibliotecas nativas de 16 KB;
- configurar Play App Signing, ficha, Seguridad de los datos, clasificación, países y canal de prueba;
- preparar capturas obtenidas de la compilación final;
- para iOS, configurar certificados, perfil, Team ID y App Store Connect antes de generar el IPA;
- mantener públicas y coherentes las páginas de soporte, privacidad, eliminación local y guía de uso.

Un CI verde demuestra que el código compila y pasa las pruebas automatizadas configuradas; no equivale a una aprobación de Google Play o App Store.

## Contacto

- Desarrollador: **Bet0**.
- Responsable: **Alberto Lucchetta**, República Argentina.
- Soporte: **support.ARchScan@gmail.com**.
- Privacidad: **bet0.archscan@gmail.com**.
- Plazo de respuesta informado: **20 días hábiles**, sin sustituir plazos legales aplicables.

No se publican teléfono ni domicilio en estos documentos. Play Console puede requerir información adicional al titular según el tipo de cuenta y los países de distribución.

## Contribuciones y licencia

Preservá proyectos históricos, no publiques secretos y agregá pruebas para los cambios de geometría, persistencia y unidades. Los textos de interfaz deben utilizar gen-l10n en español e inglés.

Código distribuido bajo [licencia MIT](LICENSE). La preparación freemium no cambia la licencia del repositorio.
