#!/bin/bash
set -e

DB_NAME=$1

if [ -z "$DB_NAME" ]; then
    echo "Error: No se especificó el nombre de la base de datos."
    exit 1
fi

echo "--- Iniciando Protocolo de Autodestrucción para: $DB_NAME ---"

# Detectar versión de Postgres (Si el nombre contiene 'salesianos' o 'sdb')
if [[ "$DB_NAME" == *"salesianos"* || "$DB_NAME" == *"sdb"* ]]; then
    echo ">> Detectado proyecto SALESIANOS. Usando PostgreSQL 12..."
    PG_BIN="/usr/lib/postgresql/12/bin"
else
    echo ">>Proyecto Estandar. Usando PostgreSQL 17..."
    PG_BIN="/usr/lib/postgresql/17/bin"
fi

CMD_DROPDB="$PG_BIN/dropdb"

# Verificamos si la base existe antes de intentar borrarla
if sudo -u postgres $PG_BIN/psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo ">> Borrando base de datos en Postgres..."
    sudo -u postgres $CMD_DROPDB --if-exists --force -- "$DB_NAME"
    echo "Base de datos $DB_NAME eliminada de Postgres."
else
    echo "La base de datos $DB_NAME ya no existe en Postgres. Nada que borrar."
fi

# LIMPIEZA DE FILESTORE (Ajusta la ruta si tu filestore está en otro lado)
FILESTORE_PATH="/home/ubuntu/.local/share/Odoo/filestore/$DB_NAME"
if [ -d "$FILESTORE_PATH" ]; then
    echo ">>Borrando Filestore..."
    sudo rm -rf "$FILESTORE_PATH"
    echo "Filestore eliminado."
fi

echo "Autodestrucción completada."