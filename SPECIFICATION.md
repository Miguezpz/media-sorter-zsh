# Especificación Técnica: Organizador de Archivos y Detector de Duplicados (.zsh)

Este documento detalla el diseño y las funcionalidades del script de organización de archivos para macOS (M2) utilizando ZSH.

## 1. Objetivo
Proporcionar una herramienta robusta y rápida para gestionar backups masivos de fotos, videos y otros archivos provenientes de múltiples dispositivos, eliminando la redundancia y estructurando el contenido de forma lógica.

## 2. Requisitos del Sistema
- **SO**: macOS (Optimizado para Apple Silicon M2).
- **Terminal**: Ghostty.
- **Dependencias**:
  - `jdupes`: Para búsqueda ultra-rápida de duplicados.
  - `exiftool`: Para renombrado inteligente basado en metadatos.
  - Herramientas BSD estándar (`find`, `md5`, `stat`).

## 3. Funcionalidades Seleccionadas

### A. Modo de Operación: Copia Segura
El script realizará una **copia** de los archivos al destino por defecto, preservando los originales en el disco duro de backup hasta que el usuario decida borrarlos manualmente.

### B. Gestión de Duplicados (jdupes)
Se utilizará `jdupes` para analizar archivos idénticos bit a bit. El script integrará la salida de `jdupes` para ofrecer un reporte claro antes de cualquier acción.

### C. Renombrado Inteligente (Smart Renaming)
Utilizando `exiftool`, las fotos y videos se renombrarán siguiendo el patrón `YYYYMMDD_HHMMSS.ext` basándose en la fecha de captura real, evitando conflictos de nombres como `IMG_0001.JPG`.

### D. Limpieza de Carpetas Vacías
Tras completar la organización, el script ofrecerá limpiar las carpetas que hayan quedado vacías en la estructura de origen.

### E. Registro de Operaciones (Logs)
Se generará un archivo `management_log.txt` en la carpeta destino con el detalle de cada archivo procesado, renombrado o detectado como duplicado.

## 4. Estructura de Carpetas Destino
Para mantener el contexto del origen, el script preguntará el nombre del dispositivo/backup. La estructura resultante será:
`Destino/Categoria/Nombre_Backup/Archivo.ext`

Ejemplo: `~/Fotos_Organizadas/Imagenes/iPhone_XS_Backup/20231025_143005.jpg`

### Categorías:
- **Imagenes**: .jpg, .jpeg, .png, .gif, .heic, .webp, .raw, .cr2, .nef
- **Videos**: .mp4, .mov, .avi, .mkv, .m4v, .3gp
- **Audio**: .mp3, .wav, .aac, .flac, .m4a
- **Documentos**: .pdf, .docx, .txt, .xlsx, .pptx, .md
- **Otros**: Extensiones no reconocidas.

## 5. Flujo de Trabajo (Workflow)
1. Inicio del script.
2. Verificación de dependencias (`jdupes`, `exiftool`) e instalación automática sugerida si faltan.
3. Selección de Carpeta Origen.
4. Selección de Carpeta Destino.
5. Ingreso de Identificador de Backup (ej: "iPhone_8_Backup_2021").
6. Escaneo de duplicados con `jdupes` en el origen.
7. Presentación de reporte de duplicados y confirmación.
8. Copia y organización de archivos únicos (con renombrado EXIF opcional).
9. Limpieza de carpetas vacías en origen (opcional).
10. Generación de reporte final y log.