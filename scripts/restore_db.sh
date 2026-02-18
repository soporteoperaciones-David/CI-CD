#!/bin/bash
set -e

# --- VARIABLES RECIBIDAS ---
# NEW_DB_NAME
# DB_OWNER
# LOCAL_BACKUP_FILE

SYSTEM_USER="ubuntu"
TARGET_DIR="/home/$SYSTEM_USER/backups_odoo"

echo "--- Iniciando Restauración Inteligente ---"


if [[ "$NEW_DB_NAME" == *"salesianos"* ]]; then
    echo ">> 🔵 Detectado proyecto SALESIANOS. Usando PostgreSQL 12..."
    PG_BIN="/usr/lib/postgresql/12/bin"
else
    echo ">> 🟢 Proyecto Estandar. Usando PostgreSQL 17..."
    PG_BIN="/usr/lib/postgresql/17/bin"
fi

# Definimos los comandos con la ruta absoluta
CMD_PSQL="$PG_BIN/psql"
CMD_RESTORE="$PG_BIN/pg_restore"
CMD_CREATEDB="$PG_BIN/createdb"
CMD_DROPDB="$PG_BIN/dropdb"

# preparar archivos
sudo mkdir -p "$TARGET_DIR"
sudo mv "/tmp/$LOCAL_BACKUP_FILE" "$TARGET_DIR/"
sudo chown -R "$SYSTEM_USER:$SYSTEM_USER" "$TARGET_DIR"
FULL_PATH="$TARGET_DIR/$LOCAL_BACKUP_FILE"


echo ">> Recreando base de datos $NEW_DB_NAME..."

# Usamos el binario seleccionado ($CMD_DROPDB)
sudo -u postgres $CMD_DROPDB --if-exists "$NEW_DB_NAME"
sudo -u postgres $CMD_CREATEDB -O "$DB_OWNER" "$NEW_DB_NAME"


if [[ "$LOCAL_BACKUP_FILE" == *".dump" ]]; then
    echo ">> Restaurando DUMP con $CMD_RESTORE ..."
    sudo -u postgres $CMD_RESTORE --no-owner --role="$DB_OWNER" -d "$NEW_DB_NAME" "$FULL_PATH" || echo "Advertencia: Error menor de versión ignorado (transaction_timeout u otros)."
    
elif [[ "$LOCAL_BACKUP_FILE" == *".sql" ]]; then
    echo ">> Restaurando SQL con $CMD_PSQL ..."
    sudo -u postgres $CMD_PSQL -d "$NEW_DB_NAME" -f "$FULL_PATH" || echo "Advertencia en SQL..."
fi

echo "Restauración Completada: $NEW_DB_NAME"