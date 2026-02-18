#!/bin/bash
set -e

# Recibimos la ruta de la llave en vez del password
KEY_PATH="$SSH_KEY_FILE"

echo ">> [SmartNaming] Buscando nombre disponible para base: ${BASE_NAME}..." >&2

# Construir primer candidato
CANDIDATE="${BASE_NAME}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
COUNTER=1

# Bucle usando SSH con Llave (-i) y forzando IPv4 (-4)
# Nota: Quitamos sshpass y usamos la llave directa
while ssh -4 -i "$KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$TARGET_IP "sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw $CANDIDATE"; do
    COUNTER=$((COUNTER+1))
    CANDIDATE="${BASE_NAME}_v${COUNTER}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
    echo ">> [SmartNaming] ⚠️ ${CANDIDATE} ya existe. Probando siguiente..." >&2
done

echo ">> [SmartNaming] Nombre Final: ${CANDIDATE}" >&2
echo "$CANDIDATE"