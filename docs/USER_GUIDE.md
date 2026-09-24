# ARchScan User Guide / Guía de uso

**Guide version:** ARchScan 2.7.0  
**Last updated:** September 8, 2026
**Developer:** Bet0  
**Data model:** local projects, without user accounts or cloud synchronization

---

# English — User Guide

### Switch or rename a local project

While a project is open, use **Close project** to return to **My projects** without closing ARchScan. From **My projects**, use **Rename** on a saved project to change only its name; the project UUID, rooms, geometry and local data remain unchanged.

### Technical dimensions

Technical drawings keep opening dimensions and overall dimensions while avoiding a redundant wall dimension on a wall segment occupied by a door. This prevents stacked or fragmented door/wall dimensions in the final plan.

## About this guide

ARchScan surveys spaces with the device camera. On compatible devices it uses augmented reality through ARCore or ARKit. When augmented reality is unavailable, it uses Basic Scanner with camera guidance and manual measurements.

Projects are stored locally on the device. ARchScan does not create accounts and does not automatically upload projects, images, measurements, or exports.

## Quick start — five steps

1. Open **ARchScan**, select **New project**, and enter a project name.
2. Select **New scan**. ARchScan automatically chooses the scanner supported by the device.
3. Register the room corners in order while moving around the perimeter.
4. Select **Close room** after registering at least three valid corners.
5. Open the overall floor plan to edit walls, add doors or windows, organize rooms, and export the project.

## 1. Create and open a project

### Create a project

1. Open ARchScan.
2. Select **New project**.
3. Enter a descriptive name, such as “Ground floor” or “Office survey.”
4. Confirm the project.
5. Select **New scan** to register the first space.

Use one project for spaces that belong to the same plan. This makes it possible to align and connect rooms later.

### Open an existing project

1. Open **My projects**.
2. Select the required project.
3. Review its registered spaces or open the overall floor plan.
4. Start a new scan only when another space must be added.

Projects are saved locally. They remain available after closing and reopening the application unless they are deleted, the application is uninstalled, or the device data is erased.

## 2. Automatic selection of Basic Scanner, ARCore, or ARKit

ARchScan checks the platform and available device capabilities before opening the scanner:

- **ARCore:** selected on compatible Android devices.
- **ARKit:** selected on compatible iPhone or iPad devices.
- **Basic Scanner:** selected when augmented reality is unavailable but a camera can be used.

The selection is automatic. No manual scanner setting is required.

If the augmented-reality scanner cannot start, ARchScan may offer **Continue with the basic scanner**. This fallback keeps the project workflow available, but distances must be entered manually.

## 3. Scan and close a room

Register corners consecutively around the room. Do not jump between unrelated walls. A room needs at least three valid corners before it can be closed.

### Basic Scanner instructions

1. Keep the camera aimed at the area being measured.
2. Select **Measure first corner** or **Measure next corner**.
3. Enter the physical distance from the previous point.
4. Choose the direction indicated by the interface.
5. Repeat the process around the room.
6. Select **Close room** when the contour is complete.
7. Review the room in the overall floor plan.

Basic Scanner uses the camera as a visual reference. It does not automatically calculate the physical wall length. Measure each distance with an appropriate measuring tool and enter it carefully.

### ARCore and ARKit instructions

1. Move the device slowly so the AR session can recognize the surroundings.
2. Aim at the actual corner or floor reference.
3. Select **Add corner**.
4. Continue around the perimeter in order.
5. Avoid sudden movements and keep the scanned surface visible.
6. Select **Close room** after the final required corner.

If the current camera position is invalid, move slowly, aim at a recognized surface, and try again.

### Closing against a nearby point or wall

The plan editor can propose a valid closing path toward the nearest compatible point or wall. Review the highlighted proposal before confirming it. ARchScan rejects closures that would create invalid crossings or overlaps.

## 4. Continue a room from a door or window

Doors and windows can connect two spaces.

1. Open the overall floor plan.
2. Select **Choose a door or window to continue**.
3. Select the required opening.
4. Choose the side or endpoint from which the new space will be measured.
5. Confirm the highlighted continuation.
6. Register the new room.
7. Close the room and review the connection on the overall plan.

