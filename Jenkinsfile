pipeline {
    agent {
        docker {
            // Usamos una imagen base de Ubuntu limpia
            image 'ubuntu:22.04'
            // CRÍTICO:
            // 1. -u root: Para poder instalar cosas con apt-get
            // 2. --privileged y --device: Obligatorios para que OpenVPN pueda crear la interfaz tun0
            args '-u root --privileged --cap-add=NET_ADMIN --device /dev/net/tun -v /var/run/docker.sock:/var/run/docker.sock'
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
        // --- CREDENCIALES ---
        // Sube tu archivo .ovpn a Jenkins en: "Manage Jenkins" -> "Credentials" -> "Secret File"
        // ID: vpn-pasante-config
        VPN_CONFIG = credentials('vpn-pasante-config')
        
        ROOT_PASS_ID = 'root-password-prod' 
        GOOGLE_CHAT_WEBHOOK = credentials('GOOGLE_CHAT_WEBHOOK')
        
        // --- DESTINOS ---
        IP_TEST_V15 = "148.113.165.227" 
        IP_TEST_V19 = "158.69.210.128"
        BACKUP_DIR_REMOTE = "/opt/backup_integralis"

        // --- NGROK ---
        ODOO_LOCAL_URL = "https://faceable-maddison-unharangued.ngrok-free.dev" // <--- ¡VERIFICA ESTO!
        ODOO_LOCAL_DB = "prueba"
        ODOO_LOCAL_PASS = credentials('odoo-local-api-key') 
    }

    stages {
        stage('Preparar Entorno Docker') {
            steps {
                script {
                    echo "--- Instalando herramientas en el contenedor efímero ---"
                    // Como somos root dentro de este contenedor temporal, instalamos lo que queramos
                    sh """
                        apt-get update
                        apt-get install -y openvpn curl sshpass iputils-ping python3
                    """
                }
            }
        }

        stage('Conectar VPN y Descargar') {
            steps {
                script {
                    echo "--- Iniciando VPN ---"
                    
                    // Copiamos la configuración secreta a un archivo real
                    sh "cp ${env.VPN_CONFIG} /tmp/vpn_config.ovpn"

                    // Iniciamos OpenVPN en background
                    sh "openvpn --config /tmp/vpn_config.ovpn --daemon"
                    
                    echo "Esperando conexión..."
                    sleep 10
                    
                    // Verificación (opcional)
                    sh "ping -c 2 10.8.0.1 || echo 'Ping falló, pero intentamos seguir...'"

                    // --- LÓGICA DE CONTRASEÑA MAESTRA ---
                    if (params.ODOO_URL.contains('.sdb-integralis360.com')) {
                        env.MASTER_PWD = credentials('vault-sdb-integralis360.com')
                    } else if (params.ODOO_URL.contains('.dic-integralis360.com')) {
                        env.MASTER_PWD = credentials('dic-integralis360.com')
                    } else if (params.ODOO_URL.contains('lns') || params.ODOO_URL.contains('edb') || params.ODOO_URL.contains('cgs')) {
                            env.MASTER_PWD = credentials('dic-lns') 
                    } else {
                        env.MASTER_PWD = credentials('vault-integralis360.website')
                    }

                    // --- OBTENER NOMBRE DE BD ---
                    def db_response = sh(script: """
                        curl -s -k -X POST "https://${params.ODOO_URL}/web/database/list" \
                        -H "Content-Type: application/json" \
                        -d '{"params": {"master_pwd": "${env.MASTER_PWD}"}}'
                    """, returnStdout: true).trim()
                    
                    def json_db = readJSON text: db_response
                    env.DB_NAME = json_db.result[0]
                    echo "Base detectada: ${env.DB_NAME}"
                    
                    // --- DESCARGAR ---
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

        stage('Enviar y Restaurar') {
            steps {
                script {
                    // Calculamos versión Postgres
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
                        // Enviamos con sshpass (que instalamos en el primer stage)
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
        
        stage('Notificaciones') {
             steps {
                script {
                    def chat_msg = """{"text": "✅ *Respaldo Completado*\\n*Base:* ${env.NEW_DB_NAME}\\n*Tipo:* ${params.BACKUP_TYPE}\\n*URL:* ${env.FINAL_URL}"}"""
                    sh "curl -X POST -H 'Content-Type: application/json; charset=UTF-8' -d '${chat_msg}' '${env.GOOGLE_CHAT_WEBHOOK}' || true"

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
            // Como el contenedor se destruye al final, no hace falta matar la VPN, 
            // pero por si acaso falla a mitad de camino:
            sh "killall openvpn || true" 
        }
        failure {
            script {
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