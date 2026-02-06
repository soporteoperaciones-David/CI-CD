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
        // --- RUTAS Y CONFIGURACIÓN ---
        BACKUP_DIR_REMOTE = "/opt/backup_integralis"
        
        // IP DEL HOST (El servidor físico visto desde Docker)
        HOST_IP = "172.17.0.1"
        HOST_VPN_CONFIG = "/root/pasante.ovpn" 
        
        // --- CREDENCIALES ---
        ROOT_PASS_ID = 'root-password-prod' 
        GOOGLE_CHAT_WEBHOOK = credentials('GOOGLE_CHAT_WEBHOOK')
        
        // --- SERVIDORES DESTINO ---
        IP_TEST_V15 = "148.113.165.227" 
        IP_TEST_V19 = "158.69.210.128"

        // --- ODOO LOCAL (Usando Ngrok o IP Pública) ---
        // ASEGÚRATE QUE ESTA URL SEA LA CORRECTA DE NGROK
        ODOO_LOCAL_URL = "https://tu-url-de-ngrok.ngrok-free.app" // <-- ¡ACTUALIZA ESTO!
        ODOO_LOCAL_DB = "prueba"
        ODOO_LOCAL_PASS = credentials('odoo-local-api-key') 
    }

    stages {
        stage('Delegar VPN y Descarga al Host') {
            steps {
                script {
                    echo "--- 1. Conectando al Servidor Host (${env.HOST_IP}) para VPN ---"
                    
                    withCredentials([string(credentialsId: env.ROOT_PASS_ID, variable: 'ROOT_PASS')]) {
                        
                        // A. DEFINIR LÓGICA DE CONTRASEÑA MAESTRA
                        if (params.ODOO_URL.contains('.sdb-integralis360.com')) {
                            env.MASTER_PWD = credentials('vault-sdb-integralis360.com')
                        } else if (params.ODOO_URL.contains('.dic-integralis360.com')) {
                            env.MASTER_PWD = credentials('dic-integralis360.com')
                        } else if (params.ODOO_URL.contains('lns') || params.ODOO_URL.contains('edb') || params.ODOO_URL.contains('cgs')) {
                             env.MASTER_PWD = credentials('dic-lns') 
                        } else {
                            env.MASTER_PWD = credentials('vault-integralis360.website')
                        }

                        // B. SCRIPT REMOTO: VPN + DATABASE LIST + DOWNLOAD
                        // Este bloque de texto bash se ejecutará en el servidor físico, no en Jenkins
                        def remote_script = """
                            # 1. Gestionar VPN
                            killall openvpn || true
                            openvpn --config ${env.HOST_VPN_CONFIG} --daemon
                            echo "Esperando VPN..."
                            sleep 10
                            
                            # 2. Obtener Nombre de la BD (Curl a través de la VPN)
                            DB_JSON=\$(curl -s -k -X POST "https://${params.ODOO_URL}/web/database/list" \
                                -H "Content-Type: application/json" \
                                -d '{"params": {"master_pwd": "${env.MASTER_PWD}"}}')
                            
                            # Extraer nombre usando python (más seguro que grep)
                            DB_NAME=\$(echo \$DB_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['result'][0])")
                            echo "Base detectada: \$DB_NAME"
                            
                            # 3. Preparar nombre de archivo
                            DATE=\$(date +%Y%m%d)
                            EXT="dump"
                            [ "${params.BACKUP_TYPE}" = "zip" ] && EXT="zip"
                            BACKUP_PATH="/tmp/backup_\${DB_NAME}-\${DATE}.\${EXT}"
                            
                            # 4. Descargar Respaldo
                            echo "Descargando..."
                            curl -k -X POST \
                                -F "master_pwd=${env.MASTER_PWD}" \
                                -F "name=\$DB_NAME" \
                                -F "backup_format=${params.BACKUP_TYPE}" \
                                "https://${params.ODOO_URL}/web/database/backup" \
                                -o "\$BACKUP_PATH"
                            
                            # 5. Dar permisos y reportar nombre final
                            chmod 644 "\$BACKUP_PATH"
                            echo "FILENAME:\$BACKUP_PATH"
                            echo "DBNAME_ONLY:\$DB_NAME"
                        """

                        echo "Ejecutando operaciones en el Host..."
                        // Ejecutamos SSH y capturamos la salida para saber el nombre del archivo
                        def output = sh(script: "sshpass -p '${ROOT_PASS}' ssh -o StrictHostKeyChecking=no root@${env.HOST_IP} '${remote_script}'", returnStdout: true).trim()
                        echo "Salida del Host: \n${output}"
                        
                        // Parsear el nombre del archivo y la BD de la salida del script
                        def remote_file_path = output.split('\n').find { it.startsWith('FILENAME:') }?.split(':')?.getAt(1)
                        env.DB_NAME = output.split('\n').find { it.startsWith('DBNAME_ONLY:') }?.split(':')?.getAt(1)
                        
                        if (!remote_file_path || !env.DB_NAME) {
                            error "No se pudo obtener el nombre del archivo o base de datos. Revisa la conexión VPN en el Host."
                        }
                        
                        // Definir nombre local en Jenkins
                        env.LOCAL_BACKUP_FILE = remote_file_path.split('/').last()
                        
                        // C. TRAER ARCHIVO A JENKINS (SCP)
                        echo "Trayendo archivo ${remote_file_path} a Jenkins..."
                        sh "sshpass -p '${ROOT_PASS}' scp -o StrictHostKeyChecking=no root@${env.HOST_IP}:${remote_file_path} ./${env.LOCAL_BACKUP_FILE}"
                        
                        // D. LIMPIEZA EN HOST (Importante para no llenar el disco del servidor)
                        sh "sshpass -p '${ROOT_PASS}' ssh -o StrictHostKeyChecking=no root@${env.HOST_IP} 'rm -f ${remote_file_path}; killall openvpn || true'"
                    }
                }
            }
        }

        stage('Lógica de Versión y Restore') {
            steps {
                script {
                    // Calculamos la versión de Postgres basándonos en el nombre obtenido
                    env.PG_BIN_VERSION = "17" 
                    if (params.ODOO_URL.contains('sdb-integralis360.com')) {
                        env.PG_BIN_VERSION = "12"
                        if (env.DB_NAME.contains('edb') || env.DB_NAME.contains('cgs')) {
                            env.PG_BIN_VERSION = "17"
                        }
                    }

                    def target_ip = (params.VERSION == 'v15') ? env.IP_TEST_V15 : env.IP_TEST_V19
                    def suffix = (params.VERSION == 'v15') ? 'ee15n2' : 'ee19'
                    def date = sh(script: "date +%Y%m%d", returnStdout: true).trim()
                    env.NEW_DB_NAME = "${env.DB_NAME}-${date}-${suffix}"
                    env.FINAL_URL = "https://${env.NEW_DB_NAME}.odooecuador.online/web/login"

                    withCredentials([string(credentialsId: env.ROOT_PASS_ID, variable: 'ROOT_PASS')]) {
                        echo "Enviando a servidor destino (${target_ip})..."
                        sh "sshpass -p '${ROOT_PASS}' scp -o StrictHostKeyChecking=no ${env.LOCAL_BACKUP_FILE} root@${target_ip}:${env.BACKUP_DIR_REMOTE}/"

                        echo "Restaurando en destino..."
                        sh """
                            sshpass -p '${ROOT_PASS}' ssh -o StrictHostKeyChecking=no root@${target_ip} '
                                update-alternatives --set psql /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/psql
                                update-alternatives --set pg_dump /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/pg_dump
                                update-alternatives --set pg_restore /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/pg_restore
                                
                                curl -k -X POST "http://localhost:8069/web/database/restore" \
                                    -F "master_pwd=${env.MASTER_PWD}" \
                                    -F "file=@${env.BACKUP_DIR_REMOTE}/${env.LOCAL_BACKUP_FILE}" \
                                    -F "name=${env.NEW_DB_NAME}" \
                                    -F "copy=true"
                                
                                rm -f ${env.BACKUP_DIR_REMOTE}/${env.LOCAL_BACKUP_FILE}
                            '
                        """
                    }
                }
            }
        }

        stage('Notificaciones') {
            steps {
                script {
                    // Google Chat
                    def chat_msg = """{"text": "*Respaldo Completado*\\n*Base:* ${env.NEW_DB_NAME}\\n*Tipo:* ${params.BACKUP_TYPE}\\n*URL:* ${env.FINAL_URL}"}"""
                    sh "curl -X POST -H 'Content-Type: application/json; charset=UTF-8' -d '${chat_msg}' '${env.GOOGLE_CHAT_WEBHOOK}' || true"

                    // Odoo Success
                    def odoo_payload = """
                    {
                        "jsonrpc": "2.0", "method": "call",
                        "params": {
                            "service": "object", "method": "execute_kw",
                            "args": [
                                "${env.ODOO_LOCAL_DB}", 2, "${env.ODOO_LOCAL_PASS}",
                                "backup.automation", "write",
                                [[${params.ODOO_ID}], {
                                    "state": "done",
                                    "result_url": "${env.FINAL_URL}",
                                    "jenkins_log": "Exitoso. Base: ${env.NEW_DB_NAME}"
                                }]
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
            cleanWs()
            // Intento de seguridad extra: matar la VPN en el host si quedó colgada
            script {
                withCredentials([string(credentialsId: env.ROOT_PASS_ID, variable: 'ROOT_PASS')]) {
                    sh "sshpass -p '${ROOT_PASS}' ssh -o StrictHostKeyChecking=no root@${env.HOST_IP} 'killall openvpn || true'"
                }
            }
        }
        failure {
            script {
                echo "Pipeline Fallido."
                if (params.ODOO_ID) {
                    def error_msg = "Fallo en Jenkins #${env.BUILD_NUMBER}. Ver logs: ${env.BUILD_URL}"
                    def err_payload = """
                    {
                        "jsonrpc": "2.0", "method": "call",
                        "params": {
                            "service": "object", "method": "execute_kw",
                            "args": [
                                "${env.ODOO_LOCAL_DB}", 2, "${env.ODOO_LOCAL_PASS}",
                                "backup.automation", "write",
                                [[${params.ODOO_ID}], {"state": "error", "jenkins_log": "${error_msg}"}]
                            ]
                        }
                    }
                    """
                    sh "curl -X POST -H 'Content-Type: application/json' -d '${err_payload}' '${env.ODOO_LOCAL_URL}/jsonrpc' || true"
                }
            }
        }
    }
}