The new room uses the selected opening as its reference. Do not move or edit that opening while the scanner is open.

## 5. Continue from corners

An unfinished room can be continued from its first or last vertex.

1. Open the overall floor plan.
2. Select an endpoint of the open contour.
3. Select **Continue scanning from here**.
4. Confirm that the highlighted vertex is the intended starting point.
5. Continue registering corners.
6. Close the room when the contour is complete.

Intermediate vertices cannot be used to branch an open contour. This prevents ambiguous or self-intersecting geometry.

### Start a new room between two corners of a closed room

1. Tap the starting corner directly on the overall plan.
2. Select **Continue scanning from here**.
3. Tap the corner where the new room must close. The starting and closing
   corners are highlighted with different colors.
4. Use two fingers or the zoom controls if you need to move or resize the plan
   before choosing the closing corner.
5. Confirm the selection and scan the new outer contour.
6. Close the new room and verify the shared boundary on the overall plan.

The operation creates a new room. It does not replace the source room or delete
its existing wall, measurements, doors, or windows. A coincident corner shared
by several rooms is resolved against the room selected for continuation.

## 6. Calibrate vertices when continuing with AR

A new AR session has its own coordinate reference. ARchScan therefore asks for two known points before continuing an existing open room:

1. Aim at the **previous contour vertex** and confirm it.
2. Aim at the **starting vertex** selected on the plan and confirm it.
3. Wait for the orientation-aligned confirmation.
4. Continue scanning from the starting vertex.

Use the real physical vertices and keep the device stable while confirming them. The two references preserve translation and orientation, including walls that are not at 90 degrees.

This calibration applies to ARCore and ARKit. Basic Scanner continues through manual distance and direction entry and does not require AR calibration.

## 7. Add doors and windows from the floor plan

Doors and windows are added from the overall plan, not during contour scanning.

1. Open the overall floor plan.
2. Select **Add door** or **Add window**.
3. Tap the wall that contains the opening.
4. Move the opening along the wall to the required position.
5. Enter or edit its measurements.
6. Confirm the placement.

An opening must remain associated with a valid wall. The closing wall can also receive doors and windows.

## 8. Edit, move, and delete walls, corners, and openings

### Walls

1. Tap a wall to select it.
2. Choose the available measurement or editing action.
3. Drag the wall in parallel or enter the required measurement.
4. Review the preview.
5. Confirm the change.

Select **Delete wall** to remove it. Its openings are removed and the contour remains open. The operation can be undone during the current editing session.

### Corners

1. Tap a corner.
2. Drag it to the intended position.
3. Use the nearby point or wall alignment when offered.
4. Confirm the final geometry.

### Doors and windows

1. Tap the opening.
2. Move it along its wall or edit its dimensions.
3. Confirm the change, or select **Delete opening**.

Deleting a connected opening removes the connection without deleting either room.

## 9. Move, align, organize, and delete rooms

### Move or rotate rooms

1. Open the room transformation tool.
2. Select the room.
3. Move or rotate it with gestures.
4. Confirm the placement.

Rooms connected by openings or shared walls move as a group so their existing relationships are preserved.
Use two fingers to pan or zoom the plan while arranging rooms. The dedicated
zoom-out, zoom-in, and reset-view controls remain available when greater
precision is required.

### Align walls

1. Position one room near the target room.
2. Select **Align with the nearest wall**.
3. Review the proposed alignment.
4. Confirm it only if it represents the real layout.

### Organize spaces

**Organize spaces** arranges independent groups. It does not intentionally separate rooms that are already connected. The first group stays fixed, and the action can be undone during the session.

### Delete a room

1. Select the room or one of its remaining elements.
2. Select **Delete room**.
3. Review the confirmation.
4. Confirm deletion.

The room, its walls, and its openings are removed. Connections to other rooms are removed without deleting those rooms. A room can also be deleted when no walls remain.

## 10. Undo and redo

Use **Undo** and **Redo** after scanning or plan-editing actions when the buttons are available.

Undo and redo operate on complete actions, such as a wall edit and the openings affected by that edit. Plan-editing history belongs to the current editing session and is not a permanent backup.

Before closing the application, review the plan and save or export any important project.

