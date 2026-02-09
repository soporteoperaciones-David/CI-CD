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
        ROOT_PASS_ID = 'root-password-prod' 
        GOOGLE_CHAT_WEBHOOK = credentials('GOOGLE_CHAT_WEBHOOK')
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

                    echo "--- Preparando Configuración VPN ---"
                    configFileProvider([configFile(fileId: 'vpn-pasante-file', targetLocation: 'pasante.ovpn')]) {
                        
                        echo "--- Arrancando Contenedor en modo 'Zombie' ---"
                        // 1. Iniciamos el contenedor con 'sleep infinity'. 
                        // Esto garantiza que el contenedor NO SE APAGUE aunque falle la instalación.
                        sh """
                            docker run -d --name vpn-sidecar \
                            --cap-add=NET_ADMIN --device /dev/net/tun \
                            -v "${WORKSPACE}":/vpn \
                            ubuntu:22.04 \
                            sleep infinity
                        """

                        echo "--- Instalando OpenVPN ---"
                        // 2. Instalamos software en el contenedor vivo
                        sh "docker exec vpn-sidecar apt-get update"
                        sh "docker exec vpn-sidecar apt-get install -y openvpn iproute2 iputils-ping"

                        echo "--- Iniciando Servicio VPN ---"
                        // 3. Ejecutamos OpenVPN en modo 'daemon' (segundo plano)
                        // Agregamos --log para guardar el error en un archivo si falla
                        sh "docker exec vpn-sidecar openvpn --config /vpn/pasante.ovpn --daemon --log /vpn/vpn-debug.log"
                    }
                    
                    echo "--- Esperando conexión (15s) ---"
                    sleep 15
                    
                    // 4. DIAGNÓSTICO DE VIDA O MUERTE
                    echo "--- Verificando Logs de OpenVPN ---"
                    // Leemos el log que generó OpenVPN. Si falló, aquí nos dirá por qué.
                    sh "docker exec vpn-sidecar cat /vpn/vpn-debug.log || echo 'No se pudo leer el log'"
                    
                    echo "--- Verificando Interfaz ---"
                    sh "docker exec vpn-sidecar ip addr show tun0"
                }
            }
        }

        stage('2. Descargar Backup (Vía VPN)') {
            steps {
                script {
                    echo "--- Generando Scripts ---"
                    
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
apt-get update -qq && apt-get install -y curl python3 -qq

ifconfig tun0 || ip addr show tun0 || echo '⚠️ No veo tun0'

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

echo '--- Descargando ---'
curl -k -X POST \
    -F "master_pwd=${env.MASTER_PWD}" \
    -F "name=\$DB_NAME" \
    -F "backup_format=${params.BACKUP_TYPE}" \
    "https://${params.ODOO_URL}/web/database/backup" \
    -o "/workspace/\$FILENAME"

echo "\$FILENAME" > /workspace/filename.txt
echo "\$DB_NAME" > /workspace/dbname.txt
chmod 666 "/workspace/\$FILENAME"
"""
                    writeFile file: 'download.sh', text: mainScript
                    sh "chmod +x download.sh"

                    echo "--- Ejecutando Worker ---"
                    sh """
                        docker run --rm \
                        --network container:vpn-sidecar \
                        -v "${WORKSPACE}":/workspace \
                        ubuntu:22.04 \
                        /workspace/download.sh
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

                    def target_ip = (params.VERSION == 'v15') ? env.IP_TEST_V15 : env.IP_TEST_V19
                    env.FINAL_URL = "https://${env.NEW_DB_NAME}.odooecuador.online/web/login"

                    withCredentials([string(credentialsId: env.ROOT_PASS_ID, variable: 'ROOT_PASS')]) {
                        
                        def deployScript = """#!/bin/bash
set -e
apt-get update -qq && apt-get install -y sshpass openssh-client curl -qq

echo '--- Enviando archivo ---'
sshpass -p '${ROOT_PASS}' scp -o StrictHostKeyChecking=no /workspace/${env.LOCAL_BACKUP_FILE} root@${target_ip}:${env.BACKUP_DIR_REMOTE}/

echo '--- Restaurando ---'
sshpass -p '${ROOT_PASS}' ssh -o StrictHostKeyChecking=no root@${target_ip} '
    update-alternatives --set psql /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/psql
    update-alternatives --set pg_dump /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/pg_dump
    update-alternatives --set pg_restore /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/pg_restore
    
    echo "Restaurando ${env.NEW_DB_NAME}..."
    curl -k -X POST "http://localhost:8069/web/database/restore" \
        -F "master_pwd=${env.MASTER_PWD}" \
        -F "file=@${env.BACKUP_DIR_REMOTE}/${env.LOCAL_BACKUP_FILE}" \
        -F "name=${env.NEW_DB_NAME}" \
        -F "copy=true"
    
    rm -f ${env.BACKUP_DIR_REMOTE}/${env.LOCAL_BACKUP_FILE}
'
"""
                        writeFile file: 'deploy.sh', text: deployScript
                        sh "chmod +x deploy.sh"

                        sh """
                            docker run --rm \
                            --network container:vpn-sidecar \
                            -v "${WORKSPACE}":/workspace \
                            ubuntu:22.04 \
                            /workspace/deploy.sh
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
            cleanWs()
        }
    }
}