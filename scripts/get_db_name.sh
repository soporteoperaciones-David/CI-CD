#!/bin/bash
set -e

# 1. Validar que recibimos el nombre base (para evitar nombres como "-2026-ee15")
if [ -z "$BASE_NAME" ]; then
    # Si por alguna razón llega vacío, le ponemos un nombre por defecto
    BASE_NAME="db_recuperada"
fi

# 2. Limpieza de seguridad: Quitar guiones al principio del nombre
# (Si el nombre empieza con guion, Postgres cree que es el parámetro "-1" y falla)
SAFE_BASE_NAME=$(echo "$BASE_NAME" | sed 's/^-*//')

# 3. Construir candidato
KEY_PATH="$SSH_KEY_FILE"
CANDIDATE="${SAFE_BASE_NAME}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
COUNTER=1

# echo ">> Comprobando disponibilidad de: $CANDIDATE" >&2

# 4. Bucle para evitar duplicados en Postgres
while ssh -4 -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@$TARGET_IP "sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw $CANDIDATE"; do
    COUNTER=$((COUNTER+1))
    CANDIDATE="${SAFE_BASE_NAME}_v${COUNTER}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
done

# 5. Imprimir el nombre final (Jenkins captura esta última línea)
echo "$CANDIDATE"