## 11. Save and open historical projects

ARchScan saves projects locally through its internal database.

- Close and reopen the application to confirm that the project appears in **My projects**.
- Historical compatible projects should open without manual conversion.
- Before uninstalling ARchScan or installing a build signed with a different key, export important projects as JSON.
- Never uninstall the application before making a JSON backup if the local projects must be preserved.

If a historical file is not compatible, ARchScan rejects the import without intentionally modifying the current project.

## 12. Import and export JSON or SVG

### Export JSON

1. Open the required project or floor plan.
2. Open the project export menu.
3. Select the JSON export option.
4. Choose the destination using the device share or file interface.
5. Keep the file in a safe location.

The JSON file contains the project structure, points, measurements, openings, and connections.

### Import JSON

1. Open the plan import option.
2. Select an ARchScan-compatible JSON file.
3. Review the imported project.
4. Confirm that rooms, measurements, and openings are present.

Importing JSON does not upload the file to an ARchScan server. File access is initiated by the user.

### SVG

ARchScan SVG exports are editable vector drawings that embed a versioned JSON
project backup. They can be saved to Files or shared. Import accepts only JSON
or SVG files with valid ARchScan metadata, asks before replacing the open
project, and safely rejects generic SVG drawings.

## 13. Export PDF and DXF 2D

### PDF

Select **Export**, choose PDF, and then choose **Save to Files** or **Share**.
The PDF provides a vector plan and technical information.

### DXF 2D

Select **Export**, choose DXF 2D, and then choose **Save to Files** or **Share**.
The DXF contains editable 2D geometry for compatible CAD software.

- Spanish/metric projects export DXF coordinates in meters.
- English/imperial output uses inches, with measurements displayed in feet and inches.
- DXF measurements are currently exported as editable text, not associative CAD dimensions.
- ARchScan does not currently import DXF files.
- DXF is not DWG.

Exported files remain under the user's control and must be deleted from their destination folder or receiving application when no longer needed.

## 14. Delete local data

### Delete one project

Open **My projects**, locate the project, and select **Delete**. Confirm the operation.

### Delete all local projects

1. Open **Privacy and data**.
2. Select **Delete all local projects**.
3. Read the warning.
4. Select **Delete permanently**.

This removes projects stored by ARchScan on that device. It does not delete previously exported JSON, PDF, or DXF files. Delete exported files separately from the folder or application where they were saved.

Uninstalling ARchScan also removes its local application data. Export important projects first.

## 15. Camera, permission, and resume troubleshooting

### Camera permission was denied

1. Open the device system settings.
2. Find ARchScan in the application list.
3. Enable camera permission.
4. Return to ARchScan and retry the scanner.

ARchScan does not require location permission to store project coordinates. Measurements are local plan coordinates, not geographic location.

### Camera remains on “Preparing camera”

- Wait briefly for the camera service to initialize.
- Return to the previous screen and open the scanner again.
- If an error appears, select **Retry camera**.
- Close other applications that may be using the camera.
- Restart ARchScan if the camera remains unavailable.

### Camera does not resume after the screen was off

- Unlock the device and wait for ARchScan to restore the camera.
- If restoration fails, select **Retry camera**.
- Return to the plan and reopen the scan if necessary.
- Confirm that camera permission is still enabled.

### AR tracking is unavailable or unstable

- Improve room lighting.
- Move the device slowly.
- Keep textured surfaces and corners visible.
- Avoid reflective, transparent, or featureless surfaces.
- Use **Continue with the basic scanner** when offered.

### The room cannot be closed

- Confirm that at least three valid corners exist.
- Review the point order.
- Remove duplicated or crossing points.
- Use the proposed valid closure only after reviewing its highlighted path.

### A wall was deleted and scanning must continue

Select an endpoint of the resulting open contour and use **Continue scanning from here**. In AR, complete the two-vertex calibration before adding new corners.

## 16. Accuracy and physical verification

Mobile measurements are estimates influenced by the device, camera, sensors, lighting, surfaces, user movement, and manual data entry.

Always verify critical dimensions with an appropriate physical measuring instrument before using the results for construction, fabrication, budgets, legal documents, safety decisions, or professional technical work.

