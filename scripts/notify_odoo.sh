#!/bin/bash
# scripts/notify_odoo.sh

RECORD_ID=$1
STATE=$2
BACKUP_URL=$3
LOG_MSG=$4

# ODOO_UID=2 es el admin por defecto.
ODOO_UID=2  
MODEL_NAME="backup.automation" # <--- CONFIRMADO EN TU PYTHON (_name = 'backup.automation')

if [ -z "$RECORD_ID" ] || [ "$RECORD_ID" = "null" ] || [ "$RECORD_ID" -eq 0 ]; then
    echo "No hay RECORD_ID válido ($RECORD_ID). Omitiendo actualización Odoo."
    exit 0
fi

echo "--- Notificando a Odoo ---"
echo "URL: $ODOO_URL | DB: $ODOO_DB | ID: $RECORD_ID"

# Construimos el JSON Payload
# CORRECCIÓN: Cambiamos 'backup_url' por 'result_url' para que coincida con tu Python
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
                    "result_url": "${BACKUP_URL}",
                    "jenkins_log": "${LOG_MSG}"
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