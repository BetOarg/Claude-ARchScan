# Incidente: material de firma Android expuesto (2026-09-24)

## Qué pasó

- `f97fe18` agregó `.github/workflows/generate.yml`, que generó un keystore
  de release con una contraseña fija en el YAML e imprimió el keystore en
  base64 en los logs públicos de GitHub Actions.
- `5a91175` versionó `packages/room_scanner_app/android/key.properties` con
  esa misma contraseña (el archivo estaba en `.gitignore`, se agregó forzado).
- `ci.yml` decodificaba el keystore de producción en cada push/PR.

## Alcance

La clave expuesta **no está registrada como upload key en Play Console**.
No hay reset de Play pendiente. La clave queda, igual, **descartada para
siempre**: su contraseña y su contenido son públicos.

Riesgo residual: si el secret `ANDROID_KEYSTORE_BASE64` contiene ese
keystore, la primera subida de un AAB firmado con él a Play lo registraría
como upload key. Por eso los secrets se reemplazan antes de cualquier
publicación.

## Remediación en el repositorio

- `key.properties` deja de estar versionado.
- `ci.yml` compila el AAB de release sin firmar; la clave de producción solo
  existe en `release_android.yml`, que la borra al terminar.
- `tool/security_audit.dart` falla si se versiona un `key.properties` o una
  contraseña de keystore en `.yml`, `.yaml`, `.sh` o `.properties`
  (la clave pública de pruebas `android` sigue permitida).

## Remediación manual (fuera del repositorio)

1. Generar una clave nueva **en una máquina local**, nunca en CI:

   ```bash
   keytool -genkeypair -v -keystore archscan-upload.jks \
     -keyalg RSA -keysize 4096 -validity 10000 -alias archscan-upload
   base64 -w0 archscan-upload.jks > archscan-upload.jks.b64
   ```

   La contraseña se ingresa en el prompt interactivo de `keytool`.

2. Reemplazar en *Settings → Secrets and variables → Actions*:
   `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
   `ANDROID_KEY_PASSWORD`.
3. Borrar los logs de las ejecuciones de "Generate Keystore" en la pestaña
   Actions.
4. Guardar el `.jks` y sus contraseñas en un gestor de contraseñas con
   respaldo. Perder la upload key obliga a pedir un reset a Google.
5. Borrar `archscan-upload.jks.b64` del disco local.
