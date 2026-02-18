#!/bin/bash
# scripts/notify_odoo.sh

RECORD_ID=$1
STATE=$2
BACKUP_URL=$3
LOG_MSG=$4

# Variables de entorno inyectadas por Jenkins
# ODOO_URL, ODOO_DB, ODOO_PASS (API Key)

ODOO_UID=2  # ID del admin. Ajustar si es necesario.
MODEL_NAME="restauraciones.test" # <--- ¡VERIFICA QUE ESTE SEA EL NOMBRE DE TU MODELO EN ODOO!

if [ -z "$RECORD_ID" ] || [ "$RECORD_ID" = "null" ] || [ "$RECORD_ID" -eq 0 ]; then
    echo "⚠️ No hay RECORD_ID válido ($RECORD_ID). Omitiendo actualización Odoo."
    exit 0
fi

echo "--- Notificando a Odoo ---"
echo "URL: $ODOO_URL | DB: $ODOO_DB | ID: $RECORD_ID"

# Construimos el JSON Payload
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

# Ejecutar CURL
curl -s -X POST \
     -H "Content-Type: application/json" \
     -d "$PAYLOAD" \
     "${ODOO_URL}/jsonrpc"