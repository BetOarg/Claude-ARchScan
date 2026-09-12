# Publicación de ARchScan

## Modelo de datos

ARchScan funciona sin cuenta y guarda los proyectos únicamente en el dispositivo. Las compilaciones no requieren configuración, claves ni servicios de backend. JSON, SVG, PDF, DXF, PNG y JPG se exportan solo por decisión del usuario.

## Modelo comercial

Versión actual gratuita, sin anuncios y sin compras. Freemium con Pro opcional previsto, no activado. Definir funciones, modalidad y precio antes de integrar cobros. Ver [Google Play y freemium](GOOGLE_PLAY_FREEMIUM.md).

## Android

Antes de publicar:

- confirmar `applicationId "com.bet0.ARchScan"`;
- verificar `targetSdkVersion 36` y compatibilidad de todas las bibliotecas nativas con páginas de 16 KB;
- asignar un número de compilación no utilizado en Play Console;
- configurar Play App Signing y una clave de carga de producción;
- ejecutar análisis, pruebas y `flutter build appbundle --release`;
- probar guardado, cierre, reapertura, eliminación local e importación/exportación.

El workflow `release_android.yml` requiere únicamente los secretos de firma Android.

## iOS

Antes de publicar:

- confirmar Bundle ID `com.bet0.ARchScan`;
- configurar el equipo, certificado de distribución y perfil de aprovisionamiento;
- ejecutar análisis, pruebas y compilación iOS sin firma;
- generar el IPA firmado mediante `release_ios.yml`;
- validar permisos, Privacy Manifest y funcionamiento físico.

## Privacidad y tiendas

- publicar la política de privacidad con URL estable y pública;
- publicar la página de eliminación de datos locales;
- declarar que ARchScan no crea cuentas ni sincroniza proyectos;
- confirmar que no recopila ubicación, fotografías, videos, publicidad ni seguimiento;
- responsable: Alberto Lucchetta (Bet0), República Argentina;
- soporte: support.ARchScan@gmail.com; privacidad: bet0.archscan@gmail.com;
- verificar SDK transitivos y copias del sistema antes de completar Seguridad de los datos.

## Verificación final

Ejecutar desde la raíz:

- `dart run packages/room_scanner_app/tool/verify_store_readiness.dart --strict`;
- `dart run packages/room_scanner_app/tool/security_audit.dart`;
- las pruebas de la compilación firmada en dispositivos. Los workflows existentes se ejecutan por decisión del titular; esta preparación no los consulta ni dispara.

El verificador no certifica firma, URLs accesibles, compatibilidad binaria ni aprobación de tienda.

No publicar hasta que todas las compilaciones estén verdes y las URLs públicas coincidan con la funcionalidad real.


## Límites y verificación de exportaciones

La importación admite JSON y SVG producido por ARchScan con metadatos. Límite: 10 MiB, 1000 ambientes, 10000 puntos y 10000 aberturas. El análisis de archivos se ejecuta fuera del hilo de interfaz en dispositivos móviles. Probar cancelación, compartir en iPad y coherencia del idioma de PDF/SVG/DXF. Los archivos externos y las copias temporales compartidas no se eliminan al borrar un proyecto.
