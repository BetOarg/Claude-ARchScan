# Corrección de dirección de apertura en exportaciones

## Diagnóstico

La geometría técnica de exportación conserva `doorHingeSide`, `doorSwingSide` y `doorOpeningDirection`, pero el sentido lateral utilizado por los renderizadores de exportación queda invertido respecto del plano mostrado en la aplicación.

## Corrección

`TechnicalDrawingGeometry.normalizeRoom()` genera una copia exclusivamente para dibujo técnico y normaliza `doorSwingSide` al sistema de coordenadas utilizado por las salidas. La geometría persistida del proyecto y los metadatos JSON no se modifican.

Esto mantiene alineados SVG, PDF y las salidas raster que derivan del SVG, además de DXF que consume la misma geometría técnica normalizada.

## Regresión cubierta

La prueba debe comprobar que la normalización de exportación no altera el proyecto original y que la orientación de apertura usada por la geometría técnica es la opuesta a la orientación gráfica actualmente invertida.
