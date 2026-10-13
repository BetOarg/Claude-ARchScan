# ARchScan — Google Sites copy (English first, Spanish second)

**Purpose:** reviewed source copy for the public Google Sites pages. Keep each language in a separate section; do not alternate languages paragraph by paragraph.

**Review date:** 13 October 2026  
**Documented candidate:** 2.7.2+6  
**Important:** this candidate has not been certified as a final store release. Do not label it “published”, “approved”, or “available on Google Play/App Store” until that is verified.

## Page: Home / Inicio

### English

# ARchScan
**Measure spaces. Build clear 2D plans. Export technical drawings.**

ARchScan is a mobile space-surveying and floor-plan editing app for Android and iOS. On compatible devices, it can use augmented reality. When AR is unavailable, Basic Scanner provides camera guidance and manual measurement entry.

**What you can do**
- Capture room corners and create room outlines.
- Edit walls, corners, dimensions, doors, and windows in a shared 2D plan.
- Continue a room from an open contour or create a new room between selected corners of an existing room.
- Move, align, and organize rooms and connected groups.
- Undo or redo supported editing actions.
- Save projects locally and return to them later.
- Export project data as JSON or ARchScan SVG, and export technical plans as PDF, 2D DXF, PNG, or JPG.

**Import and export**
JSON projects and ARchScan SVG files with valid embedded project metadata can be imported. PDF, DXF, PNG, and JPG are export formats only. Generic SVG files and DXF imports are not supported. DXF output is 2D and is not a DWG file.

**Privacy by design**
ARchScan does not require an account or operate its own cloud-sync service. Projects are stored locally on the device. Exported files and files shared with other apps are controlled by the user and the selected destination. Sharing may create temporary cache copies.

**Beta and release status**
The documented candidate is 2.7.2+6. This does not mean the candidate has been published or approved by either store. The planned beta is free, without ads, in-app purchases, or locked features. A future optional Pro unlock has not been implemented or made available for purchase.

**Measurement notice**
Mobile measurements are indicative. Verify dimensions physically before using them for construction, estimates, or professional decisions.

**Links**
- User Guide: [link to the existing User Guide page]
- Support: https://sites.google.com/view/archscan/soporte-support
- Privacy: https://sites.google.com/view/archscan/privacidad-privacy
- Local data deletion: include this section on the Privacy page; ARchScan has no user accounts to delete.

### Español

# ARchScan
**Medí espacios. Creá planos 2D claros. Exportá dibujos técnicos.**

ARchScan es una aplicación móvil de relevamiento de espacios y edición de planos para Android e iOS. En dispositivos compatibles puede utilizar realidad aumentada. Cuando la AR no está disponible, Basic Scanner ofrece una guía con cámara e ingreso manual de medidas.

**Qué podés hacer**
- Registrar esquinas y crear contornos de ambientes.
- Editar paredes, esquinas, cotas, puertas y ventanas en un plano 2D común.
- Continuar un ambiente desde un contorno abierto o crear uno nuevo entre esquinas seleccionadas de otro ambiente.
- Mover, alinear y organizar ambientes y grupos conectados.
- Deshacer o rehacer las acciones de edición compatibles.
- Guardar proyectos localmente y retomarlos más adelante.
- Exportar datos de proyecto como JSON o SVG ARchScan, y planos técnicos como PDF, DXF 2D, PNG o JPG.

**Importación y exportación**
Se pueden importar proyectos JSON y archivos SVG ARchScan con metadatos válidos del proyecto. PDF, DXF, PNG y JPG solo se exportan. No se admiten SVG genéricos ni importación DXF. El DXF es 2D y no equivale a un archivo DWG.

**Privacidad**
ARchScan no requiere una cuenta ni ofrece sincronización propia en la nube. Los proyectos se guardan localmente en el dispositivo. Los archivos exportados o compartidos quedan bajo el control de la persona usuaria y del destino elegido. La compartición puede crear copias temporales en caché.

**Estado de la beta**
La candidata documentada es 2.7.2+6. Esto no significa que esté publicada ni aprobada por las tiendas. La beta prevista es gratuita, sin anuncios, compras integradas ni funciones bloqueadas. Un posible desbloqueo Pro futuro todavía no está implementado ni disponible para comprar.

**Aviso sobre las medidas**
Las mediciones móviles son orientativas. Verificá las dimensiones físicamente antes de utilizarlas en obra, presupuestos o decisiones profesionales.

**Enlaces**
- Guía de uso: [enlace a la página existente de Guía de uso]
- Soporte: https://sites.google.com/view/archscan/soporte-support
- Privacidad: https://sites.google.com/view/archscan/privacidad-privacy
- Eliminación de datos locales: incluir esta sección en la página de Privacidad; ARchScan no tiene cuentas de usuario que deban eliminarse.

## Page: User Guide / Guía de uso

### English — required corrections

Update the guide metadata to:
- **Guide version:** documentation for candidate 2.7.2+6; not a claim of store release.
- **Last updated:** 13 October 2026.

