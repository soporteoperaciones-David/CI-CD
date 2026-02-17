#!/bin/bash
set -e

# --- CONFIGURACIÓN DE IDs (¡PON TUS IDs AQUÍ!) ---
ID_INTEGRALIS_15="17hZ4JVz3pR7Ww258F3UgHD7O6cihTbJd"
ID_SALESIANOS_15="1ZpP2o_b9BFX_3fhAZeILRvkJCbFINhlL"
ID_INTEGRALIS_19="1V9ZhfgBu9AlFilRGabihnPC6fJeUxpmg"
ID_DICS_15="1-6ghqjTGsd3fvFAi3-TA1uNe-YGTNYwI"

# --- 1. Determinar qué carpeta usar según el dominio ---
echo "--- Analizando Dominio: $ODOO_URL ---"

if [[ "$ODOO_URL" == *".sdb-integralis360.com"* ]]; then
    TARGET_FOLDER_ID="$ID_SALESIANOS_15"
    echo ">> Detectado: Salesianos (ID: $TARGET_FOLDER_ID)"
    
elif [[ "$ODOO_URL" == *".dic-integralis360.com"* ]]; then
    TARGET_FOLDER_ID="$ID_DICS_15"
    echo ">> Detectado: DICs (ID: $TARGET_FOLDER_ID)"

elif [[ "$VERSION" == "v19" ]]; then
    TARGET_FOLDER_ID="$ID_INTEGRALIS_19"
    echo ">> Detectado: Integralis v19 (ID: $TARGET_FOLDER_ID)"

else
    TARGET_FOLDER_ID="$ID_INTEGRALIS_15"
    echo ">> Default: Integralis v15 (ID: $TARGET_FOLDER_ID)"
fi

# --- 2. Calcular Fecha del Backup ---
# Si BACKUP_DATE viene como 'latest', usamos la fecha de AYER (formato YYYYMMDD)
# Si viene una fecha específica, usamos esa.

if [ "$BACKUP_DATE" == "latest" ] || [ -z "$BACKUP_DATE" ]; then
    SEARCH_DATE=$(date -d "yesterday" +%Y%m%d)
    echo ">> Modo Automático: Buscando backup de AYER ($SEARCH_DATE)"
else
    SEARCH_DATE="$BACKUP_DATE"
    echo ">> Modo Manual: Buscando backup de fecha $SEARCH_DATE"
fi

# --- 3. Buscar y Descargar con Rclone ---
echo "--- Buscando archivo en Drive... ---"

# Configurar Rclone (Jenkins inyectará el archivo conf en /root/.config/rclone/rclone.conf)
# El remoto se llama 'gdrive-jenkins' (o como lo hayas puesto en rclone config)
REMOTE_NAME="gdrive-jenkins" 

# Listamos archivos que coincidan con la fecha y sean .dump o .tar.gz
# Buscamos recursivamente dentro de la carpeta 'respaldos' de ese ID
# Estructura supuesta: ID_CARPETA -> respaldos -> nombre_base -> archivo

echo ">> Buscando patrón: *$SEARCH_DATE*"

# Primero, intentamos encontrar el archivo exacto.
# Usamos --include para filtrar por fecha y extensión
# gdrive-jenkins,root_folder_id=XXX:respaldos
FILE_PATH=$(rclone lsf "$REMOTE_NAME,root_folder_id=$TARGET_FOLDER_ID:respaldos" --recursive --files-only --include "*$SEARCH_DATE*.dump" --include "*$SEARCH_DATE*.tar.gz" | head -n 1)

if [ -z "$FILE_PATH" ]; then
    echo "ERROR: No se encontró ningún backup con la fecha $SEARCH_DATE en la carpeta seleccionada."
    echo "   Intenta con otra fecha o verifica que el backup de ayer se haya subido."
    exit 1
fi

FILENAME=$(basename "$FILE_PATH")
echo "Archivo encontrado: $FILENAME"
echo ">> Ruta en Drive: $FILE_PATH"

echo "--- Descargando... ---"
rclone copy "$REMOTE_NAME,root_folder_id=$TARGET_FOLDER_ID:respaldos/$FILE_PATH" /workspace/ -P

# --- 4. Preparar Salida ---
# Si es tar.gz, descomprimimos para sacar el dump
if [[ "$FILENAME" == *".tar.gz" ]]; then
    echo ">> Descomprimiendo $FILENAME..."
    tar -xzvf "/workspace/$FILENAME" -C /workspace/
    # Buscamos el .dump resultante
    DUMP_FILE=$(find /workspace -name "*.dump" | head -n 1)
    FILENAME=$(basename "$DUMP_FILE")
fi

echo "$FILENAME" > /workspace/filename.txt
# Extraemos el nombre de la base del nombre del archivo (ej: pioxii-15_2025... -> pioxii-15)
# Esto es un estimado, puede requerir ajuste según tus nombres exactos
CLEAN_DB_NAME=$(echo "$FILENAME" | sed -E 's/_?[0-9]{8}.*//')
echo "$CLEAN_DB_NAME" > /workspace/dbname.txt

chmod 666 "/workspace/$FILENAME"
echo "Descarga completada."