#!/usr/bin/env zsh
# ============================================================================
# Carpetas protegidas: programas, juegos, proyectos de código y paquetes de
# macOS que NO deben repartirse por categorías (dejarían de funcionar).
# ============================================================================
#
# Detección:
#   1. Marcadores fuertes (protegen la carpeta que los contiene):
#        .dll .cab .msi .sys .ocx            → programa / juego
#        package.json, Cargo.toml, go.mod… → proyecto de código
#        .sln .csproj .vcxproj, .git/, node_modules/
#      Un .exe suelto NO cuenta: es habitual tener un instalador junto a
#      fotos o documentos personales.
#   2. Paquetes de macOS (*.app, *.photoslibrary, *.fcpbundle…) se protegen
#      como unidad.
#   3. La protección "sube" a la carpeta padre mientras ésta casi no tenga
#      contenido personal (fotos, videos, audio, documentos) fuera de las
#      subcarpetas ya protegidas: como máximo PROTECT_MAX_PERSONAL archivos y
#      PROTECT_MAX_PERSONAL_PCT % del total (p. ej. imágenes de vista previa de
#      un juego). Así un juego completo queda entero, pero una carpeta
#      "Documentos" con un programa dentro no se bloquea.
#   La carpeta de origen nunca se protege.

typeset -gA PROT_SET=()        # carpeta protegida -> motivo
typeset -ga PROTECTED_DIRS=()  # lista final (sin anidadas), ordenada

typeset -gi PROTECT_MAX_PERSONAL=20
typeset -gi PROTECT_MAX_PERSONAL_PCT=3

typeset -ga PROJECT_MARKER_FILES=(
    package.json cargo.toml go.mod pom.xml build.gradle pyproject.toml
    setup.py composer.json gemfile cmakelists.txt
)

# ¿El archivo cuenta como contenido personal? (no software)
_is_user_content() {
    local f="$1" cat_name=""
    categorize_file "$f" cat_name
    case "$cat_name" in
        Imagenes|Videos|Audio) return 0 ;;
        Documentos) [[ "${f:l}" != *.(txt|md|rtf|csv) ]] ;;   # léeme de programas
        *) return 1 ;;
    esac
}

# compute_protected_dirs SOURCE_DIR ARCHIVO...
# (los archivos vienen de scan_files; las entradas llamadas ".git" son carpetas)
compute_protected_dirs() {
    local src="$1"; shift
    local f d r p lname comp acc
    local -A prot=() user=() total=()
    local -i is_user
    PROT_SET=()
    PROTECTED_DIRS=()

    for f in "$@"; do
        d="${f:h}"
        lname="${${f:t}:l}"

        if [[ "${f:t}" == ".git" ]]; then
            [[ "$d" != "$src" ]] && prot[$d]="proyecto de código (git)"
            continue
        fi

        r="/${f#$src/}"
        if [[ "$r" == */node_modules/* ]]; then
            p="${r%%/node_modules/*}"
            [[ -n "$p" ]] && prot[$src$p]="proyecto de código (node_modules)"
        fi
        if [[ "${r:l}" == */*.(app|photoslibrary|fcpbundle|imovielibrary|aplibrary|musiclibrary|tvlibrary|logicx|band|xcodeproj)/* ]]; then
            acc="$src"
            for comp in "${(@s:/:)${r#/}}"; do
                acc+="/$comp"
                if [[ "${comp:l}" == *.xcodeproj ]]; then
                    [[ "${acc:h}" != "$src" ]] && prot[${acc:h}]="proyecto de código (Xcode)"
                    break
                elif [[ "${comp:l}" == *.(app|photoslibrary|fcpbundle|imovielibrary|aplibrary|musiclibrary|tvlibrary|logicx|band) ]]; then
                    prot[$acc]="paquete de macOS"
                    break
                fi
            done
        fi
        if [[ "$d" != "$src" ]]; then
            if (( ${PROJECT_MARKER_FILES[(Ie)$lname]} )) || [[ "$lname" == *.(sln|csproj|vcxproj) ]]; then
                prot[$d]="proyecto de código"
            elif [[ "$lname" == *.(dll|cab|msi|sys|ocx) ]]; then
                [[ -z "${prot[$d]:-}" ]] && prot[$d]="programa o juego"
            fi
        fi

        # Conteos por carpeta (para decidir si la protección sube al padre)
        is_user=0
        _is_user_content "$f" && is_user=1
        p="$d"
        while [[ "$p" == "$src"/* ]]; do
            # (no usar (( user[$p]++ )): falla con rutas que contienen "]" u otros símbolos)
            total[$p]=$(( ${total[$p]:-0} + 1 ))
            (( is_user )) && user[$p]=$(( ${user[$p]:-0} + 1 ))
            p="${p:h}"
        done
    done

    (( ${#prot} )) || return 0

    # Quitar las anidadas (quedarse con la más externa)
    local -a kept=()
    local k anc nested
    for k in ${(ok)prot}; do
        nested=false
        for anc in "${kept[@]}"; do
            [[ "$k" == "$anc"/* ]] && { nested=true; break; }
        done
        [[ "$nested" == "false" ]] && kept+=("$k")
    done

    # Subir la protección mientras el padre no tenga contenido personal propio
    local changed=true parent reason
    local -i inside_user user_out
    while [[ "$changed" == "true" ]]; do
        changed=false
        for k in "${kept[@]}"; do
            parent="${k:h}"
            [[ "$parent" == "$src" || "$parent" != "$src"/* ]] && continue
            inside_user=0
            for anc in "${kept[@]}"; do
                [[ "$anc" == "$parent"/* ]] && (( inside_user += ${user[$anc]:-0} ))
            done
            user_out=$(( ${user[$parent]:-0} - inside_user ))
            if (( user_out <= PROTECT_MAX_PERSONAL && user_out * 100 <= PROTECT_MAX_PERSONAL_PCT * ${total[$parent]:-1} )); then
                reason="${prot[$k]}"
                prot[$parent]="$reason"
                kept=("$parent" ${kept:#$parent/*})
                changed=true
                break
            fi
        done
    done

    PROTECTED_DIRS=(${(o)kept})
    for k in "${PROTECTED_DIRS[@]}"; do
        PROT_SET[$k]="${prot[$k]}"
    done
}

# ¿La ruta está dentro de una carpeta protegida?
is_protected_path() {
    (( ${#PROT_SET} )) || return 1
    local p="${1:h}"
    while [[ "$p" == "$SOURCE_DIR"/* ]]; do
        (( ${+PROT_SET[$p]} )) && return 0
        p="${p:h}"
    done
    return 1
}