ARchScan is a surveying and documentation aid. It does not replace professional verification.

## Frequently asked questions

### Does ARchScan require an account?

No. ARchScan does not create user accounts.

### Does ARchScan upload my projects?

No. Projects are stored locally. Exporting or sharing occurs only when the user starts the action.

### Does ARchScan contain advertisements or purchases?

The current beta is free and contains no advertisements, subscriptions, purchases, or locked Pro functions.

### Can I use ARchScan without ARCore or ARKit?

Yes. Basic Scanner is used when augmented reality is unavailable and a camera can be accessed.

### Can I add doors or windows while scanning?

The current workflow adds doors and windows from the overall floor plan after the room contour is registered.

### Can I continue an unfinished room from either end?

Yes. Select the first or last vertex of the open contour. Intermediate vertices are not used for branching.

### Can I create a new room between two corners of an existing room?

Yes. Tap the starting corner, select **Continue scanning from here**, and then
tap the closing corner. ARchScan preserves the original room and uses the
selected boundary as a shared wall.

### Can ARchScan import DXF?

No. ARchScan exports DXF 2D but does not currently import DXF.

### Are exported files deleted when I delete a project?

No. Delete exported files separately from their destination folder or receiving application.

### What should I do before uninstalling the application?

Export important projects as JSON and verify that the files can be accessed from their saved location.

## Support, privacy, and local data deletion

- **Official website:** https://sites.google.com/view/archscan/inicio
- **Support:** support.ARchScan@gmail.com
- **Privacy contact:** bet0.archscan@gmail.com
- **Privacy Policy:** available from the Privacy section of the official website.
- **Local Data Deletion:** available from the Privacy and Data section of the official website.
- **Response period:** up to 20 business days, without replacing any shorter legally applicable period.

---

# Español — Guía de uso

## Acerca de esta guía

ARchScan releva espacios mediante la cámara del dispositivo. En equipos compatibles utiliza realidad aumentada mediante ARCore o ARKit. Cuando la realidad aumentada no está disponible, utiliza Basic Scanner con guía de cámara y mediciones manuales.

Los proyectos se guardan localmente en el dispositivo. ARchScan no crea cuentas ni carga automáticamente proyectos, imágenes, mediciones o exportaciones.

## Inicio rápido — cinco pasos

1. Abrí **ARchScan**, seleccioná **Nuevo proyecto** e ingresá un nombre.
2. Seleccioná **Nuevo escaneo**. ARchScan elegirá automáticamente el escáner compatible con el dispositivo.
3. Registrá las esquinas del ambiente en orden mientras recorrés su perímetro.
4. Seleccioná **Cerrar ambiente** después de registrar al menos tres esquinas válidas.
5. Abrí el plano general para editar paredes, agregar puertas o ventanas, organizar ambientes y exportar el proyecto.

## 1. Crear y abrir un proyecto

### Crear un proyecto

1. Abrí ARchScan.
2. Seleccioná **Nuevo proyecto**.
3. Ingresá un nombre descriptivo, como “Planta baja” o “Relevamiento oficina”.
4. Confirmá el proyecto.
5. Seleccioná **Nuevo escaneo** para registrar el primer ambiente.

Usá un mismo proyecto para los ambientes que pertenecen al mismo plano. Esto permite alinearlos y conectarlos posteriormente.

### Abrir un proyecto existente

1. Abrí **Mis proyectos**.
2. Seleccioná el proyecto requerido.
3. Revisá sus ambientes registrados o abrí el plano general.
4. Iniciá otro escaneo solamente cuando necesites agregar un ambiente.

Los proyectos se guardan localmente. Permanecen disponibles después de cerrar y abrir la aplicación, salvo que se eliminen, se desinstale la aplicación o se borren sus datos.

## 2. Selección automática de Basic Scanner, ARCore o ARKit

ARchScan comprueba la plataforma y las capacidades disponibles antes de abrir el escáner:

- **ARCore:** se selecciona en dispositivos Android compatibles.
- **ARKit:** se selecciona en iPhone o iPad compatibles.
- **Basic Scanner:** se selecciona cuando la realidad aumentada no está disponible, pero se puede utilizar una cámara.

