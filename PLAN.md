# Plan: Mejoras de Validación y Procesamiento por Fases

## Objetivos

1. **Validar que Source ≠ Destination** - Prevenir errores de configuración
2. **Verificar espacio en disco disponible** - Antes y durante el procesamiento
3. **Procesamiento por fases (chunking)** - Cuando el espacio es limitado, procesar en lotes y limpiar origen tras cada fase

---

## 1. Validación Source ≠ Destination

### Implementación en `organize.zsh` - función `validate_config()`

```zsh
validate_config() {
    # ... validaciones existentes ...
    
    # NUEVA: Validar que source y destination no sean el mismo
    local abs_source=$(cd "$SOURCE_DIR" && pwd)
    local abs_dest=$(mkdir -p "$DEST_ROOT" && cd "$DEST_ROOT" && pwd)
    
    # Verificar si dest está dentro de source (o viceversa)
    if [[ "$abs_dest" == "$abs_source"* ]]; then
        print_error "Destination cannot be inside source directory"
        print_error "  Source:      $abs_source"
        print_error "  Destination: $abs_dest"
        ((errors++))
    elif [[ "$abs_source" == "$abs_dest"* ]]; then
        print_error "Source cannot be inside destination directory"
        ((errors++))
    fi
    
    # Verificar si son el mismo filesystem (mismo dispositivo)
    local src_dev=$(stat -f "%d" "$abs_source" 2>/dev/null)
    local dest_dev=$(stat -f "%d" "$abs_dest" 2>/dev/null)
    if [[ -n "$src_dev" && -n "$dest_dev" && "$src_dev" == "$dest_dev" ]]; then
        print_warn "Source and destination are on the same filesystem"
        print_warn "Moving files will be fast (rename), but copying will use extra space"
        if ! confirm "Continue anyway?"; then
            ((errors++))
        fi
    fi
}
```

---

## 2. Verificación de Espacio en Disco

### Nueva función en `lib/file_ops.zsh`

```zsh
# Obtener espacio libre en bytes
get_free_space_bytes() {
    local path="$1"
    df -k "$path" 2>/dev/null | awk 'NR==2 {print $4 * 1024}'
}

# Obtener espacio libre legible
get_free_space_human() {
    local path="$1"
    df -h "$path" 2>/dev/null | awk 'NR==2 {print $4}'
}

# Estimar tamaño total de archivos a procesar
estimate_source_size() {
    local source_dir="$1"
    local -a files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(scan_files "$source_dir")
    
    local total_size=0
    for file in "${files[@]}"; do
        total_size=$((total_size + $(get_file_size "$file")))
    done
    echo "$total_size"
}

# Verificar si hay espacio suficiente
check_disk_space() {
    local source_dir="$1"
    local dest_dir="$2"
    local copy_mode="${3:-copy}"
    
    local free_dest=$(get_free_space_bytes "$dest_dir")
    local needed=$(estimate_source_size "$source_dir")
    
    # Si es move, no necesitamos espacio extra en destino (solo metadatos)
    if [[ "$copy_mode" == "move" ]]; then
        needed=0
    fi
    
    # Margen de seguridad 10%
    local needed_with_margin=$((needed * 110 / 100))
    
    if [[ $free_dest -lt $needed_with_margin ]]; then
        return 1  # Espacio insuficiente
    fi
    return 0  # Espacio suficiente
}
```

---

## 3. Procesamiento por Fases (Phased Processing)

### Concepto

Cuando `COPY_MODE="copy"` y el espacio en destino es insuficiente para todos los archivos:

1. **Dividir archivos en chunks** (ej. 5000 archivos o 50GB por fase)
2. **Fase N**: 
   - Copiar chunk N a destino
   - Verificar integridad (hash)
   - **Eliminar archivos copiados del source** (solo si copia exitosa)
   - Liberar espacio en source (que suele ser el mismo disco)
3. **Repetir** hasta completar todos los archivos

### Nueva función en `lib/file_ops.zsh`

