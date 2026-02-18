#!/bin/bash

# scripts/notify_odoo.sh
# Uso: ./notify_odoo.sh <RECORD_ID> <STATE> <URL> <MENSAJE>

RECORD_ID=$1
STATE=$2
BACKUP_URL=$3
LOG_MSG=$4

# 1. Configuración (OJO: Estas variables vendrán del entorno de Jenkins por seguridad)
# Si quieres, puedes hardcodearlas aquí, pero es mejor leerlas del ENV como haremos abajo.
: "${ODOO_URL:?Falta la variable ODOO_URL}"
: "${ODOO_DB:?Falta la variable ODOO_DB}"
: "${ODOO_PASS:?Falta la variable ODOO_PASS}" # Esta es la API KEY

# El ID del usuario admin suele ser 2. Si es otro, cámbialo aquí.
ODOO_UID=2 
MODEL_NAME="backup.automation" # Tu modelo (según tu código antiguo)

if [ -z "$RECORD_ID" ] || [ "$RECORD_ID" -eq 0 ]; then
    echo "⚠️ No hay RECORD_ID (Valor: $RECORD_ID). Omitiendo actualización de Odoo."
    exit 0
fi

echo "--- Notificando a Odoo ($ODOO_URL) ---"
echo "ID: $RECORD_ID | Estado: $STATE"

# 2. Construir el JSON Payload
# Usamos printf para evitar problemas con comillas
PAYLOAD=$(cat <<EOF
{
    "jsonrpc": "2.0",
    "method": "call",
    "params": {
        "service": "object",
        "method": "execute_kw",
        "args": [
            "${ODOO_DB}",
            ${ODOO_UID},
            "${ODOO_PASS}",
            "${MODEL_NAME}",
            "write",
            [
                [${RECORD_ID}],
                {
                    "state": "${STATE}",
                    "backup_url": "${BACKUP_URL}",
                    "log_notes": "${LOG_MSG}"
                }
            ]
        ]
    }
}
EOF
)

# 3. Ejecutar CURL
RESPONSE=$(curl -s -X POST \
     -H "Content-Type: application/json" \
     -d "$PAYLOAD" \
     "${ODOO_URL}/jsonrpc")

echo "Respuesta Odoo: $RESPONSE"