Keep the existing detailed instructions, but ensure they do not imply physical validation of the final signed candidate. Preserve these distinctions:
- Basic Scanner uses manual distances; the camera is a visual reference.
- ARCore and ARKit depend on compatible hardware and conditions.
- RoomPlan must only be described as available on compatible Apple hardware where the integration is present.
- Doors and windows are added from the overall floor plan, not during contour scanning.
- Import: JSON and ARchScan SVG with valid project metadata.
- Export: JSON, SVG, PDF, DXF 2D, PNG, JPG.
- DXF import and DWG export are not available.
- Projects are local. Export a JSON backup before uninstalling or installing a build signed with a different key.
- Undo/redo history is not a permanent backup.
- Mobile measurements must be physically verified.

### Español — correcciones requeridas

Actualizar los metadatos de la guía:
- **Versión de la guía:** documentación para la candidata 2.7.2+6; no afirma que esté publicada en las tiendas.
- **Última actualización:** 13 de octubre de 2026.

Conservar las instrucciones detalladas y no afirmar que la candidata final firmada ya fue validada físicamente. Mantener estas distinciones:
- Basic Scanner requiere ingresar distancias manualmente; la cámara es una referencia visual.
- ARCore y ARKit dependen de hardware compatible y de las condiciones del entorno.
- RoomPlan solo debe describirse como disponible en hardware Apple compatible cuando la integración esté presente.
- Las puertas y ventanas se agregan desde el plano general, no durante el trazado del contorno.
- Importación: JSON y SVG ARchScan con metadatos válidos del proyecto.
- Exportación: JSON, SVG, PDF, DXF 2D, PNG y JPG.
- No se ofrece importación DXF ni exportación DWG.
- Los proyectos son locales. Exportar una copia JSON antes de desinstalar o instalar una compilación firmada con otra clave.
- El historial de deshacer/rehacer no es una copia de seguridad permanente.
- Las medidas móviles deben verificarse físicamente.

## Page: Support / Soporte

### English

**Support — ARchScan**

For support, report the app version, device model, operating-system version, steps to reproduce the issue, and screenshots or logs when available. Do not send confidential floor plans or personal data belonging to other people.

Email: bet0.archscan@gmail.com  
Expected response target: 20 business days, without replacing any legal deadlines that may apply.

### Español

**Soporte — ARchScan**

Para solicitar soporte, indicá la versión de la aplicación, modelo del dispositivo, versión del sistema operativo, pasos para reproducir el problema y capturas o registros si están disponibles. No envíes planos confidenciales ni datos personales de terceros.

Correo: bet0.archscan@gmail.com  
Plazo de respuesta informado: 20 días hábiles, sin sustituir plazos legales aplicables.

## Page: Privacy / Privacidad

Use the policy maintained in `docs/PUBLIC_PRIVACY_POLICY.md` as the source of truth. Ensure the live page explicitly covers:
- Local project storage and no ARchScan account or app-owned cloud sync.
- Camera/sensor use during scanning.
- JSON, SVG, PDF, DXF, PNG, and JPG export/share behavior.
- Temporary cache copies created during sharing.
- Deletion of local projects, app data, and externally exported files as separate actions.
- Support emails being processed by the email provider.
- No ads or in-app purchases in the documented candidate; review again against the final artifact and its transitive SDKs.
- A clear local-data deletion section, since ARchScan has no accounts to delete.
- Contact: bet0.archscan@gmail.com.
- Responsible party: Alberto Lucchetta (Bet0), Argentina.
- Response target: 20 business days, subject to applicable legal requirements.

### English — local data deletion

ARchScan does not create user accounts, so there is no account to delete. To remove local projects, use the app's **Privacy and data** controls. Clearing the app's storage or uninstalling the app can also remove local projects. JSON, SVG, PDF, DXF, PNG, and JPG files exported or shared outside ARchScan must be deleted separately from the folder, service, or app where they were saved. Temporary sharing-cache copies may remain until the operating system clears them.

### Español — eliminación de datos locales

ARchScan no crea cuentas de usuario, por lo que no hay una cuenta que eliminar. Para borrar proyectos locales, utilizá los controles de **Privacidad y datos** de la aplicación. Borrar el almacenamiento de la app o desinstalarla también puede eliminar los proyectos locales. Los archivos JSON, SVG, PDF, DXF, PNG y JPG exportados o compartidos fuera de ARchScan deben borrarse por separado desde la carpeta, el servicio o la aplicación donde se guardaron. Las copias temporales de caché de la compartición pueden permanecer hasta que el sistema operativo las elimine.

## Publication checklist

- [ ] Replace outdated version/date text on the Home and User Guide pages.
- [ ] Paste English sections first, then Spanish sections; do not mix languages paragraph by paragraph.
- [ ] Check all navigation links on desktop and mobile.
- [ ] Verify Support and Privacy URLs open without signing in.
- [ ] Publish the site and open the public URLs in a signed-out/private browser session.
- [ ] Compare the public page text with the actual candidate and privacy policy.
- [ ] Do not claim final store approval, successful physical testing, or a published release without evidence.
