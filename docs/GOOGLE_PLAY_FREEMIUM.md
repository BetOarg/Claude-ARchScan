# ARchScan: freemium sin anuncios y Google Play

Fecha de revisión documental: 28 de agosto de 2026. No equivale a aprobación de Google.

## 1. Estado real

La compilación actual 2.7.0+4 es gratuita, sin anuncios ni compras integradas. El freemium es el modelo previsto: base local gratuita más un desbloqueo Pro opcional. Todavía no existe integración de cobro, restauración ni validación de compras. No ofrecer un producto Pro ni anunciarlo como disponible con esta compilación.

No se cambian identificadores, licencia MIT, datos históricos ni acceso a funciones existentes para preparar la publicación.

## 2. Decisiones necesarias antes de implementar Pro

El titular debe aprobar:

- funciones nuevas que serán Pro y funciones esenciales que seguirán gratuitas;
- compra única o suscripción, precio y países;
- política de acceso de usuarios beta e históricos;
- alcance Android/iOS de la compra: no prometer que una compra de Google se restaura automáticamente en Apple.

Recomendación pendiente de aprobación: mantener gratuitos el acceso a proyectos guardados, recuperación y copias JSON, y reservar funciones avanzadas nuevas para Pro. No imponer límites retroactivos sobre datos existentes.

Después de esa definición, implementar un servicio de derechos de acceso compartido, compra, restauración y estados pendiente/cancelado/reembolsado. Un booleano en preferencias no acredita una compra. Los proyectos pueden seguir siendo locales aunque la transacción necesite Internet.

Los cobros por funciones digitales deben ajustarse a la [política de pagos de Google Play](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en). Integrar Google Play Billing como vía estándar; no añadir enlaces de pago alternativos sin evaluar las condiciones aplicables. Actualizar privacidad y Seguridad de los datos antes de activar compras.

## 3. Preparación de Android ya presente

- Application ID: `com.bet0.ARchScan`; conservar exactamente.
- minSdk 28; compileSdk y targetSdk 36.
- Android Gradle Plugin 8.13.2 y NDK 28.2.13676358.
- ARCore opcional, cámara opcional para instalación y permiso solicitado al utilizarla.
- Firma release separada de la clave pública de pruebas.
- No hay dependencias directas publicitarias ni de compras en pubspec.

API 36 coincide con el objetivo indicado por la [guía oficial de nivel API](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en); volver a revisar la exigencia al enviar.

**Pendiente crítico:** comprobar páginas de 16 KB de todas las bibliotecas nativas incluidas en el AAB, especialmente Flutter, AR y cualquier otra biblioteca nativa transitiva. Elegir un NDK reciente no recompila ni garantiza la alineación de bibliotecas precompiladas de terceros. Seguir la [verificación oficial de 16 KB](https://developer.android.com/guide/practices/page-sizes), inspeccionar ELF/ZIP y probar el APK generado en un entorno de 16 KB. No marcar este punto como aprobado por tener CI verde. Si una dependencia falla, planificar actualización o migración con copia y pruebas de proyectos históricos.

## 4. Firma y entrega

1. Confirmar la cuenta de desarrollador y su verificación en Play Console.
2. Configurar Play App Signing y custodiar una clave privada de carga. No subir secretos al repositorio ni usar la clave pública de pruebas.
3. Configurar los secretos/entradas que solicita el workflow existente `release_android.yml`. Esta guía no lo ejecuta ni consulta sus resultados.
4. Elegir un número de compilación no usado en Play Console. El `+4` actual no garantiza que esté disponible.
5. Generar AAB de release y comprobar su firma y manifiesto final.
6. Subir primero al canal de pruebas correspondiente, no directamente a producción.

Para una compilación local con las dependencias y el código generado ya preparados:

```bash
cd packages/room_scanner_app/android
./gradlew :app:verifyProductionSigning
cd ..
flutter build appbundle --release
```

Salida habitual: `build/app/outputs/bundle/release/app-release.aab`. Sin `key.properties` la configuración permite una compilación sin firma: ese archivo no es una entrega publicable. La verificación de propiedades no sustituye comprobar el certificado real.

Antes de pasar del APK de pruebas a Google Play, exportar JSON. Una firma distinta puede impedir actualizar sobre la instalación anterior.

## 5. Ficha y formularios

- Nombre: ARchScan. Desarrollador visible: Bet0.
- Descarga: gratuita. Publicidad: No, sujeto a auditoría del manifiesto fusionado y SDK finales.
- Compras: no anunciar ni configurar Pro como disponible hasta integrarlo y probarlo.
- Soporte: support.ARchScan@gmail.com.
- Privacidad: bet0.archscan@gmail.com.
- Responsable: Alberto Lucchetta, República Argentina.
- Categoría sugerida: Productividad, pendiente de confirmación.
- URLs públicas de privacidad y soporte: pendientes; no inventar dominios ni presentar Markdown de GitHub como web ya publicada.
- Preparar capturas reales de la misma compilación, icono y gráfico promocional conforme a los campos de Play Console.
- Completar clasificación de contenido, público objetivo, acceso a la app y países; no inventar respuestas.

Seguridad de los datos debe reflejar el AAB y todos sus SDK, no solo el código propio. Incluso una app sin recopilación debe completar el formulario y proporcionar privacidad pública, según la [guía oficial](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en). No seleccionar automáticamente “No se recopilan datos” sin auditoría. No hay cuenta ARchScan: no inventar credenciales para revisión.

## 6. Canal de pruebas

Empezar con pruebas internas y continuar según las condiciones de la cuenta. Para cuentas personales creadas después del 13 de noviembre de 2023, Google indica una prueba cerrada con al menos 12 participantes inscritos durante 14 días continuos antes de solicitar acceso a producción. El acceso a pruebas abiertas depende de obtener acceso a producción. Confirmar la situación real de la cuenta en la [guía de pruebas de Google](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en).

No se presume que la cuenta del titular pertenezca a esa categoría ni que ya cumpla los requisitos.

## 7. Criterio de entrega

No enviar a producción hasta comprobar firma, 16 KB, URLs, formularios, proyectos históricos y funcionamiento físico de Basic/ARCore. Los fallos de cierre, aberturas o continuidad deben resolverse, no ocultarse.

El verificador del repositorio solo revisa estructura y documentación. No accede a Play Console, no valida compras y no certifica el AAB.

