# Lista de preparación para publicación — ARchScan

**Última revisión:** 24/09/2026  
**Main:** `ae2e90ea5bb88a0ebf21ba9ab72e259bbaeef66f`  
**Versión declarada:** `2.7.0+4`

## Estado verificable en repositorio

- [x] Nombre visible ARchScan.
- [x] Android Application ID `com.bet0.ARchScan`.
- [x] iOS Bundle ID `com.bet0.ARchScan`.
- [x] Android API 36 y NDK 28.2.
- [x] ARCore opcional y fallback sin AR.
- [x] Localización Flutter en español e inglés.
- [x] Configuraciones iOS Debug, Profile y Release.
- [x] Firma Android release separada de debug.
- [x] Persistencia local.
- [x] Eliminación de proyectos locales.
- [x] Auditoría técnica de privacidad y seguridad.
- [x] JSON/SVG/PDF/DXF/PNG/JPG.
- [x] Exportaciones técnicas con cotas ordenadas de adentro hacia afuera.
- [x] Nombre del ambiente conservado como texto visible en el plano; sin leyendas/reportes redundantes.
- [x] CI con análisis, pruebas y verificaciones Android/iOS.
- [x] Cerrar proyecto y cambiar de proyecto sin cerrar la aplicación.
- [x] Renombrar proyectos conservando UUID y datos locales.
- [x] Cotas de puertas sin fragmentación redundante del muro.
- [x] Sitio público bilingüe, privacidad, soporte y eliminación de datos locales documentados.

## Estado administrativo

- [x] No hay PR abiertos.
- [ ] Eliminar físicamente la rama de trabajo fusionada que todavía aparece en GitHub: `fix/project-switch-rename-dimensions`.
- [ ] Proteger `main`.
- [ ] Activar eliminación automática de ramas fusionadas si se desea mantener el repositorio limpio.

La rama de trabajo restante es administrativa; no forma parte del artefacto de publicación.

## Validación física final

- [x] Basic validado previamente.
- [x] ARCore validado previamente.
- [ ] Repetir Basic y ARCore sobre el candidato final firmado.
- [ ] ARKit: validación física final.
- [ ] RoomPlan: validación física final.
- [ ] Primera apertura y permisos; denegación/recuperación.
- [ ] Escaneo, cierre y continuación desde aberturas o extremos.
- [ ] Puertas/ventanas, borrado de paredes y continuación.
- [ ] Suspensión/reanudación de cámara y orientación.
- [ ] Plano 2D, edición, navegación y rotación.
- [ ] Guardado, cierre y recuperación.
- [ ] Proyectos históricos.
- [ ] Importación/exportación JSON y SVG ARchScan.
- [ ] PDF, DXF, PNG y JPG.
- [ ] Compartir y cancelación del menú, incluido iPad.
- [ ] Eliminación de datos locales.
- [ ] Textos largos ES/EN, accesibilidad y ausencia de truncamiento.

## Artefactos de publicación

- [ ] Crear y custodiar keystore Android de producción fuera de Git.
- [ ] Configurar Play App Signing.
- [ ] Generar AAB firmado definitivo.
- [ ] Auditar firma, manifiesto fusionado, permisos, SDK y bibliotecas nativas, incluidas páginas de 16 KB.
- [ ] Generar archive/IPA firmado definitivo.
- [ ] Auditar firma y configuración de Apple.
- [ ] Confirmar que el build number no fue reutilizado.
- [ ] Probar el mismo artefacto que se enviará; no reconstruir entre validación y promoción.

## Tiendas y publicación

- [ ] Completar formularios de privacidad de Google Play y Apple según el artefacto final.
- [ ] Confirmar categoría, precio/estado gratuito y países de distribución.
- [ ] Confirmar política pública, soporte y eliminación de datos sin autenticación.
- [ ] Preparar capturas y material promocional reales.
- [ ] Verificar que README, sitio, fichas y binario describan la misma funcionalidad y permisos.
- [ ] Confirmar que la beta mantiene el alcance actual: gratuita, sin anuncios, sin IAP y sin funciones bloqueadas.

## Privacidad y soporte

La política debe seguir contemplando proyectos locales, exportaciones JSON/SVG/PDF/DXF/PNG/JPG y copias temporales de caché durante la compartición. ARchScan no crea cuentas, por lo que corresponde documentar eliminación de datos locales y no una página de borrado de cuenta.

## Respaldo y recuperación

1. Conservar SHA del lanzamiento, SHA-256 del AAB/IPA y auditorías de firma/permisos.
2. Conservar exportaciones JSON de los proyectos históricos usados en regresión.
3. Promover exactamente el artefacto probado.
4. Ante una regresión, detener distribución y crear el hotfix desde el tag del lanzamiento.
5. Incrementar el build number y repetir la auditoría completa.
6. No degradar esquemas Isar ni borrar proyectos al corregir.

## Criterio de salida

No enviar a revisión hasta que CI esté verde, el candidato firmado coincida con el artefacto probado, la matriz física tenga evidencia, las URL públicas funcionen sin autenticación, no existan secretos de producción en Git y las declaraciones de privacidad coincidan con el binario final.

La documentación del repositorio no puede certificar por sí sola la firma de producción, la configuración de las tiendas ni las pruebas físicas de ARKit/RoomPlan.
