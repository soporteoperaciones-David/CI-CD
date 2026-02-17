#!/bin/bash
set -e
apt-get update -qq && apt-get install -y sshpass openssh-client -qq
export SSHPASS="$MY_SSH_PASS"

# Variables que vienen del entorno de Jenkins
FILE_NAME="$LOCAL_BACKUP_FILE"
TARGET_IP="$TARGET_IP_FINAL"
DB_TARGET="$NEW_DB_NAME"
OWNER="$DB_OWNER"

echo "--- 1. Subiendo archivo .dump a $TARGET_IP ---"
sshpass -e scp -o StrictHostKeyChecking=no "/workspace/$FILE_NAME" ubuntu@$TARGET_IP:/home/ubuntu/

echo "--- 2. Conectando y Restaurando (Remoto) ---"
# Aquí enviamos las variables locales al entorno remoto antes de ejecutar bash
sshpass -e ssh -o StrictHostKeyChecking=no ubuntu@$TARGET_IP \
"FILE_NAME='$FILE_NAME' DB_TARGET='$DB_TARGET' OWNER='$OWNER' sudo bash -s" <<'EOF'

    # --- ESTO SE EJECUTA EN EL SERVIDOR REMOTO ---
    SOURCE_PATH="/home/ubuntu/$FILE_NAME"
    DEST_DIR="/opt/backup_integralis"
    DEST_PATH="$DEST_DIR/$FILE_NAME"
    
    # Mover a carpeta destino
    mkdir -p $DEST_DIR
    [ -f "$SOURCE_PATH" ] && mv $SOURCE_PATH $DEST_PATH
    chmod 644 $DEST_PATH
    
    # Detectar binario
    PG_BIN="pg_restore"
    [ -f "/usr/lib/postgresql/17/bin/pg_restore" ] && PG_BIN="/usr/lib/postgresql/17/bin/pg_restore"
    [ -f "/usr/lib/postgresql/14/bin/pg_restore" ] && PG_BIN="/usr/lib/postgresql/14/bin/pg_restore"
    
    echo ">> Recreando DB: $DB_TARGET (Dueño: $OWNER)"
    sudo -u postgres dropdb $DB_TARGET --if-exists
    sudo -u postgres createdb -O $OWNER $DB_TARGET
    
    echo ">> Restaurando con $PG_BIN..."
    sudo -u postgres $PG_BIN \
        --dbname=$DB_TARGET \
        --clean --no-acl --no-owner \
        --role=$OWNER \
        --verbose \
        $DEST_PATH > /tmp/pg_restore.log 2>&1 || echo "⚠️ Alerta en restore"
        
    tail -n 5 /tmp/pg_restore.log
    echo "RESTAURACIÓN COMPLETADA"
EOF