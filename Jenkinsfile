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
        // ID de la credencial "Secret Text" donde guardaste la contraseña de ROOT
        ROOT_PASS_ID = 'root-password-prod' 
        GOOGLE_CHAT_WEBHOOK = credentials('GOOGLE_CHAT_WEBHOOK')
        
        // --- SERVIDORES DESTINO (IPs) ---
        // Pon aquí SOLO la IP, el usuario lo manejamos como root en el código
        IP_TEST_V15 = "192.168.1.XXX" 
        IP_TEST_V19 = "192.168.1.YYY"

        // --- ODOO LOCAL (Para reportar estado) ---
        ODOO_LOCAL_URL = "http://localhost:8079"
        ODOO_LOCAL_DB = "prueba"
        ODOO_LOCAL_PASS = credentials('odoo-local-api-key') 
    }

    stages {
        stage('Inicialización y VPN') {
            steps {
                script {
                    echo "--- Iniciando Pipeline por: ${params.EXECUTED_BY} ---"
                    // Limpieza y conexión VPN
                    sh 'sudo killall openvpn || true'
                    sh 'sudo openvpn --config /home/jenkins/pasante.ovpn --daemon'
                    sleep 10 // Esperar a que levante el túnel
                }
            }
        }

        stage('Obtener Datos y Calcular Versión PG') {
            steps {
                script {
                    // 1. Obtener contraseña maestra (Master PWD) según dominio
                    if (params.ODOO_URL.contains('.sdb-integralis360.com')) {
                        env.MASTER_PWD = credentials('vault-sdb-integralis360.com')
                    } else if (params.ODOO_URL.contains('.dic-integralis360.com')) {
                        env.MASTER_PWD = credentials('dic-integralis360.com')
                    } else if (params.ODOO_URL.contains('lns') || params.ODOO_URL.contains('edb') || params.ODOO_URL.contains('cgs')) {
                         env.MASTER_PWD = credentials('dic-lns') 
                    } else {
                        env.MASTER_PWD = credentials('vault-integralis360.website')
                    }

                    // 2. Obtener nombre real de la base de datos (curl a database/list)
                    def db_response = sh(script: """
                        curl -s -k -X POST "https://${params.ODOO_URL}/web/database/list" \
                        -H "Content-Type: application/json" \
                        -d '{"params": {"master_pwd": "${env.MASTER_PWD}"}}'
                    """, returnStdout: true).trim()
                    
                    def json_db = readJSON text: db_response
                    env.DB_NAME = json_db.result[0]

                    // 3. Lógica de Versión PostgreSQL (La inteligencia del proceso)
                    // Por defecto asumimos Postgres 17 (Opción 3)
                    env.PG_BIN_VERSION = "17" 
                    
                    if (params.ODOO_URL.contains('sdb-integralis360.com')) {
                        // Regla: SDB es Postgres 12...
                        env.PG_BIN_VERSION = "12"
                        
                        // Excepción: Si contiene 'edb' o 'cgs', vuelve a ser 17
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
                    // Definir extensión según parámetro
                    def ext = (params.BACKUP_TYPE == 'zip') ? 'zip' : 'dump'
                    env.BACKUP_FILE = "backup_${env.DB_NAME}-${date}.${ext}"
                    
                    echo "Descargando backup tipo ${params.BACKUP_TYPE}..."
                    
                    // Descarga directa desde producción
                    sh """
                        curl -k -X POST \
                        -F "master_pwd=${env.MASTER_PWD}" \
                        -F "name=${env.DB_NAME}" \
                        -F "backup_format=${params.BACKUP_TYPE}" \
                        "https://${params.ODOO_URL}/web/database/backup" \
                        -o "${env.BACKUP_FILE}"
                    """
                    
                    // Validar que bajó algo (mayor a 10KB)
                    if (fileExists(env.BACKUP_FILE)) {
                        def size = sh(script: "du -k ${env.BACKUP_FILE} | cut -f1", returnStdout: true).trim().toInteger()
                        if (size < 10) error "Error: El archivo de respaldo es demasiado pequeño o está vacío."
                    } else {
                        error "Error: No se generó el archivo de respaldo."
                    }
                }
            }
        }

        stage('Transferencia y Restore (Como ROOT)') {
            steps {
                script {
                    // Determinar IP destino y nombre final
                    def target_ip = (params.VERSION == 'v15') ? env.IP_TEST_V15 : env.IP_TEST_V19
                    def suffix = (params.VERSION == 'v15') ? 'ee15n2' : 'ee19'
                    def date = sh(script: "date +%Y%m%d", returnStdout: true).trim()
                    
                    env.NEW_DB_NAME = "${env.DB_NAME}-${date}-${suffix}"
                    env.FINAL_URL = "https://${env.NEW_DB_NAME}.odooecuador.online/web/login"

                    // Usamos la credencial de texto secreto (contraseña root)
                    withCredentials([string(credentialsId: env.ROOT_PASS_ID, variable: 'ROOT_PASS')]) {
                        
                        echo "1. Transfiriendo archivo a ${target_ip}..."
                        // Usamos sshpass para pasar la contraseña al SCP
                        sh """
                            sshpass -p '${ROOT_PASS}' scp -o StrictHostKeyChecking=no ${env.BACKUP_FILE} root@${target_ip}:${env.BACKUP_DIR_REMOTE}/
                        """

                        echo "2. Ejecutando Restore Remoto con PG Versión: ${env.PG_BIN_VERSION}"
                        // Usamos sshpass para pasar la contraseña al SSH
                        // Nota: Al ser root, NO usamos sudo dentro del servidor
                        sh """
                            sshpass -p '${ROOT_PASS}' ssh -o StrictHostKeyChecking=no root@${target_ip} '
                                # A. Configurar alternativas de Postgres
                                update-alternatives --set psql /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/psql
                                update-alternatives --set pg_dump /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/pg_dump
                                update-alternatives --set pg_restore /usr/lib/postgresql/${env.PG_BIN_VERSION}/bin/pg_restore
                                
                                # B. Ejecutar Restore contra Odoo local (puerto 8069)
                                echo "Iniciando Restore en Odoo..."
                                curl -k -X POST "http://localhost:8069/web/database/restore" \
                                    -F "master_pwd=${env.MASTER_PWD}" \
                                    -F "file=@${env.BACKUP_DIR_REMOTE}/${env.BACKUP_FILE}" \
                                    -F "name=${env.NEW_DB_NAME}" \
                                    -F "copy=true"
                                
                                # C. Borrar el archivo de respaldo para liberar espacio
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
                        {"text": "*Respaldo Completado*\\n*Base:* ${env.NEW_DB_NAME}\\n*Tipo:* ${params.BACKUP_TYPE}\\n*Solicitado por:* ${params.EXECUTED_BY}\\n*URL:* ${env.FINAL_URL}"}
                    """
                    sh """
                        curl -X POST -H 'Content-Type: application/json; charset=UTF-8' \
                        -d '${chat_msg}' \
                        "${env.GOOGLE_CHAT_WEBHOOK}" || true
                    """

                    // 2. Callback a Odoo (Actualizar registro a Done)
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
            cleanWs() // Borra el dump del Jenkins Agent
            sh 'sudo killall openvpn || true' // Cierra VPN
        }
        failure {
            script {
                // Si falla, avisar a Odoo que hubo error
                if (params.ODOO_ID) {
                    def err_payload = """
                    {
                        "jsonrpc": "2.0", "method": "call",
                        "params": {
                            "service": "object", "method": "execute_kw",
                            "args": [
                                "${env.ODOO_LOCAL_DB}", 2, "${env.ODOO_LOCAL_PASS}",
                                "backup.automation", "write",
                                [[${params.ODOO_ID}], {"state": "error", "jenkins_log": "Fallo crítico. Revisar consola Jenkins."}]
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