La selección es automática. No hace falta configurar manualmente el tipo de escáner.

Si el escáner de realidad aumentada no puede iniciarse, ARchScan puede ofrecer **Continuar con el escáner básico**. El proyecto podrá continuar, pero las distancias deberán ingresarse manualmente.

## 3. Escanear y cerrar un ambiente

Registrá las esquinas consecutivamente alrededor del ambiente. No alternes entre paredes que no sean contiguas. Se necesitan al menos tres esquinas válidas para cerrar un ambiente.

### Instrucciones para Basic Scanner

1. Mantené la cámara orientada hacia el sector que estás midiendo.
2. Seleccioná **Medir primera esquina** o **Medir siguiente esquina**.
3. Ingresá la distancia física desde el punto anterior.
4. Elegí la dirección indicada por la interfaz.
5. Repetí el proceso alrededor del ambiente.
6. Seleccioná **Cerrar ambiente** cuando el contorno esté completo.
7. Revisá el ambiente en el plano general.

Basic Scanner utiliza la cámara como referencia visual. No calcula automáticamente la longitud física de la pared. Medí cada distancia con una herramienta adecuada e ingresala cuidadosamente.

### Instrucciones para ARCore y ARKit

1. Mové el dispositivo lentamente para que la sesión AR reconozca el entorno.
2. Apuntá a la esquina real o referencia del piso.
3. Seleccioná **Agregar esquina**.
4. Continuá alrededor del perímetro en orden.
5. Evitá movimientos bruscos y mantené visible la superficie escaneada.
6. Seleccioná **Cerrar ambiente** después de la última esquina necesaria.

Si la posición de cámara no es válida, mové el dispositivo lentamente, apuntá a una superficie reconocida e intentá nuevamente.

### Cerrar contra un punto o pared cercanos

El editor del plano puede proponer un recorrido válido hacia el punto o pared compatibles más cercanos. Revisá la propuesta resaltada antes de confirmarla. ARchScan rechaza cierres que producirían cruces o solapamientos inválidos.

## 4. Continuar un ambiente desde una puerta o ventana

Las puertas y ventanas pueden conectar dos ambientes.

1. Abrí el plano general.
2. Seleccioná **Elegí una puerta o ventana para continuar**.
3. Seleccioná la abertura requerida.
4. Elegí el lado o extremo desde el que medirás el nuevo ambiente.
5. Confirmá la continuación resaltada.
6. Registrá el nuevo ambiente.
7. Cerralo y revisá la conexión en el plano general.

El nuevo ambiente utiliza la abertura seleccionada como referencia. No muevas ni edites esa abertura mientras el escáner está abierto.

## 5. Continuar desde esquinas

Un ambiente sin terminar puede continuarse desde su primer o último vértice.

1. Abrí el plano general.
2. Seleccioná un extremo del contorno abierto.
3. Seleccioná **Continuar escaneo desde aquí**.
4. Confirmá que el vértice resaltado sea el punto inicial deseado.
5. Continuá registrando esquinas.
6. Cerrá el ambiente cuando el contorno esté completo.

Los vértices intermedios no pueden utilizarse para bifurcar el contorno. Esto evita geometrías ambiguas o con cruces.

### Crear un ambiente nuevo entre dos esquinas de un ambiente cerrado

1. Tocá directamente en el plano general la esquina inicial.
2. Seleccioná **Continuar escaneo desde aquí**.
3. Tocá la esquina donde debe cerrar el ambiente nuevo. El inicio y el cierre
   se resaltan con colores diferentes.
4. Usá dos dedos o los controles de zoom si necesitás mover o achicar el plano
   antes de elegir la esquina final.
5. Confirmá la selección y escaneá el nuevo contorno exterior.
6. Cerrá el ambiente nuevo y verificá el límite compartido en el plano general.

La operación crea un ambiente nuevo. No reemplaza el ambiente de origen ni
elimina su pared, medidas, puertas o ventanas existentes. Si una esquina
coincide entre varios ambientes, ARchScan utiliza la del ambiente seleccionado
para la continuación.

## 6. Calibrar vértices al continuar con AR

Una nueva sesión AR posee su propia referencia de coordenadas. Por eso, ARchScan solicita dos puntos conocidos antes de continuar un ambiente abierto:

