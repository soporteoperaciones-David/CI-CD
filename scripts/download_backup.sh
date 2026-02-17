#!/bin/bash
set -e

# --- CONFIGURACIÓN DE IDs (TUS IDs) ---
ID_INTEGRALIS_15="17hZ4JVz3pR7Ww258F3UgHD7O6cihTbJd"
ID_SALESIANOS_15="1ZpP2o_b9BFX_3fhAZeILRvkJCbFINhlL"
ID_INTEGRALIS_19="1V9ZhfgBu9AlFilRGabihnPC6fJeUxpmg"
ID_DICS_15="1-6ghqjTGsd3fvFAi3-TA1uNe-YGTNYwI"

# --- 1. Determinar carpeta y NOMBRE BASE ---
echo "--- Analizando Dominio: $ODOO_URL ---"

# Extraemos el subdominio para usarlo como filtro (ej: https://carros.sdb... -> carros)
# Esto asume que el nombre del archivo backup contiene el nombre del subdominio
DB_NAME_FILTER=$(echo "$ODOO_URL" | sed -e 's|^[^/]*//||' -e 's|/.*$||' | cut -d. -f1)
echo ">> Filtro de nombre detectado: $DB_NAME_FILTER"

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

# --- 2. Calcular Fecha ---
if [ "$BACKUP_DATE" == "latest" ] || [ -z "$BACKUP_DATE" ]; then
    SEARCH_DATE=$(date -d "yesterday" +%Y%m%d)
    echo ">> Modo Automático: Buscando backup de AYER ($SEARCH_DATE)"
else
    SEARCH_DATE="$BACKUP_DATE"
    echo ">> Modo Manual: Buscando backup de fecha $SEARCH_DATE"
fi

# --- 3. Buscar y Descargar con Rclone ---
echo "--- Buscando archivo en Drive... ---"
REMOTE_NAME="gdrive-jenkins"

echo ">> Buscando patrón: *$DB_NAME_FILTER*$SEARCH_DATE*"

# AQUI ESTA EL CAMBIO: Agregamos $DB_NAME_FILTER al include
FILE_PATH=$(rclone lsf "$REMOTE_NAME,root_folder_id=$TARGET_FOLDER_ID:respaldos" --recursive --files-only --include "*${DB_NAME_FILTER}*${SEARCH_DATE}*.dump" --include "*${DB_NAME_FILTER}*${SEARCH_DATE}*.tar.gz" | head -n 1)

if [ -z "$FILE_PATH" ]; then
    echo "❌ ERROR: No se encontró backup para '$DB_NAME_FILTER' con fecha $SEARCH_DATE."
    echo "   Verifica que el nombre del archivo en Drive contenga '$DB_NAME_FILTER'."
    exit 1
fi

FILENAME=$(basename "$FILE_PATH")
echo "✅ Archivo encontrado: $FILENAME"

echo "--- Descargando... ---"
rclone copy "$REMOTE_NAME,root_folder_id=$TARGET_FOLDER_ID:respaldos/$FILE_PATH" /workspace/ -P

# --- 4. Preparar Salida ---
if [[ "$FILENAME" == *".tar.gz" ]]; then
    echo ">> Descomprimiendo $FILENAME..."
    tar -xzvf "/workspace/$FILENAME" -C /workspace/
    DUMP_FILE=$(find /workspace -name "*.dump" | head -n 1)
    FILENAME=$(basename "$DUMP_FILE")
fi

echo "$FILENAME" > /workspace/filename.txt

# Limpiamos el nombre para sacar la base (quitamos fechas y extensiones)
CLEAN_DB_NAME=$(echo "$FILENAME" | sed -E 's/_?[0-9]{8}.*//')
echo "$CLEAN_DB_NAME" > /workspace/dbname.txt

chmod 666 "/workspace/$FILENAME"
echo "✅ Descarga completada."


