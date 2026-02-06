pipeline {
    agent any

    parameters {
        string(name: 'ODOO_URL', defaultValue: '', description: 'URL de producción (ej. produccion.sdb-integralis360.com)')
        choice(name: 'BACKUP_TYPE', choices: ['dump', 'zip'], description: 'Formato del respaldo')
        choice(name: 'VERSION', choices: ['v15', 'v19'], description: 'Versión de Odoo destino')
        string(name: 'EXECUTED_BY', defaultValue: 'Sistema', description: 'Usuario Odoo que disparó el proceso')
        string(name: 'ODOO_ID', defaultValue: '', description: 'ID del registro en el módulo de automatización')
    }

    environment {
        // --- RUTAS ---
        BACKUP_DIR_REMOTE = "/opt/backup_integralis" 
        
        // --- CREDENCIALES ---
        ROOT_PASS_ID = 'root-password-prod' 
        GOOGLE_CHAT_WEBHOOK = credentials('GOOGLE_CHAT_WEBHOOK')
        
        // --- SERVIDORES DESTINO (IPs) ---
        IP_TEST_V15 = "148.113.165.227" 
        IP_TEST_V19 = "158.69.210.128"

        // --- ODOO LOCAL (Para reportar estado) ---
        // Nota: Asegúrate que el puerto 8079 es correcto. Normalmente es 8069.
        ODOO_LOCAL_URL = "https://faceable-maddison-unharangued.ngrok-free.dev"
        ODOO_LOCAL_DB = "prueba"
        ODOO_LOCAL_PASS = credentials('odoo-local-api-key') 
    }

    stages {
        stage('Inicialización y VPN') {
            steps {
                script {
                    echo "--- Iniciando Pipeline por: ${params.EXECUTED_BY} ---"
                    
                    // 1. DIAGNÓSTICO (Para ver en los logs si algo falta)
                    sh 'echo "PATH actual: $PATH"'
                    sh 'ls -l /usr/bin/sudo || echo "ALERTA: El archivo sudo NO existe en /usr/bin"'

                    // 2. COMANDOS CON RUTA ABSOLUTA (La solución al error not found)
                    // Usamos /usr/bin/sudo para obligarlo a usar ese archivo
                    sh '/usr/bin/sudo killall openvpn || true'
                    sh '/usr/bin/sudo openvpn --config /home/jenkins/pasante.ovpn --daemon'
                    
                    echo "Esperando conexión VPN..."
                    sleep 10 
                    
                    // 3. VERIFICACIÓN DE CONEXIÓN
                    sh "ping -c 2 8.8.8.8 || echo 'Advertencia: No hay ping, pero continuamos...'"
                }
            }
        }

        stage('Obtener Datos y Calcular Versión PG') {
            steps {
                script {
                    // 1. Obtener contraseña maestra
                    if (params.ODOO_URL.contains('.sdb-integralis360.com')) {
                        env.MASTER_PWD = credentials('vault-sdb-integralis360.com')
                    } else if (params.ODOO_URL.contains('.dic-integralis360.com')) {
                        env.MASTER_PWD = credentials('dic-integralis360.com')
                    } else if (params.ODOO_URL.contains('lns') || params.ODOO_URL.contains('edb') || params.ODOO_URL.contains('cgs')) {
                         env.MASTER_PWD = credentials('dic-lns') 
                    } else {
                        env.MASTER_PWD = credentials('vault-integralis360.website')
                    }

                    // 2. Obtener nombre real de la base de datos
                    def db_response = sh(script: """
                        curl -s -k -X POST "https://${params.ODOO_URL}/web/database/list" \
                        -H "Content-Type: application/json" \
                        -d '{"params": {"master_pwd": "${env.MASTER_PWD}"}}'
                    """, returnStdout: true).trim()
                    
                    // Parsear JSON
                    def json_db = readJSON text: db_response
                    env.DB_NAME = json_db.result[0]

                    // 3. Lógica de Versión PostgreSQL
                    env.PG_BIN_VERSION = "17" // Default
                    
                    if (params.ODOO_URL.contains('sdb-integralis360.com')) {
                        env.PG_BIN_VERSION = "12"
                        // Excepción para edb/cgs
                        if (env.DB_NAME.contains('edb') || env.DB_NAME.contains('cgs')) {
                            env.PG_BIN_VERSION = "17"
                            echo "Excepción detectada (edb/cgs): Usando PostgreSQL 17"
                        } else {
                            echo "Dominio sdb estándar: Usando PostgreSQL 12"
                        }
                    } else {
                        echo "Dominio estándar: Usando PostgreSQL 17"
                    }
                }
            }
        }

        stage('Descargar Respaldo (Jenkins Workspace)') {
            steps {
                script {
                    def date = sh(script: "date +%Y%m%d", returnStdout: true).trim()
                    def ext = (params.BACKUP_TYPE == 'zip') ? 'zip' : 'dump'
                    env.BACKUP_FILE = "backup_${env.DB_NAME}-${date}.${ext}"
                    
                    echo "Descargando backup tipo ${params.BACKUP_TYPE}..."
                    
                    sh """
                        curl -k -X POST \
                        -F "master_pwd=${env.MASTER_PWD}" \
                        -F "name=${env.DB_NAME}" \
                        -F "backup_format=${params.BACKUP_TYPE}" \
                        "https://${params.ODOO_URL}/web/database/backup" \
                        -o "${env.BACKUP_FILE}"
                    """
                    
                    // Validación de archivo
                    if (fileExists(env.BACKUP_FILE)) {
                        def size = sh(script: "du -k ${env.BACKUP_FILE} | cut -f1", returnStdout: true).trim().toInteger()
                        if (size < 10) error "Error: El archivo de respaldo es demasiado pequeño (<10KB)."
                    } else {
                        error "Error: No se generó el archivo de respaldo."
                    }
                }
            }
        }

        stage('Transferencia y Restore (Como ROOT)') {
            steps {
                script {
                    def target_ip = (params.VERSION == 'v15') ? env.IP_TEST_V15 : env.IP_TEST_V19
                    def suffix = (params.VERSION == 'v15') ? 'ee15n2' : 'ee19'
                    def date = sh(script: "date +%Y%m%d", returnStdout: true).trim()
                    
                    env.NEW_DB_NAME = "${env.DB_NAME}-${date}-${suffix}"
                    env.FINAL_URL = "https://${env.NEW_DB_NAME}.odooecuador.online/web/login"

                    withCredentials([string(credentialsId: env.ROOT_PASS_ID, variable: 'ROOT_PASS')]) {
                        
                        echo "Transfiriendo a ${target_ip}..."
                        sh """
                            sshpass -p '${ROOT_PASS}' scp -o StrictHostKeyChecking=no ${env.BACKUP_FILE} root@${target_ip}:${env.BACKUP_DIR_REMOTE}/
                        """

                        echo "Ejecutando Restore con PG Versión: ${env.PG_BIN_VERSION}"
                        sh """
                            sshpass -p '${ROOT_PASS}' ssh -o StrictHostKeyChecking=no root@${target_ip} '
                                update-alternatives --set psql /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/psql
                                update-alternatives --set pg_dump /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/pg_dump
                                update-alternatives --set pg_restore /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/pg_restore
                                
                                echo "Restaurando..."
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
                    // 1. Google Chat
                    def chat_msg = """
                        {"text": "*Respaldo Completado*\\n*Base:* ${env.NEW_DB_NAME}\\n*Tipo:* ${params.BACKUP_TYPE}\\n*Usuario:* ${params.EXECUTED_BY}\\n*URL:* ${env.FINAL_URL}"}
                    """
                    sh """
                        curl -X POST -H 'Content-Type: application/json; charset=UTF-8' \
                        -d '${chat_msg}' \
                        "${env.GOOGLE_CHAT_WEBHOOK}" || true
                    """

                    // 2. Odoo Callback (Success)
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
                                    "jenkins_log": "Exitoso. PG Ver: ${env.PG_BIN_VERSION}"
                                }]
                            ]
                        }
                    }
                    """
                    sh """
                        curl -X POST -H "Content-Type: application/json" \
                        -d '${odoo_payload}' \
                        "${env.ODOO_LOCAL_URL}/jsonrpc"
                    """
                }
            }
        }
    }

    post {
        always {
            cleanWs()
            // Intentamos cerrar la VPN
            sh 'sudo killall openvpn || true'
        }
        failure {
            script {
                // ESTE BLOQUE SE EJECUTA SI FALLA SUDO, OPENVPN O CUALQUIER OTRA COSA
                echo "❌ Pipeline Fallido. Reportando a Odoo..."
                
                if (params.ODOO_ID) {
                    // Creamos un mensaje con el Link al Build para depurar
                    def error_msg = "Fallo crítico en Jenkins Build #${env.BUILD_NUMBER}. Ver logs: ${env.BUILD_URL}"
                    
                    def err_payload = """
                    {
                        "jsonrpc": "2.0", "method": "call",
                        "params": {
                            "service": "object", "method": "execute_kw",
                            "args": [
                                "${env.ODOO_LOCAL_DB}", 2, "${env.ODOO_LOCAL_PASS}",
                                "backup.automation", "write",
                                [[${params.ODOO_ID}], {
                                    "state": "error", 
                                    "jenkins_log": "${error_msg}"
                                }]
                            ]
                        }
                    }
                    """
                    // Enviamos el error a Odoo
                    sh """
                        curl -X POST -H 'Content-Type: application/json' \
                        -d '${err_payload}' \
                        "${env.ODOO_LOCAL_URL}/jsonrpc" || echo "No se pudo conectar a Odoo para reportar error"
                    """
                }
            }
        }
    }
}