#!/bin/bash
set -e
KEY_PATH="$SSH_KEY_FILE"
CANDIDATE="${BASE_NAME}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
COUNTER=1

# Fíjate en el -4 después de ssh
while ssh -4 -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@$TARGET_IP "sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw $CANDIDATE"; do
    COUNTER=$((COUNTER+1))
    CANDIDATE="${BASE_NAME}_v${COUNTER}-${DATE_SUFFIX}-${ODOO_SUFFIX}"
done

echo "$CANDIDATE"