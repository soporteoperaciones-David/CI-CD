#!/bin/bash

# Recibe argumentos: ID, ESTADO, URL, MENSAJE
RECORD_ID=$1
STATE=$2
BACKUP_URL=$3
LOG_MSG=$4

# Variables de entorno inyectadas por Jenkins
# ODOO_URL, ODOO_DB, ODOO_PASS (API Key)

ODOO_UID=2  # ID del admin, cámbialo si tu usuario bot tiene otro ID
MODEL_NAME="restauraciones.test" # <--- CAMBIA ESTO POR EL NOMBRE DE TU MODELO (ej. backup.automation)

if [ -z "$RECORD_ID" ] || [ "$RECORD_ID" = "null" ] || [ "$RECORD_ID" -eq 0 ]; then
    echo "No hay RECORD_ID válido. Omitiendo actualización Odoo."
    exit 0
fi

echo "--- Notificando a Odoo ---"

# Construimos el JSON con cuidado
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

# Enviamos con CURL
curl -s -X POST \
     -H "Content-Type: application/json" \
     -d "$PAYLOAD" \
     "${ODOO_URL}/jsonrpc"