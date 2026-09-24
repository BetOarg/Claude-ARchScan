# Auditoría final del repositorio — ARchScan

**Fecha:** 24/09/2026  
**Rama auditada:** `main`  
**Commit funcional auditado:** `ae2e90ea5bb88a0ebf21ba9ab72e259bbaeef66f`  
**Versión declarada:** `2.7.0+4`

## Resultado

`main` contiene los cambios funcionales integrados hasta PR #50, incluyendo cambio de proyecto, renombrado local y corrección de cotas técnicas alrededor de puertas. El estado del repositorio es apto para continuar con la preparación de beta, pero la auditoría de repositorio no sustituye la validación física en dispositivos ni la auditoría de los artefactos firmados de producción.

## Integración funcional

- Exportaciones técnicas SVG/PDF/DXF/JPG/PNG.
- Separación profesional de cotas y conservación del nombre del ambiente como texto visible.
- Orden de cotas de adentro hacia afuera, cortas → intermedias → totales.
- Cerrar proyecto y volver a la lista de proyectos sin cerrar la aplicación.
- Renombrar proyectos conservando UUID, ambientes, geometría y datos locales.
- Evitar la cota redundante del fragmento de muro ocupado por una puerta.
- Persistencia del proyecto y geometría almacenada sin cambios por la presentación técnica de las exportaciones.

## Seguridad y privacidad

El workflow incluye verificaciones de estructura de publicación y auditoría de secretos, permisos y almacenamiento local. No se deben incorporar al repositorio keystores, certificados, perfiles ni credenciales de producción.

La política pública contempla JSON/SVG/PDF/DXF/PNG/JPG y copias temporales de caché durante la compartición. Debe comprobarse que la URL pública accesible sin autenticación coincide con esta versión antes de enviar a revisión.

## Ramas

GitHub muestra actualmente `main` y una rama de trabajo fusionada: `fix/project-switch-rename-dimensions`. Su eliminación es administrativa y no cambia el contenido de `main`.

## Pendientes reales para publicación

### Repositorio

- Proteger `main).
- Eliminar la rama de trabajo fusionada.
- Mantener el repositorio sin PR abiertos.
- Mantener el checklist sincronizado con el commit final.

### Validación física

- Basic y ARCore: repetir sobre el candidato final firmado.
- ARKit y RoomPlan: falta validación física final.
- Probar persistencia, importación/exportación, borrado local, compartir y textos largos en el candidato final.

### Artefactos y tiendas

- Crear/custodiar keystore Android de producción y configurar Play App Signing.
- Configurar los secretos de producción de GitHub sin almacenarlos en Git.
- Generar AAB firmado definitivo y auditar firma, manifiesto, permisos, SDK y bibliotecas nativas.
- Generar archive/IPA firmado definitivo y auditar configuración de Apple.
- Completar formularios de privacidad de Google Play y Apple.
- Confirmar categoría, precio/estado gratuito y países de distribución.
- Preparar capturas y material definitivo.

## Criterio de cierre

ARchScan queda listo a nivel de código/documentación cuando el checklist y este informe coincidan con el commit final. La publicación solo queda cerrada después de validar físicamente el candidato final, auditar AAB/IPA firmados y completar la configuración externa de las tiendas.
