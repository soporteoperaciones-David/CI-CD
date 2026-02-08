pipeline {
    agent any // Ejecutamos Docker desde el Host

    parameters {
        string(name: 'ODOO_URL', defaultValue: '', description: 'URL de producción')
        choice(name: 'BACKUP_TYPE', choices: ['dump', 'zip'], description: 'Formato del respaldo')
        choice(name: 'VERSION', choices: ['v15', 'v19'], description: 'Versión de Odoo destino')
        string(name: 'EXECUTED_BY', defaultValue: 'Sistema', description: 'Usuario que disparó el proceso')
        string(name: 'ODOO_ID', defaultValue: '', description: 'ID del registro en Odoo')
    }

    environment {
        // RUTA EN EL HOST FÍSICO (Asegúrate que existe)
        HOST_VPN_FILE = "/home/ubuntu/pasante.ovpn"
        
        // Credenciales
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
                    echo "--- Limpiando contenedores viejos ---"
                    sh "docker rm -f vpn-sidecar || true"

                    echo "--- Arrancando Contenedor VPN (Sidecar) ---"
                    // Iniciamos el contenedor que mantendrá el túnel abierto
                    sh """
                        docker run -d --name vpn-sidecar \
                        --cap-add=NET_ADMIN --device /dev/net/tun \
                        -v ${env.HOST_VPN_FILE}:/vpn/config.ovpn \
                        ubuntu:22.04 \
                        sh -c "apt-get update && apt-get install -y openvpn && openvpn --config /vpn/config.ovpn"
                    """
                    
                    echo "--- Esperando conexión (15s) ---"
                    sleep 15
                    
                    // Verificamos logs (solo para debug)
                    sh "docker logs vpn-sidecar"
                }
            }
        }

        stage('2. Descargar Backup (Vía VPN)') {
            steps {
                script {
                    echo "--- Iniciando Worker de Descarga ---"
                    
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

                    // SCRIPT DE DESCARGA
                    def download_cmds = """
                        apt-get update -qq && apt-get install -y curl python3 -qq
                        
                        # Verificación de IP (Debug)
                        ifconfig tun0 || ip addr show tun0 || echo '⚠️ Tun0 no visible'

                        echo '--- Consultando Odoo ---'
                        DB_JSON=\$(curl -s -k -X POST "https://${params.ODOO_URL}/web/database/list" \
                            -H "Content-Type: application/json" \
                            -d '{"params": {"master_pwd": "${env.MASTER_PWD}"}}')
                        
                        DB_NAME=\$(echo \$DB_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['result'][0])")
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
                            
                        # Guardamos datos para el siguiente stage
                        echo "\$FILENAME" > /workspace/filename.txt
                        echo "\$DB_NAME" > /workspace/dbname.txt
                        chmod 666 "/workspace/\$FILENAME"
                    """

                    // EJECUTAMOS EL WORKER 1
                    sh """
                        docker run --rm \
                        --network container:vpn-sidecar \
                        -v ${WORKSPACE}:/workspace \
                        ubuntu:22.04 \
                        sh -c "${download_cmds}"
                    """
                }
            }
        }

        stage('3. Enviar y Restaurar (Vía VPN)') {
            steps {
                script {
                    echo "--- Preparando envío por túnel VPN ---"
                    
                    // Leemos variables guardadas por el paso anterior
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
                        
                        // SCRIPT DE RESTAURACIÓN (Se ejecutará DENTRO del contenedor VPN)
                        // Nota: SSHPASS debe instalarse aquí adentro porque es un contenedor nuevo
                        def deploy_cmds = """
                            apt-get update -qq && apt-get install -y sshpass openssh-client curl -qq
                            
                            echo '--- Enviando archivo por SCP (Tunel VPN) ---'
                            sshpass -p '${ROOT_PASS}' scp -o StrictHostKeyChecking=no /workspace/${env.LOCAL_BACKUP_FILE} root@${target_ip}:${env.BACKUP_DIR_REMOTE}/

                            echo '--- Ejecutando restauración remota ---'
                            # Nos conectamos por SSH (a través de la VPN) para dar las órdenes al VPS destino
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

                        // EJECUTAMOS EL WORKER 2 (Conectado a la misma VPN)
                        sh """
                            docker run --rm \
                            --network container:vpn-sidecar \
                            -e ROOT_PASS='${ROOT_PASS}' \
                            -v ${WORKSPACE}:/workspace \
                            ubuntu:22.04 \
                            sh -c "${deploy_cmds}"
                        """
                    }
                }
            }
        }
        
        stage('Notificar') {
            steps {
                script {
                    // Notificación sale por Internet normal del Host (no hace falta VPN)
                    def chat_msg = """{"text": "*Respaldo Completado*\\n*Base:* ${env.NEW_DB_NAME}\\n*URL:* ${env.FINAL_URL}"}"""
                    sh "curl -X POST -H 'Content-Type: application/json; charset=UTF-8' -d '${chat_msg}' '${env.GOOGLE_CHAT_WEBHOOK}' || true"

                    // Si necesitas notificar al Odoo Local, y ese Odoo Local NO requiere VPN, 
                    // puedes hacerlo aquí directo desde el host.
                }
            }
        }
    }

    post {
        always {
            echo "--- Limpiando Sidecar VPN ---"
            sh "docker rm -f vpn-sidecar || true"
            cleanWs()
        }
    }
}