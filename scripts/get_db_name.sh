#!/bin/bash
# Ya no necesitamos KEY_PATH porque ssh-agent maneja la llave
CANDIDATE="${BASE_NAME}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
COUNTER=1

# Intentamos conectar usando la identidad cargada en el agente
while ssh -4 -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$TARGET_IP "sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw $CANDIDATE"; do
    COUNTER=$((COUNTER+1))
    CANDIDATE="${BASE_NAME}_v${COUNTER}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
done

echo "$CANDIDATE"