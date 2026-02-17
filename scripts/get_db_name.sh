#!/bin/bash
set -e

# Requiere las siguientes variables de entorno:
# - MY_SSH_PASS
# - TARGET_IP
# - BASE_NAME (nombre limpio de la base)
# - DATE_SUFFIX (fecha YYYYMMDD)
# - ODOO_SUFFIX (ee15n2 o ee19)

export SSHPASS="$MY_SSH_PASS"

# 1. Construir el primer candidato (Ej: pioxii-20260217-ee15n2)
CANDIDATE="${BASE_NAME}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
COUNTER=1

# Mensajes de log a stderr (>&2) para no ensuciar la salida final
echo ">> [SmartNaming] Buscando nombre disponible para base: ${BASE_NAME}..." >&2

# 2. Bucle: Mientras la base exista en Postgres remoto...
# Usamos 'grep -qw' para buscar la palabra exacta y evitar falsos positivos
while sshpass -e ssh -o StrictHostKeyChecking=no ubuntu@$TARGET_IP "sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw $CANDIDATE"; do
    COUNTER=$((COUNTER+1))
    
    # Construimos el siguiente candidato: pioxii_v2-20260217-ee15n2
    # NOTA: El _v2 va pegado al nombre base, antes de la fecha
    CANDIDATE="${BASE_NAME}_v${COUNTER}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
    
    echo ">> [SmartNaming] ⚠️ ${CANDIDATE} ya existe. Probando siguiente..." >&2
done

echo ">> [SmartNaming] Nombre Final: ${CANDIDATE}" >&2

# 3. IMPRIMIR SOLO EL NOMBRE FINAL (Esto es lo que captura Jenkins)
echo "$CANDIDATE"