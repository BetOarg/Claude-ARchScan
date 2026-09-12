# Lista de preparación para publicación — ARchScan

## Exportaciones implementadas

- JSON y SVG de ARchScan permiten recuperar el proyecto con sus metadatos.
- PDF, DXF 2D, PNG y JPG permiten entregar el plano.
- Guardar en Archivos y Compartir son destinos disponibles.
- Revalidar todos los formatos y compartir en iPad con la compilación firmada final.

## Estado verificable en repositorio

- [x] Nombre visible ARchScan.
- [x] Android Application ID `com.bet0.ARchScan`.
- [x] iOS Bundle ID `com.bet0.ARchScan`.
- [x] Android API 36 y NDK 28.2.
- [x] ARCore opcional y fallback sin AR.
- [x] Localización Flutter en español e inglés.
- [x] Permiso de cámara iOS localizado.
- [x] Configuraciones iOS Debug, Profile y Release.
- [x] Firma Android release separada de debug.
- [x] Persistencia exclusivamente local verificada en el cliente.
- [x] Eliminación de todos los proyectos locales implementada.
- [x] Auditoría técnica de privacidad.
- [x] Borradores de fichas y textos web.
- [x] Workflow manual separado que genera únicamente el APK de prueba.
- [x] El APK de prueba incluye informe de SHA-256, paquete, versión, SDK, permisos y certificado.
- [x] El workflow AAB firmado conserva manifiesto fusionado, permisos y auditoría de páginas de 16 KB.

## Configuración externa pendiente

- [x] Responsable y contactos confirmados: Alberto Lucchetta (Bet0), Argentina; soporte y privacidad en README.
- [x] Modelo previsto freemium sin anuncios documentado; Pro no activado.
- [ ] Definir funciones Pro, precio y tipo de compra antes de integrar cobros (posterior a esta beta).
- [ ] Revisar conservación de consultas de soporte y políticas del artefacto final.
- [x] Sitio público bilingüe publicado: https://sites.google.com/view/archscan/inicio
- [x] Política de privacidad y soporte publicados dentro del sitio oficial.
- [x] Instrucciones de eliminación de datos locales publicadas.
- [x] No corresponde una página de eliminación de cuenta: ARchScan no crea cuentas.
- [ ] Probar borrado local, desinstalación e importación/exportación.
- [ ] Crear y custodiar el keystore Android de producción.
- [ ] Configurar Play App Signing.
- [ ] Configurar Apple Development Team.
- [ ] Incorporar certificados y perfiles fuera de Git.
- [ ] Completar formularios de privacidad de Google y Apple.
- [ ] Confirmar categoría, precio y países de distribución.
- [ ] Preparar capturas reales y material promocional.

## Matriz de pruebas físicas

| Caso | ARCore | ARKit | Basic | Resultado |
|---|:---:|:---:|:---:|---|
| Primera apertura y permiso de cámara | ✓ | ✓ | ✓ | [ ] |
| Denegación y recuperación del permiso | ✓ | ✓ | ✓ | [ ] |
| Escaneo y cierre de un ambiente | ✓ | ✓ | ✓ | [ ] |
| Puerta y ventana sobre pared de cierre | ✓ | ✓ | ✓ | [ ] |
| Continuación desde una abertura | ✓ | ✓ | ✓ | [ ] |
| Continuación desde ambos extremos de un contorno abierto | ✓ | ✓ | ✓ | [ ] |
| Pared inclinada: calibración con vértice anterior e inicial | ✓ | ✓ | N/A | [ ] |
| Borrar una pared y continuar el escaneo | ✓ | ✓ | ✓ | [ ] |
| Cerrar contra el punto o pared válidos más cercanos | ✓ | ✓ | ✓ | [ ] |
| Eliminar ambiente completo, incluso sin paredes | ✓ | ✓ | ✓ | [ ] |
| Suspensión y reanudación de cámara | ✓ | ✓ | ✓ | [ ] |
| Ausencia de pantalla roja en cierre y diálogos | ✓ | ✓ | ✓ | [ ] |
| Cambio de orientación | ✓ | ✓ | ✓ | [ ] |
| Plano 2D, edición y rotación | ✓ | ✓ | ✓ | [ ] |
| Guardado, cierre y recuperación | ✓ | ✓ | ✓ | [ ] |
| Apertura de proyectos históricos | ✓ | ✓ | ✓ | [ ] |
| Importación y exportación JSON | ✓ | ✓ | ✓ | [ ] |
| PDF técnico y DXF 2D | ✓ | ✓ | ✓ | [ ] |
| Eliminación de datos locales | ✓ | ✓ | ✓ | [ ] |
| Textos largos en español e inglés | ✓ | ✓ | ✓ | [ ] |

## Auditoría de lanzamiento — 12/09/2026

- [x] PR #4 de estabilidad de continuaciones fusionado tras CI verde.
- [ ] Comprobar CI del nuevo candidato de lanzamiento.
- [ ] Probar Compartir en iPad y cancelación del menú.
- [ ] Verificar límites de importación (10 MiB, 1000 ambientes, 10000 puntos y 10000 aberturas).
- [ ] Probar PDF usando el idioma efectivo de la aplicación.
- [ ] Publicar la política actualizada con SVG, PNG/JPG y caché de archivos compartidos.
- [ ] Confirmar en Play Console/App Store Connect que el build 4 todavía está disponible; incrementar si ya se utilizó.
- [ ] Completar evidencia física separada para Basic, ARCore, ARKit y RoomPlan; la confirmación del usuario cubre únicamente lo que probó.

## Criterio de salida

No enviar a revisión hasta que todos los jobs de CI estén verdes, la compilación firmada coincida con la probada, no queden placeholders, la matriz física tenga evidencia, las URL públicas sean accesibles sin autenticación y la eliminación local funcione. La página web explica cómo eliminar datos y contactar a soporte; no ofrece borrado remoto de proyectos.

## Bloqueos de Google Play que CI no certifica

- [x] URL de sitio, privacidad, eliminación local y soporte publicadas; revalidar acceso sin autenticación justo antes de enviar la ficha.
- [ ] AAB firmado con clave privada de carga y versión no reutilizada.
- [ ] Bibliotecas nativas (incluidos Flutter, Isar y AR) verificadas para páginas de 16 KB en el artefacto final.
- [ ] Permisos fusionados y SDK transitivos auditados; declaración Sin anuncios comprobada.
- [ ] Formulario Seguridad de los datos coherente con la compilación enviada.
- [ ] Tipo de cuenta, pruebas exigidas y acceso a producción confirmados en Play Console.
- [ ] APK de Google Play probado con proyectos históricos después de exportar una copia JSON.

Ver [guía específica](GOOGLE_PLAY_FREEMIUM.md). Una compilación verde no marca automáticamente estas casillas.

## Artefactos y workflows

- **APK de prueba:** ejecutar manualmente `Build Android APK`. Genera solamente un APK debug con firma fija de pruebas y su carpeta de auditoría; no genera AAB.
- **AAB de tienda:** ejecutar manualmente `ARchScan - Android Store Build` con los secretos de producción. Genera el AAB firmado y su auditoría; no debe utilizarse para distribuir el APK de prueba.
- No ejecutar ambos artefactos en un mismo job. Esto evita repetir compilaciones y reduce el uso de espacio del runner.
- La firma del APK de prueba no reemplaza el keystore privado de carga ni Play App Signing.