1. Apuntá al **vértice anterior del contorno** y confirmalo.
2. Apuntá al **vértice inicial** seleccionado en el plano y confirmalo.
3. Esperá la confirmación de orientación alineada.
4. Continuá el escaneo desde el vértice inicial.

Usá los vértices físicos reales y mantené estable el dispositivo al confirmarlos. Las dos referencias conservan la traslación y orientación, incluso cuando la pared no está a 90 grados.

Esta calibración corresponde a ARCore y ARKit. Basic Scanner continúa mediante el ingreso manual de distancia y dirección y no requiere calibración AR.

## 7. Agregar puertas y ventanas desde el plano

Las puertas y ventanas se agregan desde el plano general, no durante el escaneo del contorno.

1. Abrí el plano general.
2. Seleccioná **Agregar puerta** o **Agregar ventana**.
3. Tocá la pared que contiene la abertura.
4. Mové la abertura sobre la pared hasta la posición requerida.
5. Ingresá o editá sus medidas.
6. Confirmá la ubicación.

La abertura debe permanecer asociada a una pared válida. También se pueden agregar puertas y ventanas sobre la pared de cierre.

## 8. Editar, mover y eliminar paredes, esquinas y aberturas

### Paredes

1. Tocá una pared para seleccionarla.
2. Elegí la acción de medida o edición disponible.
3. Arrastrá la pared en paralelo o ingresá la medida requerida.
4. Revisá la vista previa.
5. Confirmá el cambio.

Seleccioná **Eliminar pared** para quitarla. Sus aberturas serán eliminadas y el contorno quedará abierto. La operación puede deshacerse durante la sesión de edición actual.

### Esquinas

1. Tocá una esquina.
2. Arrastrala a la posición deseada.
3. Utilizá el ajuste al punto o pared cercanos cuando esté disponible.
4. Confirmá la geometría final.

### Puertas y ventanas

1. Tocá la abertura.
2. Movela sobre su pared o editá sus dimensiones.
3. Confirmá el cambio o seleccioná **Eliminar abertura**.

Al eliminar una abertura conectada se quita la conexión, sin eliminar ninguno de los ambientes.

## 9. Mover, alinear, organizar y eliminar ambientes

### Mover o rotar ambientes

1. Abrí la herramienta de transformación de ambientes.
2. Seleccioná el ambiente.
3. Movelo o rotalo mediante gestos.
4. Confirmá la ubicación.

Los ambientes conectados mediante aberturas o paredes compartidas se mueven como un grupo para conservar sus relaciones existentes.
Usá dos dedos para desplazar o ampliar el plano mientras organizás los
ambientes. También están disponibles los controles de alejar, acercar y
restablecer la vista para realizar ajustes precisos.

### Alinear paredes

1. Colocá un ambiente cerca del ambiente de destino.
2. Seleccioná **Alinear con la pared más cercana**.
3. Revisá la alineación propuesta.
4. Confirmala solamente si representa la distribución real.

### Organizar ambientes

**Organizar ambientes** distribuye grupos independientes. No debe separar intencionalmente ambientes ya conectados. El primer grupo permanece fijo y la acción puede deshacerse durante la sesión.

### Eliminar un ambiente

1. Seleccioná el ambiente o uno de sus elementos restantes.
2. Seleccioná **Eliminar ambiente**.
3. Revisá la confirmación.
4. Confirmá la eliminación.

Se eliminan el ambiente, sus paredes y sus aberturas. Las conexiones con otros ambientes se quitan sin eliminar esos ambientes. También se puede eliminar un ambiente cuando ya no tiene paredes.

## 10. Deshacer y rehacer

Utilizá **Deshacer** y **Rehacer** después de operaciones de escaneo o edición del plano cuando los botones estén disponibles.

Deshacer y rehacer actúan sobre operaciones completas, como la edición de una pared y las aberturas afectadas. El historial de edición del plano corresponde a la sesión actual y no constituye una copia de seguridad permanente.

Antes de cerrar la aplicación, revisá el plano y guardá o exportá cualquier proyecto importante.

## 11. Guardar y abrir proyectos históricos

