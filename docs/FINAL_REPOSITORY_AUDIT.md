# Auditoría final del repositorio — ARchScan

**Fecha:** 16/09/2026  
**Rama auditada:** `main`  
**Commit funcional auditado:** `a445e4903af7a4ffa80464c7971a625861f3841e`  
**Versión declarada:** `2.7.0+4`

## Resultado

`main` contiene los cambios funcionales integrados hasta la ordenación profesional de cotas del PR #11. El usuario confirmó CI verde para ese candidato. La auditoría de repositorio no sustituye la validación física en dispositivos ni la auditoría de los artefactos firmados de producción.

## Integración funcional

- PR #9: exportaciones técnicas SVG/PDF/DXF/JPG/PNG.
- PR #10: separación profesional de cotas y conservación del nombre del ambiente como texto visible.
- PR #11: orden de cotas de adentro hacia afuera, cortas → intermedias → totales, con reserva de espacio para reducir cruces.
- Persistencia del proyecto y geometría almacenada no se modifican por la presentación técnica de las exportaciones.

## Documentación

La documentación principal existe en `README.md` y en `docs/`, incluyendo guía de uso, DXF, privacidad, seguridad, preparación de tiendas, publicación y checklist de salida.

## Seguridad y privacidad

El workflow incluye verificaciones de estructura de publicación y auditoría de secretos, permisos y almacenamiento local. No se deben incorporar al repositorio keystores, certificados, perfiles ni credenciales de producción.

La política pública contempla JSON/SVG/PDF/DXF/PNG/JPG y copias temporales de caché durante la compartición. Debe comprobarse que la URL pública accesible sin autenticación coincide con esta versión antes de enviar a revisión.

## Ramas

Al momento de esta revisión GitHub muestra `main` y dos ramas de trabajo que corresponden a PR ya fusionados:

- `fix/ordered-architectural-dimensions`
- `fix/professional-export-dimensions`

La eliminación física de estas ramas es administrativa. `main` no debe eliminarse ni moverse.

## Pendientes reales para publicación

### Repositorio

- Actualizar el checklist al commit actual.
- Proteger `main` con las reglas deseadas.
- Eliminar las ramas de trabajo fusionadas.
- Confirmar que no existan PR abiertos.

### Validación física

- Basic y ARCore: ya validados por el responsable; repetir sobre el candidato final después de generar el artefacto definitivo.
- ARKit y RoomPlan: falta validación física final.
- Probar persistencia, importación/exportación, borrado local, compartir y textos largos en el candidato final.

### Artefactos y tiendas

- Crear/custodiar keystore Android de producción y configurar Play App Signing.
- Generar AAB firmado definitivo y auditar firma, manifiesto, permisos, SDK y bibliotecas nativas.
- Generar archive/IPA firmado definitivo y auditar configuración de Apple.
- Completar formularios de privacidad de Google Play y Apple.
- Confirmar categoría, precio/estado gratuito y países de distribución.
- Preparar capturas y material definitivo.

## Criterio de cierre

ARchScan queda listo a nivel de código/documentación cuando el checklist y este informe coincidan con el commit final. La publicación solo queda cerrada después de validar físicamente el candidato final, auditar AAB/IPA firmados y completar la configuración externa de las tiendas.
