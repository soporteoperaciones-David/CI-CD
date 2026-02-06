pipeline {
    agent {
        docker {
            image 'ubuntu:22.04'
            reuseNode true
            // Agregamos --security-opt apparmor=unconfined por si acaso el host bloquea a OpenVPN
            args '-u root --privileged --cap-add=NET_ADMIN --device /dev/net/tun --security-opt apparmor=unconfined -v /var/run/docker.sock:/var/run/docker.sock'
        }
    }

    parameters {
        string(name: 'ODOO_URL', defaultValue: '', description: 'URL de producción')
        choice(name: 'BACKUP_TYPE', choices: ['dump', 'zip'], description: 'Formato del respaldo')
        choice(name: 'VERSION', choices: ['v15', 'v19'], description: 'Versión de Odoo destino')
        string(name: 'EXECUTED_BY', defaultValue: 'Sistema', description: 'Usuario que disparó el proceso')
        string(name: 'ODOO_ID', defaultValue: '', description: 'ID del registro en Odoo')
    }

    environment {
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
        stage('Preparar Entorno') {
            steps {
                script {
                    echo "--- Instalando herramientas ---"
                    sh "apt-get update && apt-get install -y openvpn curl sshpass iputils-ping python3"
                }
            }
        }

        stage('Conectar VPN y Descargar') {
            steps {
                script {
                    echo "--- Inyectando Configuración VPN ---"
                    
                    // Usamos el plugin para traer el archivo al workspace (aunque tenga espacios)
                    configFileProvider([configFile(fileId: 'vpn-pasante-file', targetLocation: 'pasante.ovpn')]) {
                        
                        echo "--- Moviendo a zona segura (/tmp) ---"
                        // 1. COPIAMOS el archivo a /tmp para salirnos de la carpeta con espacios
                        //    y para solucionar cualquier problema de permisos de usuario (1000 vs Root).
                        sh "cp pasante.ovpn /tmp/vpn_final.ovpn"
                        
                        // 2. Ajustamos permisos en el nuevo archivo
                        sh "chmod 600 /tmp/vpn_final.ovpn"
                        
                        // 3. Verificamos (Debug)
                        sh "ls -l /tmp/vpn_final.ovpn"

                        echo "--- Iniciando VPN ---"
                        // 4. Ejecutamos OpenVPN apuntando al archivo en /tmp
                        //    IMPORTANTE: Usamos la ruta absoluta /tmp/vpn_final.ovpn
                        sh "openvpn --config /tmp/vpn_final.ovpn --daemon --log /tmp/vpn.log --verb 3"
                        
                        echo "Esperando conexión (15s)..."
                        sleep 15
                        
                        // DIAGNÓSTICO
                        sh "cat /tmp/vpn.log || echo 'No log file found'"
                        sh "ip addr show tun0 || echo '⚠️ tun0 no levantó'"
                        sh "ping -c 2 10.8.0.1 || echo '⚠️ Ping falló (Puede ser firewall, pero seguimos)'"

                        // ... (AQUÍ CONTINÚA TU LÓGICA DE SIEMPRE: PASSWORD, BASE DE DATOS, ETC.) ...
                        // Copia aquí el resto de tu código (Password Maestra, Curl, etc.)
                        
                         // --- 1. Password Maestra ---
                        if (params.ODOO_URL.contains('.sdb-integralis360.com')) {
                            env.MASTER_PWD = credentials('vault-sdb-integralis360.com')
                        } else if (params.ODOO_URL.contains('.dic-integralis360.com')) {
                            env.MASTER_PWD = credentials('dic-integralis360.com')
                        } else if (params.ODOO_URL.contains('lns') || params.ODOO_URL.contains('edb') || params.ODOO_URL.contains('cgs')) {
                                env.MASTER_PWD = credentials('dic-lns') 
                        } else {
                            env.MASTER_PWD = credentials('vault-integralis360.website')
                        }

                        // --- 2. Obtener Nombre BD ---
                        def db_response = sh(script: """
                            curl -s -k -X POST "https://${params.ODOO_URL}/web/database/list" \
                            -H "Content-Type: application/json" \
                            -d '{"params": {"master_pwd": "${env.MASTER_PWD}"}}'
                        """, returnStdout: true).trim()
                        
                        def json_db = readJSON text: db_response
                        env.DB_NAME = json_db.result[0]
                        echo "Base detectada: ${env.DB_NAME}"
                        
                        // --- 3. Descargar ---
                        def date = sh(script: "date +%Y%m%d", returnStdout: true).trim()
                        def ext = (params.BACKUP_TYPE == 'zip') ? 'zip' : 'dump'
                        env.BACKUP_FILE = "backup_${env.DB_NAME}-${date}.${ext}"
                        
                        echo "Descargando backup..."
                        sh """
                            curl -k -X POST \
                            -F "master_pwd=${env.MASTER_PWD}" \
                            -F "name=${env.DB_NAME}" \
                            -F "backup_format=${params.BACKUP_TYPE}" \
                            "https://${params.ODOO_URL}/web/database/backup" \
                            -o "${env.BACKUP_FILE}"
                        """
                    } 
                }
            }
        }

        stage('Enviar y Restaurar') {
            steps {
                script {
                    env.PG_BIN_VERSION = "17" 
                    if (params.ODOO_URL.contains('sdb-integralis360.com')) {
                        env.PG_BIN_VERSION = "12"
                        if (env.DB_NAME.contains('edb') || env.DB_NAME.contains('cgs')) { env.PG_BIN_VERSION = "17" }
                    }

                    def target_ip = (params.VERSION == 'v15') ? env.IP_TEST_V15 : env.IP_TEST_V19
                    def suffix = (params.VERSION == 'v15') ? 'ee15n2' : 'ee19'
                    def date = sh(script: "date +%Y%m%d", returnStdout: true).trim()
                    env.NEW_DB_NAME = "${env.DB_NAME}-${date}-${suffix}"
                    env.FINAL_URL = "https://${env.NEW_DB_NAME}.odooecuador.online/web/login"

                    withCredentials([string(credentialsId: env.ROOT_PASS_ID, variable: 'ROOT_PASS')]) {
                        echo "Enviando a ${target_ip}..."
                        sh "sshpass -p '${ROOT_PASS}' scp -o StrictHostKeyChecking=no ${env.BACKUP_FILE} root@${target_ip}:${env.BACKUP_DIR_REMOTE}/"

                        echo "Restaurando..."
                        sh """
                            sshpass -p '${ROOT_PASS}' ssh -o StrictHostKeyChecking=no root@${target_ip} '
                                update-alternatives --set psql /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/psql
                                update-alternatives --set pg_dump /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/pg_dump
                                update-alternatives --set pg_restore /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/pg_restore
                                
                                curl -k -X POST "http://localhost:8069/web/database/restore" \
                                    -F "master_pwd=${env.MASTER_PWD}" \
                                    -F "file=@${env.BACKUP_DIR_REMOTE}/${env.BACKUP_FILE}" \
                                    -F "name=${env.NEW_DB_NAME}" \
                                    -F "copy=true"
                                
                                rm -f ${env.BACKUP_DIR_REMOTE}/${env.BACKUP_FILE}
                            '
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
            cleanWs()
        }
    }
}