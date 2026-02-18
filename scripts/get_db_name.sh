#!/bin/bash
set -e

# Recibe la ruta de la llave desde la variable que exportamos en el pipeline
KEY_PATH="$SSH_KEY_FILE" 

CANDIDATE="${BASE_NAME}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
COUNTER=1

# Bucle usando la llave (-i)
while ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@$TARGET_IP "sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw $CANDIDATE"; do
    COUNTER=$((COUNTER+1))
    CANDIDATE="${BASE_NAME}_v${COUNTER}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
done

echo "$CANDIDATE"