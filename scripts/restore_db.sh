#!/bin/bash
set -e

# --- VARIABLES RECIBIDAS ---
# NEW_DB_NAME
# DB_OWNER
# LOCAL_BACKUP_FILE (Solo el nombre del archivo, ej: backup.dump)

# CAMBIO: Usamos /tmp para evitar bloqueos de permisos con el usuario 'postgres'
TARGET_DIR="/tmp/odoo_restores"

echo "--- Iniciando Restauración Inteligente ---"

# Detectar versión de Postgres según el nombre de la base (Salesianos vs Estándar)
if [[ "$ODOO_URL" == *".sdb-integralis360.com"* || "$NEW_DB_NAME" == *"salesianos"* ]]; then
    echo ">> Detectado proyecto SALESIANOS. Usando PostgreSQL 12..."
    PG_BIN="/usr/lib/postgresql/12/bin"
else
    echo ">> Proyecto Estandar. Usando PostgreSQL 17..."
    PG_BIN="/usr/lib/postgresql/17/bin"
fi

# Definimos los comandos
CMD_PSQL="$PG_BIN/psql"
CMD_RESTORE="$PG_BIN/pg_restore"
CMD_CREATEDB="$PG_BIN/createdb"
CMD_DROPDB="$PG_BIN/dropdb"

# 1. Preparar carpeta destino (Limpia y con permisos abiertos)
sudo mkdir -p "$TARGET_DIR"
sudo chmod 777 "$TARGET_DIR"

# 2. Mover el archivo desde /tmp (donde lo dejó SCP) a nuestra carpeta de trabajo
# OJO: Asumimos que LOCAL_BACKUP_FILE es solo el nombre, no la ruta completa
SOURCE_FILE="/tmp/$LOCAL_BACKUP_FILE"
FULL_PATH="$TARGET_DIR/$LOCAL_BACKUP_FILE"

if [ -f "$SOURCE_FILE" ]; then
    echo ">> Moviendo archivo a zona segura..."
    sudo mv "$SOURCE_FILE" "$FULL_PATH"
else
    # Si ya estaba ahí (por reintentos), verificamos
    if [ ! -f "$FULL_PATH" ]; then
        echo "Error: No encuentro el archivo en $SOURCE_FILE ni en $FULL_PATH"
        exit 1
    fi
fi

# 3. Permisos finales al archivo (Vital para que postgres lo lea)
sudo chmod 644 "$FULL_PATH"
# Opcional: Cambiar dueño a postgres para asegurar lectura
sudo chown postgres:postgres "$FULL_PATH"

echo ">> Recreando base de datos $NEW_DB_NAME..."

# Borrar y crear la DB con owner temporal "postgres": el usuario de Odoo
# todavía no debe poder verla ni conectarse mientras se restaura.
sudo -u postgres $CMD_DROPDB --if-exists -- "$NEW_DB_NAME"
sudo -u postgres $CMD_CREATEDB -O postgres -- "$NEW_DB_NAME"

# Revocamos conexión al usuario de Odoo mientras dura el restore, para que
# ningún worker se enganche a la base a medio restaurar y dispare
# cron/correo antes de tiempo (eso era lo que forzaba el reinicio manual).
echo ">> Bloqueando conexiones de $DB_OWNER a $NEW_DB_NAME durante el proceso..."
sudo -u postgres $CMD_PSQL -c "REVOKE CONNECT ON DATABASE \"$NEW_DB_NAME\" FROM PUBLIC, \"$DB_OWNER\";"

# Restaurar (queda todo cargado bajo el owner "postgres", sin reasignar
# ownership desde el dump)
if [[ "$LOCAL_BACKUP_FILE" == *".dump" ]]; then
    echo ">> Restaurando DUMP con $CMD_RESTORE ..."
    # Agregamos verbose leve y manejo de error
    sudo -u postgres $CMD_RESTORE --verbose --no-owner -j 4 -d "$NEW_DB_NAME" -- "$FULL_PATH" || echo "⚠️ Advertencia: pg_restore finalizó con advertencias (ignorando errores no críticos)."

elif [[ "$LOCAL_BACKUP_FILE" == *".sql" ]]; then
    echo ">> Restaurando SQL con $CMD_PSQL ..."
    sudo -u postgres $CMD_PSQL -d "$NEW_DB_NAME" -f "$FULL_PATH" || echo "⚠️ Advertencia en SQL..."
fi

# Desactivamos correo (entrada y salida) y cron ANTES de entregarle la base
# al usuario de Odoo, para que no dispare nada automático al reconectarse.
echo ">> Desactivando servidores de correo (entrada/salida) en $NEW_DB_NAME..."
sudo -u postgres $CMD_PSQL -d "$NEW_DB_NAME" -c "UPDATE ir_mail_server SET active = false;" || echo "⚠️ No se pudo desactivar ir_mail_server (¿tabla inexistente?)."
sudo -u postgres $CMD_PSQL -d "$NEW_DB_NAME" -c "UPDATE fetchmail_server SET active = false;" || echo "⚠️ No se pudo desactivar fetchmail_server (¿tabla inexistente?)."

echo ">> Desactivando cron en $NEW_DB_NAME..."
sudo -u postgres $CMD_PSQL -d "$NEW_DB_NAME" -c "UPDATE ir_cron SET active = false;" || echo "⚠️ No se pudo desactivar ir_cron (¿tabla inexistente?)."

# Recién ahora le entregamos la base al usuario de Odoo: cambiamos el owner
# definitivo y reabrimos la conexión para que el servicio la reconozca.
echo ">> Asignando owner definitivo ($DB_OWNER) a $NEW_DB_NAME..."
sudo -u postgres $CMD_PSQL -c "ALTER DATABASE \"$NEW_DB_NAME\" OWNER TO \"$DB_OWNER\";"

echo ">> Restaurando permisos de conexión a $NEW_DB_NAME..."
sudo -u postgres $CMD_PSQL -c "GRANT CONNECT ON DATABASE \"$NEW_DB_NAME\" TO PUBLIC, \"$DB_OWNER\";"

# Limpieza final (Opcional, para no llenar el disco)
# sudo rm "$FULL_PATH"

echo "Restauración Completada: $NEW_DB_NAME"