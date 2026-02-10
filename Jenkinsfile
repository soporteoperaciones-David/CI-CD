pipeline {
    agent any 

    parameters {
        string(name: 'ODOO_URL', defaultValue: '', description: 'URL de producción')
        choice(name: 'BACKUP_TYPE', choices: ['dump', 'zip'], description: 'Formato del respaldo')
        choice(name: 'VERSION', choices: ['v15', 'v19'], description: 'Versión de Odoo destino')
        string(name: 'EXECUTED_BY', defaultValue: 'Sistema', description: 'Usuario que disparó el proceso')
        string(name: 'ODOO_ID', defaultValue: '', description: 'ID del registro en Odoo')
    }

    environment {
        // --- CREDENCIALES ---
        // Asegúrate de que los IDs coinciden con los de tu Jenkins
        SSH_PASS_V15 = credentials('root-pass-v15') 
        SSH_PASS_V19 = credentials('ssh-pass-v19')
        
        GOOGLE_CHAT_WEBHOOK = credentials('GOOGLE_CHAT_WEBHOOK')
        
        // IPs
        IP_TEST_V15 = "148.113.165.227" 
        IP_TEST_V19 = "158.69.210.128"
        
        BACKUP_DIR_REMOTE = "/opt/backup_integralis"
        
        ODOO_LOCAL_URL = "https://faceable-maddison-unharangued.ngrok-free.dev" 
        ODOO_LOCAL_DB = "prueba"
        ODOO_LOCAL_PASS = credentials('odoo-local-api-key') 
    }

    stages {
        stage('1. Iniciar Sidecar VPN') {
            steps {
                script {
                    echo "--- Limpiando entorno ---"
                    sh "docker rm -f vpn-sidecar || true"

                    configFileProvider([configFile(fileId: 'vpn-pasante-file', targetLocation: 'pasante.ovpn')]) {
                        sh "docker run -d --name vpn-sidecar --cap-add=NET_ADMIN --device /dev/net/tun ubuntu:22.04 sleep infinity"
                        sh "docker exec vpn-sidecar sh -c 'apt-get update && apt-get install -y openvpn iproute2 iputils-ping'"
                        sh "docker cp pasante.ovpn vpn-sidecar:/etc/openvpn/client.conf"
                        sh "docker exec -d vpn-sidecar openvpn --config /etc/openvpn/client.conf --daemon"
                    }
                    
                    sleep 15
                    sh "docker exec vpn-sidecar ip addr show tun0"
                }
            }
        }

        stage('2. Descargar Backup (Vía VPN)') {
            steps {
                script {
                    echo "--- 1. Seleccionando Credencial ---"
                    
                    def selected_cred_id = ''
                    
                    // Lógica de selección
                    if (params.ODOO_URL.contains('.sdb-integralis360.com')) {
                        selected_cred_id = 'vault-sdb-integralis360.com'
                    } else if (params.ODOO_URL.contains('.dic-integralis360.com')) {
                        selected_cred_id = 'dic-integralis360.com'
                    } else if (params.ODOO_URL.contains('lns') || params.ODOO_URL.contains('edb') || params.ODOO_URL.contains('cgs')) {
                        selected_cred_id = 'dic-lns'
                    } else {
                        // Aquí cae alianza247. Si actualizaste 'vault-integralis360.website', esto funcionará.
                        selected_cred_id = 'vault-integralis360.website'
                    }
                    
                    echo "--- ID Seleccionado: ${selected_cred_id} ---"

                    // Script Python auxiliar
                    writeFile file: 'extract.py', text: """
import sys, json
try:
    data = json.load(sys.stdin)
    if 'result' in data:
        print(data['result'][0])
    else:
        print("ERROR_JSON")
except:
    print("ERROR_PYTHON")
"""

                    // Script Bash (GENÉRICO)
                    // Nota: Ya no interpolamos ${env.MASTER_PWD} aquí. Usamos la variable de entorno $MASTER_PWD
                    // que inyectaremos vía Docker. Esto evita el problema del valor NULL.
                    def mainScript = """#!/bin/bash
set -e
apt-get update -qq && apt-get install -y curl python3 iproute2 -qq

# Validación: Asegurarnos de que la contraseña llegó
if [ -z "\$MASTER_PWD" ]; then
    echo "❌ ERROR: La variable MASTER_PWD está vacía dentro del contenedor."
    exit 1
fi

echo '--- Consultando Odoo ---'
# Usamos la variable de entorno directa (\$MASTER_PWD)
DB_JSON=\$(curl -s -k -X POST "https://${params.ODOO_URL}/web/database/list" \
    -H "Content-Type: application/json" \
    -d '{"params": {"master_pwd": "'"\$MASTER_PWD"'"}}')

if echo "\$DB_JSON" | grep -q "Access Denied"; then
    echo "❌ ERROR FATAL: Contraseña maestra rechazada al listar."
    exit 1
fi

DB_NAME=\$(echo "\$DB_JSON" | python3 /workspace/extract.py)
echo "Base detectada: \$DB_NAME"

DATE=\$(date +%Y%m%d)
EXT="${params.BACKUP_TYPE == 'zip' ? 'zip' : 'dump'}"
FILENAME="backup_\${DB_NAME}-\${DATE}.\${EXT}"

echo "--- Descargando archivo: \$FILENAME ---"
curl -k -X POST \
    --form-string "master_pwd=\$MASTER_PWD" \
    --form-string "name=\$DB_NAME" \
    --form-string "backup_format=${params.BACKUP_TYPE}" \
    "https://${params.ODOO_URL}/web/database/backup" \
    -o "/workspace/\$FILENAME"

# Validar si bajó un HTML de error
if grep -q "Database backup error" "/workspace/\$FILENAME"; then
    echo "❌ ERROR CRÍTICO: Odoo rechazó la descarga (Access Denied)."
    exit 1
fi

if [ ! -s "/workspace/\$FILENAME" ]; then
    echo "❌ Error: Archivo vacío."
    exit 1
fi

echo "\$FILENAME" > /workspace/filename.txt
echo "\$DB_NAME" > /workspace/dbname.txt
chmod 666 "/workspace/\$FILENAME"
"""
                    writeFile file: 'download.sh', text: mainScript
                    sh "chmod +x download.sh"

                    echo "--- Ejecutando Worker con Credencial Inyectada ---"
                    
                    // ⚠️ AQUÍ ESTÁ LA SOLUCIÓN DEL NULL ⚠️
                    // Usamos withCredentials con el ID seleccionado dinámicamente
                    withCredentials([string(credentialsId: selected_cred_id, variable: 'TEMP_PWD')]) {
                        sh """
                            docker rm -f vpn-worker || true
                            
                            # Pasamos la contraseña al contenedor explícitamente (-e)
                            docker run -d --name vpn-worker \\
                                -e MASTER_PWD="\${TEMP_PWD}" \\
                                --network container:vpn-sidecar \\
                                ubuntu:22.04 sleep infinity
                            
                            docker exec vpn-worker mkdir -p /workspace
                            docker cp extract.py vpn-worker:/workspace/
                            docker cp download.sh vpn-worker:/workspace/
                            
                            docker exec vpn-worker /workspace/download.sh
                            
                            docker cp vpn-worker:/workspace/filename.txt .
                            docker cp vpn-worker:/workspace/dbname.txt .
                            FILENAME=\$(cat filename.txt)
                            docker cp vpn-worker:/workspace/\$FILENAME .
                            
                            docker rm -f vpn-worker
                        """
                    }
                }
            }
        }

        stage('3. Enviar y Restaurar (Vía VPN)') {
            steps {
                script {
                    env.LOCAL_BACKUP_FILE = readFile('filename.txt').trim()
                    env.DB_NAME = readFile('dbname.txt').trim()
                    
                    // Limpieza del nombre de la base
                    def cleanName = env.DB_NAME.replace("-ee15", "").replace("-ee", "")
                    env.NEW_DB_NAME = "${cleanName}-" + sh(returnStdout: true, script: 'date +%Y%m%d').trim() + "-" + ((params.VERSION == 'v15') ? 'ee15n2' : 'ee19')
                    
                    // --- CONFIGURACIÓN DINÁMICA ---
                    def db_owner = 'odoo' // Default
                    
                    if (params.VERSION == 'v15') {
                        env.TARGET_IP_FINAL = env.IP_TEST_V15
                        env.SELECTED_PASS = env.SSH_PASS_V15
                        db_owner = 'odoo15' // <--- Usamos odoo15 según tu ejemplo
                    } else {
                        env.TARGET_IP_FINAL = env.IP_TEST_V19
                        env.SELECTED_PASS = env.SSH_PASS_V19
                        db_owner = 'odoo'   // <--- Ajusta si en v19 usas otro usuario
                    }
                    
                    env.DB_OWNER = db_owner
                    env.FINAL_URL = "https://${env.NEW_DB_NAME}.odooecuador.online/web/login"
                    
                    echo "--- ESTRATEGIA: PG_RESTORE NATIVO ---"
                    echo "Servidor: ${env.TARGET_IP_FINAL}"
                    echo "Base Nueva: ${env.NEW_DB_NAME}"
                    echo "Dueño DB: ${env.DB_OWNER}"

                    def deployScriptContent = """#!/bin/bash
set -e
apt-get update -qq && apt-get install -y sshpass openssh-client -qq
export SSHPASS="\$MY_SSH_PASS"

echo "--- 1. Subiendo archivo .dump ---"
sshpass -e scp -o StrictHostKeyChecking=no /workspace/${env.LOCAL_BACKUP_FILE} ubuntu@${env.TARGET_IP_FINAL}:/home/ubuntu/

echo "--- 2. Ejecutando Restore en Backend ---"
sshpass -e ssh -o StrictHostKeyChecking=no ubuntu@${env.TARGET_IP_FINAL} 'sudo bash -s' <<'EOF'

    # --- ZONA ROOT ---
    
    # 1. Variables
    FILE_NAME="${env.LOCAL_BACKUP_FILE}"
    SOURCE_PATH="/home/ubuntu/\$FILE_NAME"
    DEST_DIR="/opt/backup_integralis"
    DEST_PATH="\$DEST_DIR/\$FILE_NAME"
    DB_NAME="${env.NEW_DB_NAME}"
    DB_OWNER="${env.DB_OWNER}"
    
    # 2. Preparar Directorio Seguro
    mkdir -p \$DEST_DIR
    
    echo ">> Moviendo archivo a \$DEST_PATH..."
    if [ -f "\$SOURCE_PATH" ]; then
        mv \$SOURCE_PATH \$DEST_PATH
    else
        echo "⚠️ El archivo ya estaba en destino o falló la subida."
    fi
    
    chmod 644 \$DEST_PATH
    
    # 3. Detectar la mejor versión de pg_restore disponible
    # Intentamos usar la v17 o v14 si existen, sino la del sistema default
    PG_BIN="pg_restore"
    if [ -f "/usr/lib/postgresql/17/bin/pg_restore" ]; then
        PG_BIN="/usr/lib/postgresql/17/bin/pg_restore"
    elif [ -f "/usr/lib/postgresql/14/bin/pg_restore" ]; then
        PG_BIN="/usr/lib/postgresql/14/bin/pg_restore"
    fi
    
    echo ">> Usando binario: \$PG_BIN"
    
    # 4. PREPARAR BASE DE DATOS
    echo ">> Recreando base de datos: \$DB_NAME (Dueño: \$DB_OWNER)"
    
    # Borramos la base si existe
    sudo -u postgres dropdb \$DB_NAME --if-exists
    
    # Creamos la base vacía asignada al usuario correcto
    # Esto reemplaza el flag --create del restore, dándonos más control
    sudo -u postgres createdb -O \$DB_OWNER \$DB_NAME
    
    # 5. EJECUTAR RESTORE (Tu comando)
    echo ">> Restaurando..."
    
    # Ejecutamos como usuario 'postgres' para tener permisos totales sin password
    # Flags explicados:
    # --dbname: Base destino
    # --no-owner: Importante para no heredar dueños del backup original
    # --role: Fuerza que los objetos creados pertenezcan al usuario odoo15/odoo
    # --clean: Limpia (aunque acabamos de crearla vacía, no hace daño)
    
    sudo -u postgres \$PG_BIN \\
        --dbname=\$DB_NAME \\
        --clean \\
        --no-acl \\
        --no-owner \\
        --role=\$DB_OWNER \\
        --verbose \\
        \$DEST_PATH > /tmp/pg_restore.log 2>&1 || echo "⚠️ Advertencias en restore (Verificar log si la app falla)"
    
    echo ">> Últimas 10 líneas del log de restauración:"
    tail -n 10 /tmp/pg_restore.log
    
    echo "PROCESO FINALIZADO EXITOSAMENTE"

EOF
"""
                    writeFile file: 'deploy.sh', text: deployScriptContent
                    sh "chmod +x deploy.sh"

                    sh """
                        docker rm -f vpn-deploy || true
                        docker run -d --name vpn-deploy \\
                            -e MY_SSH_PASS="${env.SELECTED_PASS}" \\
                            --network container:vpn-sidecar \\
                            ubuntu:22.04 sleep infinity

                        docker exec vpn-deploy mkdir -p /workspace
                        docker cp deploy.sh vpn-deploy:/workspace/
                        docker cp ${env.LOCAL_BACKUP_FILE} vpn-deploy:/workspace/
                        
                        docker exec vpn-deploy /workspace/deploy.sh
                            
                        docker rm -f vpn-deploy
                    """
                }
            }
        }
        
        stage('Notificar') {
            steps {
                script {
                    def chat_msg = """{"text": "✅ *Respaldo Completado*\\n*Base:* ${env.NEW_DB_NAME}\\n*URL:* ${env.FINAL_URL}"}"""
                    sh "curl -X POST -H 'Content-Type: application/json; charset=UTF-8' -d '${chat_msg}' '${env.GOOGLE_CHAT_WEBHOOK}' || true"

                    def odoo_payload = """
                    {
                        "jsonrpc": "2.0", "method": "call",
                        "params": {
                            "service": "object", "method": "execute_kw",
                            "args": [
                                "${env.ODOO_LOCAL_DB}", 2, "${env.ODOO_LOCAL_PASS}",
                                "backup.automation", "write",
                                [[${params.ODOO_ID}], {"state": "done", "result_url": "${env.FINAL_URL}", "jenkins_log": "Exito"}]
                            ]
                        }
                    }
                    """
                    sh "curl -X POST -H 'Content-Type: application/json' -d '${odoo_payload}' '${env.ODOO_LOCAL_URL}/jsonrpc'"
                }
            }
        }
    }

    post {
        always {
            sh "docker rm -f vpn-sidecar vpn-worker vpn-deploy || true"
            cleanWs()
        }
    }
}