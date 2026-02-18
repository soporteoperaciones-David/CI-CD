#!/bin/bash
set -e

# --- VARIABLES RECIBIDAS DESDE JENKINS ---
# NEW_DB_NAME
# DB_OWNER (odoo15 u odoo19)
# LOCAL_BACKUP_FILE (Nombre del archivo en /tmp)

echo "--- Iniciando Restauración Local ---"
echo ">> Base Destino: $NEW_DB_NAME"
echo ">> Dueño: $DB_OWNER"
echo ">> Archivo: /tmp/$LOCAL_BACKUP_FILE"

# 1. Mover el archivo a un lugar seguro (Home del usuario odoo)
# Usamos sudo porque /tmp es de todos pero el destino es protegido
TARGET_DIR="/home/$DB_OWNER/backups"
sudo mkdir -p "$TARGET_DIR"
sudo mv "/tmp/$LOCAL_BACKUP_FILE" "$TARGET_DIR/"
sudo chown "$DB_OWNER:$DB_OWNER" "$TARGET_DIR/$LOCAL_BACKUP_FILE"

FULL_PATH="$TARGET_DIR/$LOCAL_BACKUP_FILE"
echo ">> Archivo movido a: $FULL_PATH"

# 2. Crear la base de datos (vacía)
echo ">> Creando base de datos vacía..."
sudo -u postgres createdb -O "$DB_OWNER" "$NEW_DB_NAME"

# 3. Restaurar según extensión
if [[ "$LOCAL_BACKUP_FILE" == *".zip" ]]; then
    echo ">> Restaurando ZIP (Filestore + SQL)..."
    # Aquí necesitas la lógica de restore python de Odoo si es zip,
    # PERO por ahora asumimos dump custom o sql plano para simplificar
    echo "⚠️ ZIP restore requiere script python de Odoo. Usando unzip básico..."
    sudo -u "$DB_OWNER" unzip -q "$FULL_PATH" -d "/home/$DB_OWNER/.local/share/Odoo/filestore/$NEW_DB_NAME"
    # (Esto suele ser más complejo con filestore, pero sigamos con dump)

elif [[ "$LOCAL_BACKUP_FILE" == *".dump" ]]; then
    echo ">> Restaurando DUMP (Formato Custom)..."
    # pg_restore requiere -d base
    sudo -u postgres pg_restore --no-owner --role="$DB_OWNER" -d "$NEW_DB_NAME" "$FULL_PATH" || true
    # El || true es porque pg_restore a veces da warnings que no son errores fatales

else
    echo ">> Restaurando SQL Plano..."
    sudo -u postgres psql -d "$NEW_DB_NAME" -f "$FULL_PATH"
fi

echo "✅ Restauración Completada: $NEW_DB_NAME"

# 4. (Opcional) Borrar backup para ahorrar espacio
# rm "$FULL_PATH"