ARchScan guarda los proyectos localmente mediante su base de datos interna.

- Cerrá y volvé a abrir la aplicación para confirmar que el proyecto aparezca en **Mis proyectos**.
- Los proyectos históricos compatibles deben abrirse sin conversión manual.
- Antes de desinstalar ARchScan o instalar una compilación firmada con otra clave, exportá los proyectos importantes como JSON.
- Nunca desinstales la aplicación sin crear antes una copia JSON si necesitás conservar los proyectos locales.

Si un archivo histórico no es compatible, ARchScan rechaza la importación sin modificar intencionalmente el proyecto actual.

## 12. Importar y exportar JSON o SVG

### Exportar JSON

1. Abrí el proyecto o plano requerido.
2. Abrí el menú de exportación del proyecto.
3. Seleccioná la opción de exportación JSON.
4. Elegí el destino mediante la interfaz de archivos o compartir del dispositivo.
5. Conservá el archivo en una ubicación segura.

El JSON contiene la estructura del proyecto, puntos, medidas, aberturas y conexiones.

### Importar JSON

1. Abrí la opción de importación del plano.
2. Seleccioná un archivo JSON compatible con ARchScan.
3. Revisá el proyecto importado.
4. Confirmá que estén presentes los ambientes, medidas y aberturas.

La importación JSON no carga el archivo a un servidor de ARchScan. El acceso al archivo es iniciado por el usuario.

### SVG

Los SVG exportados por ARchScan son planos vectoriales editables que incorporan
una copia JSON versionada del proyecto. Se pueden guardar en Archivos o
compartir. La importación acepta únicamente JSON o SVG con metadatos ARchScan
válidos, solicita confirmación antes de reemplazar el proyecto abierto y
rechaza de forma segura los SVG genéricos.

## 13. Exportar PDF y DXF 2D

### PDF

Seleccioná **Exportar**, elegí PDF y después **Guardar en Archivos** o
**Compartir**. El PDF proporciona un plano vectorial e información técnica.

### DXF 2D

Seleccioná **Exportar**, elegí DXF 2D y después **Guardar en Archivos** o
**Compartir**. El DXF contiene geometría 2D editable para programas CAD
compatibles.

- Los proyectos en español/sistema métrico exportan coordenadas DXF en metros.
- La salida en inglés/sistema imperial utiliza pulgadas y muestra las medidas en pies y pulgadas.
- Las medidas DXF se exportan actualmente como textos editables, no como cotas asociativas de CAD.
- ARchScan todavía no importa archivos DXF.
- DXF no es DWG.

Los archivos exportados quedan bajo control del usuario y deben eliminarse desde su carpeta de destino o aplicación receptora cuando ya no sean necesarios.

## 14. Eliminar datos locales

### Eliminar un proyecto

Abrí **Mis proyectos**, localizá el proyecto y seleccioná **Eliminar**. Confirmá la operación.

### Eliminar todos los proyectos locales

1. Abrí **Privacidad y datos**.
2. Seleccioná **Eliminar todos los proyectos locales**.
3. Leé la advertencia.
4. Seleccioná **Eliminar permanentemente**.

Esto elimina los proyectos guardados por ARchScan en ese dispositivo. No elimina los archivos JSON, PDF o DXF exportados previamente. Eliminá esos archivos por separado desde la carpeta o aplicación donde fueron guardados.

Desinstalar ARchScan también elimina sus datos locales. Exportá primero los proyectos importantes.

## 15. Solución de problemas de cámara, permisos y reanudación

### Se denegó el permiso de cámara

1. Abrí la configuración del sistema del dispositivo.
2. Buscá ARchScan en la lista de aplicaciones.
3. Activá el permiso de cámara.
4. Regresá a ARchScan y volvé a intentar el escaneo.

ARchScan no necesita permiso de ubicación para guardar coordenadas de proyectos. Las mediciones son coordenadas locales del plano, no una ubicación geográfica.

### La cámara permanece en “Preparando cámara”

- Esperá brevemente mientras se inicia el servicio de cámara.
- Regresá a la pantalla anterior y volvé a abrir el escáner.
- Si aparece un error, seleccioná **Reintentar cámara**.
- Cerrá otras aplicaciones que puedan estar usando la cámara.
- Reiniciá ARchScan si la cámara continúa sin estar disponible.

