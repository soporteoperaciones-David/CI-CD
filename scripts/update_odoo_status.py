#!/usr/bin/env python3
import xmlrpc.client
import sys
import os

# Uso: python3 update_odoo_status.py <RECORD_ID> <STATE> <URL_BACKUP> <LOG_MESSAGE>

def update_odoo():
    # 1. Obtener credenciales de Variables de Entorno (Inyectadas por Jenkins)
    url = os.environ.get('ODOO_GESTOR_URL')
    db = os.environ.get('ODOO_GESTOR_DB')
    username = os.environ.get('ODOO_GESTOR_USER')
    password = os.environ.get('ODOO_GESTOR_PASSWORD')
    
    # 2. Obtener argumentos del comando
    if len(sys.argv) < 5:
        print("Error: Faltan argumentos.")
        print("Uso: script.py <record_id> <state> <backup_url> <log_message>")
        sys.exit(1)

    record_id = int(sys.argv[1])
    state = sys.argv[2]      # ej: 'done' o 'failed'
    backup_url = sys.argv[3]
    log_msg = sys.argv[4]

    # Modelo donde escribir
    model_name = "tu.modelo.restauracion" # <--- CAMBIA ESTO POR TU MODELO REAL

    print(f"--- Conectando a Odoo Gestor: {url} ---")

    try:
        # 3. Conexión XML-RPC
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, username, password, {})
        
        if not uid:
            print("Error de Autenticación en Odoo Gestor")
            sys.exit(1)

        models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

        # 4. Escribir en el registro
        models.execute_kw(db, uid, password, model_name, 'write', [[record_id], {
            'state': state,
            'backup_url': backup_url,
            'log_notes': log_msg
        }])
        
        print(f"Estado actualizado a: {state}")

    except Exception as e:
        print(f"Error al actualizar Odoo: {e}")
        # No salimos con error sys.exit(1) para no poner rojo el pipeline 
        # si solo falló la notificación final.
        sys.exit(0) 

if __name__ == "__main__":
    update_odoo()