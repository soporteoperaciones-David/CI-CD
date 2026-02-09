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
        GOOGLE_CHAT_WEBHOOK = credentials('GOOGLE_CHAT_WEBHOOK')
        
        // IPs de Destino
        IP_TEST_V15 = "148.113.165.227" 
        IP_TEST_V19 = "158.69.210.128"
        
        // Rutas
        BACKUP_DIR_REMOTE = "/opt/backup_integralis"
        
        // Odoo Local
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

                    echo "--- Preparando Configuración VPN ---"
                    configFileProvider([configFile(fileId: 'vpn-pasante-file', targetLocation: 'pasante.ovpn')]) {
                        echo "--- Arrancando Contenedor Zombie ---"
                        sh "docker run -d --name vpn-sidecar --cap-add=NET_ADMIN --device /dev/net/tun ubuntu:22.04 sleep infinity"

                        echo "--- Instalando OpenVPN ---"
                        sh "docker exec vpn-sidecar apt-get update"
                        sh "docker exec vpn-sidecar apt-get install -y openvpn iproute2 iputils-ping"

                        echo "--- Copiando archivo VPN ---"
                        sh "docker cp pasante.ovpn vpn-sidecar:/etc/openvpn/client.conf"

                        echo "--- Iniciando Servicio VPN ---"
                        sh "docker exec -d vpn-sidecar openvpn --config /etc/openvpn/client.conf --daemon --log /tmp/vpn.log"
                    }
                    
                    echo "--- Esperando conexión (15s) ---"
                    sleep 15
                    
                    echo "--- Verificando Logs ---"
                    sh "docker exec vpn-sidecar cat /tmp/vpn.log || echo 'No log found'"
                    sh "docker exec vpn-sidecar ip addr show tun0"
                }
            }
        }

        stage('2. Descargar Backup (Vía VPN)') {
            steps {
                script {
                    echo "--- Generando Scripts ---"
                    
                    // Selección de Password Maestro de la Base de Datos ORIGEN
                    if (params.ODOO_URL.contains('.sdb-integralis360.com')) {
                        env.MASTER_PWD = credentials('vault-sdb-integralis360.com')
                    } else if (params.ODOO_URL.contains('.dic-integralis360.com')) {
                        env.MASTER_PWD = credentials('dic-integralis360.com')
                    } else if (params.ODOO_URL.contains('lns') || params.ODOO_URL.contains('edb') || params.ODOO_URL.contains('cgs')) {
                            env.MASTER_PWD = credentials('dic-lns') 
                    } else {
                        env.MASTER_PWD = credentials('vault-integralis360.website')
                    }

                    def pyScript = """
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['result'][0])
except:
    print("ERROR")
"""
                    writeFile file: 'extract.py', text: pyScript

                    def mainScript = """#!/bin/bash
set -e
apt-get update -qq && apt-get install -y curl python3 iproute2 -qq

echo '--- Verificando túnel ---'
ip addr show tun0 || echo '⚠️ Alerta: tun0 no visible'

echo '--- Consultando Odoo ---'
DB_JSON=\$(curl -s -k -X POST "https://${params.ODOO_URL}/web/database/list" \
    -H "Content-Type: application/json" \
    -d '{"params": {"master_pwd": "${env.MASTER_PWD}"}}')

DB_NAME=\$(echo "\$DB_JSON" | python3 /workspace/extract.py)
echo "Base detectada: \$DB_NAME"

if [ "\$DB_NAME" == "ERROR" ]; then
    echo "❌ Fallo al leer nombre de BD"
    exit 1
fi

DATE=\$(date +%Y%m%d)
EXT="${params.BACKUP_TYPE == 'zip' ? 'zip' : 'dump'}"
FILENAME="backup_\${DB_NAME}-\${DATE}.\${EXT}"

echo "--- Descargando archivo: \$FILENAME ---"
curl -k -X POST \
    --form-string "master_pwd=${env.MASTER_PWD}" \
    --form-string "name=\$DB_NAME" \
    --form-string "backup_format=${params.BACKUP_TYPE}" \
    "https://${params.ODOO_URL}/web/database/backup" \
    -o "/workspace/\$FILENAME"

if [ ! -s "/workspace/\$FILENAME" ]; then
    echo "❌ Error: El archivo descargado está vacío."
    exit 1
fi

echo "\$FILENAME" > /workspace/filename.txt
echo "\$DB_NAME" > /workspace/dbname.txt
chmod 666 "/workspace/\$FILENAME"
"""
                    writeFile file: 'download.sh', text: mainScript
                    sh "chmod +x download.sh"

                    echo "--- Ejecutando Worker ---"
                    sh """
                        docker rm -f vpn-worker || true
                        docker run -d --name vpn-worker --network container:vpn-sidecar ubuntu:22.04 sleep infinity
                        
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

        stage('3. Enviar y Restaurar (Vía VPN)') {
            steps {
                script {
                    env.LOCAL_BACKUP_FILE = readFile('filename.txt').trim()
                    env.DB_NAME = readFile('dbname.txt').trim()
                    env.NEW_DB_NAME = "${env.DB_NAME}-" + sh(returnStdout: true, script: 'date +%Y%m%d').trim() + "-" + ((params.VERSION == 'v15') ? 'ee15n2' : 'ee19')
                    
                    env.PG_BIN_VERSION = "17" 
                    if (params.ODOO_URL.contains('sdb-integralis360.com')) {
                        env.PG_BIN_VERSION = "12"
                        if (env.DB_NAME.contains('edb') || env.DB_NAME.contains('cgs')) { env.PG_BIN_VERSION = "17" }
                    }

                    // --- SELECCIÓN INTELIGENTE DE DESTINO Y CREDENCIAL ---
                    def target_ip = ""
                    def credential_id = ""

                    if (params.VERSION == 'v15') {
                        target_ip = env.IP_TEST_V15
                        credential_id = 'ssh-pass-v15' // Asegúrate de crear esta credencial en Jenkins
                    } else {
                        target_ip = env.IP_TEST_V19
                        credential_id = 'ssh-pass-v19' // Asegúrate de crear esta credencial en Jenkins
                    }

                    env.FINAL_URL = "https://${env.NEW_DB_NAME}.odooecuador.online/web/login"
                    echo "--- Destino: ubuntu@${target_ip} ---"

                    withCredentials([string(credentialsId: credential_id, variable: 'SSH_PASS')]) {
                        
                        // Script de despliegue usando usuario 'ubuntu' y 'sudo'
                        def deployScript = """#!/bin/bash
set -e
apt-get update -qq && apt-get install -y sshpass openssh-client curl -qq

echo '--- 1. Subiendo archivo a /home/ubuntu (SCP) ---'
# Copiamos a la carpeta del usuario ubuntu porque no tenemos permiso en /opt directo
sshpass -p '${SSH_PASS}' scp -o StrictHostKeyChecking=no /workspace/${env.LOCAL_BACKUP_FILE} ubuntu@${target_ip}:/home/ubuntu/

echo '--- 2. Ejecutando comandos remotos (SSH + SUDO) ---'
sshpass -p '${SSH_PASS}' ssh -o StrictHostKeyChecking=no ubuntu@${target_ip} '
    
    echo "Moviemiento de archivo..."
    # Usamos sudo para moverlo a la carpeta protegida
    sudo mv /home/ubuntu/${env.LOCAL_BACKUP_FILE} ${env.BACKUP_DIR_REMOTE}/
    # Damos permisos de lectura para que Odoo pueda leerlo
    sudo chmod 644 ${env.BACKUP_DIR_REMOTE}/${env.LOCAL_BACKUP_FILE}

    echo "Configurando Postgres..."
    sudo update-alternatives --set psql /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/psql || true
    sudo update-alternatives --set pg_dump /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/pg_dump || true
    sudo update-alternatives --set pg_restore /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/pg_restore || true
    
    echo "Restaurando ${env.NEW_DB_NAME}..."
    # Nota: curl ataca a localhost:8069, no necesita sudo, pero el archivo sí debe ser legible
    curl -k -X POST "http://localhost:8069/web/database/restore" \
        -F "master_pwd=${env.MASTER_PWD}" \
        -F "file=@${env.BACKUP_DIR_REMOTE}/${env.LOCAL_BACKUP_FILE}" \
        -F "name=${env.NEW_DB_NAME}" \
        -F "copy=true"
    
    echo "Limpiando..."
    sudo rm -f ${env.BACKUP_DIR_REMOTE}/${env.LOCAL_BACKUP_FILE}
'
"""
                        writeFile file: 'deploy.sh', text: deployScript
                        sh "chmod +x deploy.sh"

                        sh """
                            docker rm -f vpn-deploy || true
                            docker run -d --name vpn-deploy --network container:vpn-sidecar ubuntu:22.04 sleep infinity
                            
                            docker exec vpn-deploy mkdir -p /workspace
                            docker cp deploy.sh vpn-deploy:/workspace/
                            docker cp ${env.LOCAL_BACKUP_FILE} vpn-deploy:/workspace/
                            
                            docker exec vpn-deploy /workspace/deploy.sh
                            
                            docker rm -f vpn-deploy
                        """
                    }
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
            echo "--- Limpiando Sidecar ---"
            sh "docker rm -f vpn-sidecar || true"
            sh "docker rm -f vpn-worker || true"
            sh "docker rm -f vpn-deploy || true"
            cleanWs()
        }
    }
}