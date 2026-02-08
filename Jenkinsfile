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
        // RUTA REAL EN EL SERVIDOR FÍSICO
        HOST_VPN_FILE = "/home/ubuntu/pasante.ovpn"
        
        // Credenciales
        ROOT_PASS_ID = 'root-password-prod' 
        GOOGLE_CHAT_WEBHOOK = credentials('GOOGLE_CHAT_WEBHOOK')
        
        IP_TEST_V15 = "148.113.165.227" 
        IP_TEST_V19 = "158.69.210.128"
        BACKUP_DIR_REMOTE = "/opt/backup_integralis"
        
        ODOO_LOCAL_URL = "https://tu-url-ngrok.ngrok-free.app" 
        ODOO_LOCAL_DB = "prueba"
        ODOO_LOCAL_PASS = credentials('odoo-local-api-key') 
    }

    stages {
        stage('1. Iniciar Sidecar VPN') {
            steps {
                script {
                    echo "--- Limpiando contenedores viejos ---"
                    sh "docker rm -f vpn-sidecar || true"

                    echo "--- Arrancando Contenedor VPN (Sidecar) ---"
                    
                    // CORRECCIÓN 1: Eliminamos el 'cp'. 
                    // Montamos directamente la ruta del HOST (${env.HOST_VPN_FILE}) al contenedor.
                    // Docker (root) sí podrá leer el archivo.
                    sh """
                        docker run -d --name vpn-sidecar \
                        --cap-add=NET_ADMIN --device /dev/net/tun \
                        -v ${env.HOST_VPN_FILE}:/vpn/config.ovpn \
                        ubuntu:22.04 \
                        sh -c "apt-get update && apt-get install -y openvpn && \
                               echo '--- Iniciando OpenVPN ---' && \
                               openvpn --config /vpn/config.ovpn"
                    """
                    
                    echo "--- Esperando conexión (15s) ---"
                    sleep 15
                    
                    // Verificamos logs para confirmar
                    sh "docker logs vpn-sidecar"
                }
            }
        }

        stage('2. Descargar Backup (Vía VPN)') {
            steps {
                script {
                    echo "--- Generando Script de Descarga ---"
                    
                    // Lógica de Passwords
                    if (params.ODOO_URL.contains('.sdb-integralis360.com')) {
                        env.MASTER_PWD = credentials('vault-sdb-integralis360.com')
                    } else if (params.ODOO_URL.contains('.dic-integralis360.com')) {
                        env.MASTER_PWD = credentials('dic-integralis360.com')
                    } else if (params.ODOO_URL.contains('lns') || params.ODOO_URL.contains('edb') || params.ODOO_URL.contains('cgs')) {
                            env.MASTER_PWD = credentials('dic-lns') 
                    } else {
                        env.MASTER_PWD = credentials('vault-integralis360.website')
                    }

                    // CORRECCIÓN 2: Sintaxis Python corregida (escapando comillas y $)
                    def scriptContent = """#!/bin/bash
set -e
apt-get update -qq && apt-get install -y curl python3 -qq

echo '--- Verificando conexión VPN ---'
ifconfig tun0 || ip addr show tun0 || echo '⚠️ No veo tun0'

echo '--- Consultando Odoo ---'
DB_JSON=\$(curl -s -k -X POST "https://${params.ODOO_URL}/web/database/list" \
    -H "Content-Type: application/json" \
    -d '{"params": {"master_pwd": "${env.MASTER_PWD}"}}')

# AQUÍ ESTABA EL ERROR: Usamos sintaxis limpia para extraer el nombre
DB_NAME=\$(echo "\$DB_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['result'][0])")
echo "Base detectada: \$DB_NAME"

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

# Guardar nombres para Jenkins
echo "\$FILENAME" > /workspace/filename.txt
echo "\$DB_NAME" > /workspace/dbname.txt
chmod 666 "/workspace/\$FILENAME"
"""
                    writeFile file: 'download_script.sh', text: scriptContent
                    sh "chmod +x download_script.sh"

                    echo "--- Ejecutando Worker ---"
                    sh """
                        docker run --rm \
                        --network container:vpn-sidecar \
                        -v ${WORKSPACE}:/workspace \
                        ubuntu:22.04 \
                        /workspace/download_script.sh
                    """
                }
            }
        }

        stage('3. Enviar y Restaurar (Vía VPN)') {
            steps {
                script {
                    echo "--- Generando Script de Restore ---"
                    
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
                        
                        def deployContent = """#!/bin/bash
set -e
apt-get update -qq && apt-get install -y sshpass openssh-client curl -qq

echo '--- Enviando archivo por SCP (Tunel VPN) ---'
sshpass -p '${ROOT_PASS}' scp -o StrictHostKeyChecking=no /workspace/${env.LOCAL_BACKUP_FILE} root@${target_ip}:${env.BACKUP_DIR_REMOTE}/

echo '--- Ejecutando restauración remota ---'
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
                        writeFile file: 'deploy_script.sh', text: deployContent
                        sh "chmod +x deploy_script.sh"

                        sh """
                            docker run --rm \
                            --network container:vpn-sidecar \
                            -v ${WORKSPACE}:/workspace \
                            ubuntu:22.04 \
                            /workspace/deploy_script.sh
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