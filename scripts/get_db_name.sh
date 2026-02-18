#!/bin/bash
set -e

# Recibimos la ruta de la llave desde Jenkins
KEY_PATH="$SSH_KEY_FILE"

CANDIDATE="${BASE_NAME}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
COUNTER=1

echo ">> [SmartNaming] Buscando: $CANDIDATE" >&2

# Usamos -i "$KEY_PATH" para usar la llave temporal de Jenkins
while ssh -4 -i "$KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$TARGET_IP "sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw $CANDIDATE"; do
    COUNTER=$((COUNTER+1))
    CANDIDATE="${BASE_NAME}_v${COUNTER}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
    echo ">> [SmartNaming] Ocupado. Probando: $CANDIDATE" >&2
done

echo "$CANDIDATE"