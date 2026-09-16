# Auditoría final del repositorio — ARchScan

**Fecha:** 16/09/2026  
**Rama auditada:** `main`  
**Commit auditado:** `b3cabb8249b7576e3a63188f7d75bc646c15e9f5`  
**Versión declarada:** `2.7.0+4`

## 1. Resultado de la auditoría

El estado de `main` es coherente para continuar con la preparación de publicación. El último cambio funcional de exportaciones técnicas está integrado y el workflow `ARchScan - CI Build Check` terminó correctamente para el mismo commit auditado.

La auditoría del repositorio no sustituye la validación física en dispositivos ni la auditoría del AAB/IPA firmado de producción.

## 2. Evidencia de integración

- PR #9, **Exportar planos técnicos coherentes en SVG, PDF, DXF, JPG y PNG**, fue fusionado el 16/09/2026 en `main`.
- El merge generó el commit `b3cabb8249b7576e3a63188f7d75bc646c15e9f5`.
- El CI del mismo commit terminó con conclusión `success`.
- El cambio conserva las mediciones originales en JSON y metadatos mientras normaliza la geometría técnica usada por las exportaciones.

## 3. Documentación revisada

La documentación de repositorio debe describir el estado real, sin presentar como completadas tareas que dependen de tiendas, firma de producción o pruebas físicas. Los documentos principales son:

- `README.md`: estado del producto, arquitectura, desarrollo, privacidad y preparación de tienda.
- `docs/USER_GUIDE.md`: guía funcional bilingüe.
- `docs/plan-touch-editor.md`: edición táctil y continuidad.
- `docs/dxf-2d.md`: contrato de exportación DXF.
- `docs/PUBLIC_PRIVACY_POLICY.md`: política pública.
- `docs/ACCOUNT_DELETION_PAGE.md`: eliminación de datos locales.
- `docs/PRIVACY_DATA_AUDIT.md`: inventario de privacidad.
- `docs/SECURITY_AUDIT.md`: controles de seguridad.
- `docs/GOOGLE_PLAY_FREEMIUM.md`: preparación comercial de Google Play.
- `docs/PRODUCTION_RELEASE.md`: procedimiento de publicación.
- `docs/STORE_LISTING_ES_EN.md`: textos de ficha ES/EN.
- `docs/APP_STORE_CHECKLIST.md`: preparación de App Store.
- `docs/RELEASE_READINESS_CHECKLIST.md`: matriz de salida y evidencia pendiente.

## 4. Seguridad y secretos

No se incorporan secretos de producción en la documentación. El repositorio contiene un auditor de patrones de secretos y las comprobaciones históricas registradas para la revisión de lanzamiento no encontraron credenciales reales en el historial.

La firma de producción, certificados, perfiles y credenciales de tienda deben permanecer fuera de Git y configurarse únicamente en los mecanismos seguros de CI/las consolas de las tiendas.

## 5. Ramas

Las ramas no principales actualmente visibles son:

- `codex/continuation-draft-stability`
- `codex/launch-readiness-fixes`
- `codex/readme-launch-docs`
- `feat/iso128-svg`
- `fix/arcore-surface-hit-measurement`
- `fix/final-launch-audit`
- `fix/local-data-draft-cleanup`
- `fix/ordered-project-persistence`
- `fix/scan-save-and-corner-boundary`

Las ramas asociadas a cambios ya fusionados deben eliminarse para dejar `main` como referencia de trabajo limpia. El conector disponible para esta auditoría permite verificar y modificar refs, pero no expone una operación de borrado de ramas; por tanto, **la eliminación física de estas refs queda como operación administrativa pendiente en GitHub** y no se simula moviendo las ramas a otro commit.

## 6. Estado de lanzamiento

### Integrado en `main`

- Escaneo Basic y flujo AR existente.
- Continuación de contornos y conservación de paredes/aberturas.
- Edición táctil y navegación del plano.
- Persistencia local y compatibilidad histórica documentada.
- Exportación JSON/SVG/PDF/DXF/PNG/JPG.
- Geometría técnica coherente entre formatos.
- Documentación de privacidad, soporte y eliminación de datos locales.
- Controles de accesibilidad y área segura documentados en las revisiones previas.

### Fuera del alcance de esta auditoría de repositorio

- Creación y custodia del keystore de producción.
- Play App Signing y configuración de Play Console.
- Certificados/perfiles de Apple y App Store Connect.
- AAB/IPA de producción y su auditoría de firma, permisos y bibliotecas nativas.
- Validación física final de ARKit y RoomPlan.
- Capturas y material definitivo de las tiendas.

## 7. Criterio de cierre

El repositorio queda técnicamente documentado y con `main` actualizado al último cambio funcional integrado y verificado por CI. Antes de una publicación real deben completarse únicamente las tareas externas y de validación física indicadas arriba, además de la limpieza administrativa de las ramas fusionadas.
