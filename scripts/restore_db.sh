#!/bin/bash
set -e

# --- VARIABLES RECIBIDAS ---
# NEW_DB_NAME
# DB_OWNER (odoo15 u odoo19) -> ESTO ES SOLO PARA POSTGRES
# LOCAL_BACKUP_FILE

# Definimos un usuario de SISTEMA seguro para guardar los archivos
SYSTEM_USER="ubuntu"
TARGET_DIR="/home/$SYSTEM_USER/backups_odoo"

echo "--- Iniciando Restauración ---"
echo ">> Base PostgreSQL: $NEW_DB_NAME"
echo ">> Dueño DB (Role): $DB_OWNER"
echo ">> Usuario Sistema para archivos: $SYSTEM_USER"

# 1. Preparar carpeta segura en el home de ubuntu
sudo mkdir -p "$TARGET_DIR"
# Movemos el archivo
sudo mv "/tmp/$LOCAL_BACKUP_FILE" "$TARGET_DIR/"
# Asignamos permisos al usuario ubuntu (que SÍ existe)
sudo chown -R "$SYSTEM_USER:$SYSTEM_USER" "$TARGET_DIR"

FULL_PATH="$TARGET_DIR/$LOCAL_BACKUP_FILE"
echo ">> Archivo listo en: $FULL_PATH"

# 2. Crear la base de datos (Usando el rol de postgres)
echo ">> Creando base de datos vacía..."
# Aquí usamos $DB_OWNER (odoo15) solo para el ownership de la BD
sudo -u postgres createdb -O "$DB_OWNER" "$NEW_DB_NAME"

# 3. Restaurar
if [[ "$LOCAL_BACKUP_FILE" == *".dump" ]]; then
    echo ">> Restaurando DUMP..."
    # Ejecutamos pg_restore como usuario postgres
    # --role=$DB_OWNER asegura que los objetos sean creados a nombre de odoo15
    sudo -u postgres pg_restore --no-owner --role="$DB_OWNER" -d "$NEW_DB_NAME" "$FULL_PATH" || true
    
elif [[ "$LOCAL_BACKUP_FILE" == *".sql" ]]; then
    echo ">> Restaurando SQL..."
    sudo -u postgres psql -d "$NEW_DB_NAME" -f "$FULL_PATH"
fi

echo "✅ Restauración Completada: $NEW_DB_NAME"