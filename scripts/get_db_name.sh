#!/bin/bash
set -e
# Recibimos la ruta desde la variable de entorno de Jenkins
KEY_PATH="$SSH_KEY_FILE"

CANDIDATE="${BASE_NAME}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
COUNTER=1

# Bucle con llave SSH (-i)
while ssh -4 -i "$KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$TARGET_IP "sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw $CANDIDATE"; do
    COUNTER=$((COUNTER+1))
    CANDIDATE="${BASE_NAME}_v${COUNTER}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
done
echo "$CANDIDATE"