### La cámara no se reanuda después de apagar la pantalla

- Desbloqueá el dispositivo y esperá a que ARchScan restaure la cámara.
- Si la restauración falla, seleccioná **Reintentar cámara**.
- Regresá al plano y volvé a abrir el escaneo si fuera necesario.
- Confirmá que el permiso de cámara continúe habilitado.

### El seguimiento AR no está disponible o es inestable

- Mejorá la iluminación del ambiente.
- Mové lentamente el dispositivo.
- Mantené visibles superficies con textura y esquinas.
- Evitá superficies reflectantes, transparentes o sin detalles.
- Utilizá **Continuar con el escáner básico** cuando se ofrezca.

### No se puede cerrar el ambiente

- Confirmá que existan al menos tres esquinas válidas.
- Revisá el orden de los puntos.
- Eliminá puntos duplicados o recorridos con cruces.
- Utilizá el cierre válido propuesto solamente después de revisar su recorrido resaltado.

### Se eliminó una pared y hay que continuar el escaneo

Seleccioná un extremo del contorno abierto resultante y utilizá **Continuar escaneo desde aquí**. En AR, completá la calibración de dos vértices antes de agregar nuevas esquinas.

## 16. Precisión y verificación física

Las mediciones móviles son estimaciones y dependen del dispositivo, cámara, sensores, iluminación, superficies, movimiento del usuario e ingreso manual de datos.

Verificá siempre las dimensiones críticas mediante un instrumento físico adecuado antes de utilizar los resultados para construcción, fabricación, presupuestos, documentación legal, decisiones de seguridad o trabajos técnicos profesionales.

ARchScan es una herramienta de relevamiento y documentación. No reemplaza la verificación profesional.

## Preguntas frecuentes

### ¿ARchScan necesita una cuenta?

No. ARchScan no crea cuentas de usuario.

### ¿ARchScan carga mis proyectos a internet?

No. Los proyectos se guardan localmente. La exportación o el intercambio solamente ocurre cuando el usuario inicia la acción.

### ¿ARchScan contiene anuncios o compras?

La beta actual es gratuita y no contiene anuncios, suscripciones, compras ni funciones Pro bloqueadas.

### ¿Puedo usar ARchScan sin ARCore o ARKit?

Sí. Basic Scanner se utiliza cuando la realidad aumentada no está disponible y se puede acceder a una cámara.

### ¿Puedo agregar puertas o ventanas durante el escaneo?

El flujo actual agrega puertas y ventanas desde el plano general después de registrar el contorno del ambiente.

### ¿Puedo continuar un ambiente sin terminar desde cualquiera de sus extremos?

Sí. Seleccioná el primer o último vértice del contorno abierto. Los vértices intermedios no se utilizan para crear bifurcaciones.

### ¿Puedo crear un ambiente nuevo entre dos esquinas de otro ambiente?

Sí. Tocá la esquina inicial, seleccioná **Continuar escaneo desde aquí** y
después tocá la esquina final. ARchScan conserva el ambiente original y utiliza
el límite seleccionado como pared compartida.

### ¿ARchScan puede importar DXF?

No. ARchScan exporta DXF 2D, pero todavía no importa DXF.

### ¿Los archivos exportados se eliminan al borrar un proyecto?

No. Eliminá los archivos exportados por separado desde su carpeta de destino o aplicación receptora.

### ¿Qué debo hacer antes de desinstalar la aplicación?

Exportá los proyectos importantes como JSON y verificá que puedas acceder a los archivos desde su ubicación de destino.

## Soporte, privacidad y eliminación de datos locales

- **Sitio oficial:** https://sites.google.com/view/archscan/inicio
- **Soporte:** support.ARchScan@gmail.com
- **Contacto de privacidad:** bet0.archscan@gmail.com
- **Política de privacidad:** disponible desde la sección Privacidad del sitio oficial.
- **Eliminación de datos locales:** disponible desde la sección Privacidad y datos del sitio oficial.
- **Plazo de respuesta:** hasta 20 días hábiles, sin sustituir un plazo legal aplicable más breve.
