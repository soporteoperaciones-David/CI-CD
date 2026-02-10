#!/bin/bash
set -e
# Instalamos dependencias
apt-get update -qq && apt-get install -y curl python3 iproute2 -qq

# Validaciones
if [ -z "$MASTER_PWD" ]; then
    echo "Error: MASTER_PWD no está definida."
    exit 1
fi

echo "--- Consultando Odoo en: $ODOO_URL ---"

# 1. Obtener nombre de la base
DB_JSON=$(curl -s -k -X POST "https://$ODOO_URL/web/database/list" \
    -H "Content-Type: application/json" \
    -d '{"params": {"master_pwd": "'"$MASTER_PWD"'"}}')

if echo "$DB_JSON" | grep -q "Access Denied"; then
    echo "Contraseña maestra rechazada al listar."
    exit 1
fi

# Usamos el script de python que está en la misma carpeta
DB_NAME=$(echo "$DB_JSON" | python3 /workspace/extract.py)
echo "Base detectada: $DB_NAME"

# 2. Preparar nombre de archivo
DATE=$(date +%Y%m%d)
# BACKUP_TYPE viene de Jenkins como variable de entorno
EXT="zip"
if [ "$BACKUP_TYPE" == "dump" ]; then
    EXT="dump"
fi
FILENAME="backup_${DB_NAME}-${DATE}.${EXT}"

# 3. Descargar
echo "--- Descargando archivo: $FILENAME ---"
curl -k -X POST \
    --form-string "master_pwd=$MASTER_PWD" \
    --form-string "name=$DB_NAME" \
    --form-string "backup_format=$BACKUP_TYPE" \
    "https://$ODOO_URL/web/database/backup" \
    -o "/workspace/$FILENAME"

# 4. Validaciones finales
if grep -q "Database backup error" "/workspace/$FILENAME"; then
    echo "Odoo rechazó la descarga (Access Denied)."
    exit 1
fi

if [ ! -s "/workspace/$FILENAME" ]; then
    echo "Archivo vacío."
    exit 1
fi

# Guardar metadatos para el siguiente stage
echo "$FILENAME" > /workspace/filename.txt
echo "$DB_NAME" > /workspace/dbname.txt
chmod 666 "/workspace/$FILENAME"