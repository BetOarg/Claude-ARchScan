# Auditoría final del repositorio — ARchScan

**Última revisión:** 12/10/2026  
**Rama auditada:** `main`  
**Versión candidata documentada:** `2.7.2+6`

## Resultado ejecutivo

La auditoría automatizada de código y persistencia sigue avanzando con CI. Los PR #63–#67 quedaron fusionados: arrastre táctil/magnetismo, persistencia del ajuste y Undo, rollback de borrado de proyectos, reapertura de SQLite con metadatos de aberturas y rollback de reemplazo de instantáneas. La CI de cada PR pasó antes de fusionar. La CI posterior al merge del PR #67 debe comprobarse por separado antes de declarar verde `main`.

Este informe no certifica pruebas físicas ni artefactos firmados definitivos. No se ha declarado publicada la versión en Google Play o App Store.

## Estado del repositorio

- Backend de persistencia: Drift/SQLite; no reintroducir Isar.
- Los proyectos y habitaciones se conservan localmente.
- Las pruebas recientes cubren rollback de guardado/borrado, reapertura de archivos SQLite, geometría precisa, metadatos de puertas/ventanas y magnetismo táctil con Undo.
- Importar JSON/SVG ARchScan y exportar formatos están disponibles desde la pantalla de proyectos; la prueba manual en dispositivo sigue siendo necesaria.
- CI incluye análisis y pruebas, estructura de publicación, Android App Bundle de verificación e inspección de configuración iOS.
- El checklist de publicación es `docs/RELEASE_READINESS_CHECKLIST.md`.

## UX y funcionalidad

### Implementado en código

- Importación desde la pantalla inicial de proyectos y exportación seleccionando un proyecto.
- Selector de archivos sin filtro MIME restrictivo, validación de extensión JSON/SVG y límite de tamaño.
- Editor de plano común para Basic, ARCore y ARKit.
- Selección y arrastre táctil, ajuste a paredes/puntos, vista previa de cierre, edición de aberturas y Undo/Redo por sesión.
- Continuación de espacios mediante selección de aberturas y esquinas; la integración física sigue pendiente de comprobar.
- Marca de producto reutilizable `ArchScanLogo` con SVG y nombre accesible.

### Validación UX todavía necesaria

- Confirmar en un dispositivo real que el logotipo completo no queda recortado en la pantalla de inicio, en diferentes tamaños y proporciones.
- Probar importación desde proveedores Android/iOS, tanto desde memoria como desde ruta, y cancelar/seleccionar archivos inválidos.
- Probar exportación y compartir JSON, SVG, PDF, DXF, PNG y JPG, incluida la cancelación del menú y iPad.
- Probar arrastre/magnetismo táctil, Undo/Redo, selección de paredes compartidas, edición de puertas/ventanas y zoom en pantalla pequeña.
- Completar el recorrido de continuidad de escaneo entre habitaciones: seleccionar una abertura o esquina de otro ambiente, calibrar y cerrar el contorno sin alterar el espacio original.
- Verificar textos largos, español/inglés, accesibilidad, permisos, suspensión/reanudación y errores de cámara.

## Validación física final

- [ ] Repetir Basic y ARCore en el candidato final firmado.
- [ ] Validar ARKit en hardware compatible.
- [ ] Validar RoomPlan en hardware compatible.
- [ ] Primera apertura, permisos concedidos/denegados y recuperación.
- [ ] Escaneo, cierre, continuación desde aberturas/extremos y continuación entre habitaciones.
- [ ] Persistencia tras cerrar y reabrir; probar proyectos históricos.
- [ ] Edición 2D, magnetismo, puertas/ventanas, Undo/Redo, borrar pared/ambiente y conexiones.
- [ ] Importación/exportación de todos los formatos y compartir.
- [ ] Eliminación de datos locales y revisión de textos largos ES/EN.

## Artefactos y tiendas

- [ ] Confirmar secretos de firma de producción y keystore privado; nunca guardar claves en Git.
- [ ] Generar el AAB firmado definitivo y conservar su SHA-256.
- [ ] Auditar firma, manifiesto fusionado, permisos, SDK y bibliotecas nativas, incluida compatibilidad con páginas de 16 KB.
- [ ] Generar archive/IPA firmado definitivo y revisar firma/configuración Apple.
- [ ] Probar exactamente los artefactos que se enviarán, sin reconstruirlos entre validación y promoción.
- [ ] Confirmar que el build number no se reutiliza.
- [ ] Completar formularios de privacidad, ficha, capturas, países y condiciones de beta en ambas tiendas.
- [ ] Comprobar que las URL públicas de soporte y privacidad funcionan sin autenticación y coinciden con el binario.
- [ ] Mantener la beta gratuita, sin anuncios, compras integradas ni funciones bloqueadas.
- [ ] No crear tag ni publicar hasta tener evidencia completa y autorización explícita.

## Criterio de salida

La auditoría técnica se considera cerrada cuando la CI de `main` esté verde y las pruebas relevantes estén integradas. La preparación de publicación solo se cierra tras completar las validaciones físicas, verificar AAB/IPA firmados y alinear la ficha y las declaraciones de privacidad con los artefactos reales. La CI verde no sustituye esas comprobaciones.