```zsh
# Procesar archivos en fases cuando hay espacio limitado
organize_files_phased() {
    local source_dir="$1"
    local dest_root="$2"
    local backup_id="$3"
    local chunk_size_files="${4:-5000}"
    local chunk_size_bytes="${5:-53687091200}"  # 50GB default
    
    # Recopilar todos los archivos
    local -a all_files=()
    while IFS= read -r -d '' file; do
        all_files+=("$file")
    done < <(scan_files "$source_dir")
    
    local total_files=${#all_files[@]}
    local processed=0
    local phase=1
    
    while [[ $processed -lt $total_files ]]; do
        print_section "PHASE $phase"
        
        # Calcular chunk actual
        local remaining=$((total_files - processed))
        local chunk_end=$((processed + chunk_size_files))
        [[ $chunk_end -gt $total_files ]] && chunk_end=$total_files
        
        # Verificar espacio antes de cada fase
        local free_dest=$(get_free_space_bytes "$dest_root")
        local needed=0
        for ((i=processed; i<chunk_end; i++)); do
            needed=$((needed + $(get_file_size "${all_files[i]}")))
        done
        needed=$((needed * 110 / 100))  # 10% margin
        
        if [[ $free_dest -lt $needed ]]; then
            print_warn "Insufficient space for next chunk ($needed needed, $free_dest free)"
            print_info "Waiting for space to be freed..."
            # Podría esperar o pedir intervención manual
        fi
        
        print_info "Processing files $((processed+1)) to $chunk_end of $total_files"
        
        # Procesar chunk
        local -a chunk_files=("${all_files[@]:processed:chunk_end-processed}")
        process_chunk "$chunk_files" "$dest_root" "$backup_id"
        
        # Si copy mode: eliminar archivos procesados del source
        if [[ "$COPY_MODE" == "copy" ]]; then
            cleanup_processed_source "$chunk_files" "$source_dir"
        fi
        
        processed=$chunk_end
        ((phase++))
    done
}

process_chunk() {
    local -n files_ref=$1
    local dest_root="$2"
    local backup_id="$3"
    
    for file in "${files_ref[@]}"; do
        # ... lógica existente de categorize, rename, copy ...
        # (reutilizar organize_files pero solo para este chunk)
    done
}

cleanup_processed_source() {
    local -n files_ref=$1
    local source_dir="$2"
    
    print_info "Removing processed files from source..."
    for file in "${files_ref[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_operation "$LOG_FILE" "CLEANUP_SRC" "$file" "" "(DRY RUN)"
        else
            rm -f "$file"
            log_operation "$LOG_FILE" "CLEANUP_SRC" "$file" "" "Removed after copy"
        fi
    done
    
    # Limpiar directorios vacíos en source
    cleanup_empty_dirs "$source_dir" "$LOG_FILE"
}
```

---

## 4. Integración en `organize.zsh`

### Modificar `organize_files()` para usar phased cuando sea necesario

```zsh
organize_files() {
    if [[ "$MODE" == "duplicates" ]]; then
        return 0
    fi
    
    print_section "ORGANIZING FILES"
    
    # Verificar espacio
    if ! check_disk_space "$SOURCE_DIR" "$DEST_ROOT" "$COPY_MODE"; then
        print_warn "Insufficient disk space for single-pass copy"
        print_info "Enabling phased processing..."
        organize_files_phased "$SOURCE_DIR" "$DEST_ROOT" "$BACKUP_ID"
        return 0
    fi
    
    # ... lógica existente single-pass ...
}
```

---

## 5. Mejoras Adicionales en UI

### En `get_user_config()` - mostrar espacio disponible

```zsh
# En selección de destination
print_section "DESTINATION DIRECTORY"
local dest_free=$(get_free_space_human "$(dirname "$DEST_ROOT" 2>/dev/null || echo "/")")
print_info "Free space on destination volume: $dest_free"
read_path "Destination directory" DEST_ROOT
```

### Mostrar estimación antes de confirmar

```zsh
# En CONFIGURATION SUMMARY
local est_size=$(estimate_source_size "$SOURCE_DIR")
local free_dest=$(get_free_space_human "$DEST_ROOT")
printf "  ${COLORS[BOLD]}Est. size:${COLORS[RESET]}      %s\n" "$(format_bytes $est_size)"
printf "  ${COLORS[BOLD]}Free space:${COLORS[RESET]}      %s\n" "$free_dest"
if [[ "$COPY_MODE" == "copy" ]]; then
    local needed=$((est_size * 110 / 100))
    if [[ $(get_free_space_bytes "$DEST_ROOT") -lt $needed ]]; then
        printf "  ${COLORS[RED]}⚠ SPACE WARNING: Phased processing will be used${COLORS[RESET]}\n"
    fi
fi
```

---

## Archivos a Modificar

| Archivo | Cambios |
|---------|---------|
| `organize.zsh` | `validate_config()`: validar source≠dest, mismo filesystem; `get_user_config()`: mostrar espacio libre; `organize_files()`: llamar a phased si necesario |
| `lib/file_ops.zsh` | Nuevas funciones: `get_free_space_bytes`, `get_free_space_human`, `estimate_source_size`, `check_disk_space`, `organize_files_phased`, `process_chunk`, `cleanup_processed_source`, `format_bytes` |
| `lib/ui_helpers.zsh` | (opcional) helpers para mostrar barras de progreso por fase |

---

## Testing

1. **Test validación source=dest**: Intentar misma ruta → debe fallar
2. **Test validación dest dentro de source**: `/Volumes/USB/source` vs `/Volumes/USB/source/output` → debe fallar
3. **Test mismo filesystem**: source y dest en mismo disco → warning pero permite
4. **Test espacio insuficiente**: Simular con `dd` disco lleno → debe activar phased
5. **Test phased processing**: Verificar que elimina source tras copiar y continua

---

## Consideraciones de Seguridad

- **NUNCA eliminar source** hasta verificar hash del destino
- **Dry run** debe simular todo sin borrar
- **Logs detallados** de cada archivo eliminado del source
- **Confirmación extra** antes de activar modo phased con auto-eliminación
- **Rollback**: Si falla a mitad de fase, no eliminar archivos de esa fase