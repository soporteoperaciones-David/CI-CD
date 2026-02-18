#!/bin/bash
set -e

# El Smart Naming ahora es más simple porque el sshagent ya cargó la llave
CANDIDATE="${BASE_NAME}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
COUNTER=1

echo ">> [SmartNaming] Buscando: $CANDIDATE" >&2

# Usamos la conexión directa. El comando 'ssh' usará automáticamente la llave del agente.
while ssh -4 -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$TARGET_IP "sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw $CANDIDATE"; do
    COUNTER=$((COUNTER+1))
    CANDIDATE="${BASE_NAME}_v${COUNTER}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
    echo ">> [SmartNaming] Ocupado, probando: $CANDIDATE" >&2
done

echo "$CANDIDATE"