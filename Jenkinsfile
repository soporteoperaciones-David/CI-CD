pipeline {
    agent any 

    parameters {
        string(name: 'ODOO_URL', description: 'URL de producción (para identificar carpeta)')
        string(name: 'VERSION', description: 'Versión Destino (v15/v19)')
        string(name: 'BACKUP_DATE', defaultValue: 'latest', description: 'Fecha YYYYMMDD o "latest"')
        string(name: 'EXECUTED_BY', defaultValue: 'Sistema', description: 'Usuario Odoo')
        string(name: 'ODOO_ID', defaultValue: '', description: 'ID del registro en Odoo')
        string(name: 'BACKUP_TYPE', defaultValue: 'dump', description: 'Formato (siempre dump)')
    }

    environment {
        // --- CREDENCIALES ---
        SSH_PASS_V15 = credentials('root-pass-v15') 
        SSH_PASS_V19 = credentials('ssh-pass-v19')
        GOOGLE_CHAT_WEBHOOK = credentials('GOOGLE_CHAT_WEBHOOK')
        ODOO_LOCAL_PASS = credentials('odoo-local-api-key') 
        
        // --- CONFIG ---
        IP_TEST_V15 = "148.113.165.227" 
        IP_TEST_V19 = "158.69.210.128"
        
        // URL de tu Odoo local para reportar estado (ajustar si cambia ngrok)
        ODOO_LOCAL_URL = "https://faceable-maddison-unharangued.ngrok-free.dev" 
        ODOO_LOCAL_DB = "prueba"
    }

    stages {
        stage('1. Preparar Entorno') {
            steps {
                script {
                    echo "--- Limpiando Workspace ---"
                    cleanWs()
                    // Descargamos los scripts más recientes del repo (incluyendo get_db_name.sh)
                    checkout scm 
                }
            }
        }

        stage('2. Descargar Backup (Docker + Rclone)') {
            steps {
                script {
                    // Inyectamos el archivo de configuración secreto de Rclone
                    withCredentials([file(credentialsId: 'rclone-config-file', variable: 'RCLONE_CONF_PATH')]) {
                        sh """
                            echo "--- Iniciando Worker de Descarga ---"
                            docker rm -f rclone-worker || true
                            
                            # Usamos Ubuntu y le instalamos Rclone al vuelo
                            docker run -d --name rclone-worker ubuntu:22.04 sleep infinity
                            
                            docker exec rclone-worker apt-get update -qq
                            docker exec rclone-worker apt-get install -y curl unzip -qq
                            
                            # Instalamos Rclone oficial
                            docker exec rclone-worker sh -c 'curl https://rclone.org/install.sh | bash'
                            
                            # Configuramos Rclone con tu archivo secreto
                            docker exec rclone-worker mkdir -p /root/.config/rclone
                            docker cp \$RCLONE_CONF_PATH rclone-worker:/root/.config/rclone/rclone.conf
                            
                            # Preparamos script de descarga
                            docker exec rclone-worker mkdir -p /workspace
                            docker cp scripts/download_backup.sh rclone-worker:/workspace/
                            docker exec rclone-worker chmod +x /workspace/download_backup.sh
                            
                            echo "--- Ejecutando Script de Descarga ---"
                        """
                        
                        // Ejecutamos el script pasando las variables de entorno
                        sh """
                            docker exec \
                                -e ODOO_URL="${params.ODOO_URL}" \
                                -e VERSION="${params.VERSION}" \
                                -e BACKUP_DATE="${params.BACKUP_DATE}" \
                                rclone-worker /workspace/download_backup.sh
                        """
                        
                        // Extraemos los resultados al host (Jenkins)
                        sh """
                            docker cp rclone-worker:/workspace/filename.txt .
                            docker cp rclone-worker:/workspace/dbname.txt .
                            
                            FILENAME=\$(cat filename.txt)
                            echo "Archivo descargado: \$FILENAME"
                            
                            docker cp rclone-worker:/workspace/\$FILENAME .
                            docker rm -f rclone-worker
                        """
                    }
                }
            }
        }

        stage('3. Restaurar en Servidor Test') {
            steps {
                script {
                    env.LOCAL_BACKUP_FILE = readFile('filename.txt').trim()
                    env.DB_NAME_ORIGINAL = readFile('dbname.txt').trim()
                    
                    // --- Preparación de Variables para el Smart Naming ---
                    def cleanName = env.DB_NAME_ORIGINAL.replace("-ee15", "").replace("-ee", "")
                    def dateSuffix = sh(returnStdout: true, script: 'date +%Y%m%d').trim()
                    
                    // Si el backup ya trae fecha en el nombre, la usamos
                    if (env.LOCAL_BACKUP_FILE =~ /\d{8}/) {
                        dateSuffix = (env.LOCAL_BACKUP_FILE =~ /\d{8}/)[0]
                    }

                    // Sufijo de versión Odoo
                    def odooVerSuffix = (params.VERSION == 'v15') ? 'ee15n2' : 'ee19'
                    
                    // Selección de IP y Password
                    if (params.VERSION == 'v15') {
                        env.TARGET_IP = env.IP_TEST_V15
                        env.SELECTED_PASS = env.SSH_PASS_V15
                        env.DB_OWNER = 'odoo15'
                    } else {
                        env.TARGET_IP = env.IP_TEST_V19
                        env.SELECTED_PASS = env.SSH_PASS_V19
                        env.DB_OWNER = 'odoo19'
                    }
                    
                    echo "--- Calculando Nombre Único (Smart Naming) ---"

                    // Usamos un contenedor ligero para SSHPASS
                    sh """
                        docker rm -f ssh-deployer || true
                        docker run -d --name ssh-deployer ubuntu:22.04 sleep infinity
                        docker exec ssh-deployer apt-get update -qq && docker exec ssh-deployer apt-get install -y sshpass openssh-client -qq
                        
                        # Copiamos scripts y backup al contenedor
                        docker cp scripts/restore_db.sh ssh-deployer:/tmp/
                        docker cp scripts/get_db_name.sh ssh-deployer:/tmp/
                        docker cp "${env.LOCAL_BACKUP_FILE}" ssh-deployer:/tmp/
                        
                        # PASO A: Ejecutamos get_db_name.sh para calcular el nombre libre (v2, v3...)
                        # La salida se guarda en /tmp/final_db_name.txt dentro del contenedor
                        docker exec \
                            -e MY_SSH_PASS="${env.SELECTED_PASS}" \
                            -e TARGET_IP="${env.TARGET_IP}" \
                            -e BASE_NAME="${cleanName}" \
                            -e DATE_SUFFIX="${dateSuffix}" \
                            -e ODOO_SUFFIX="${odooVerSuffix}" \
                            ssh-deployer bash -c 'chmod +x /tmp/get_db_name.sh && /tmp/get_db_name.sh > /tmp/final_db_name.txt'
                            
                        # Traemos el nombre calculado a Jenkins
                        docker cp ssh-deployer:/tmp/final_db_name.txt .
                    """
                    
                    // Leemos el nombre final calculado
                    env.NEW_DB_NAME = readFile('final_db_name.txt').trim()
                    env.FINAL_URL = "https://${env.NEW_DB_NAME}.odooecuador.online/web/login"

                    echo "--- Restaurando base definitiva: ${env.NEW_DB_NAME} ---"
                    
                    // PASO B: Ejecutamos la restauración con el nombre YA confirmado
                    sh """
                        docker exec \
                            -e MY_SSH_PASS="${env.SELECTED_PASS}" \
                            -e TARGET_IP="${env.TARGET_IP}" \
                            -e LOCAL_BACKUP_FILE="${env.LOCAL_BACKUP_FILE}" \
                            -e NEW_DB_NAME="${env.NEW_DB_NAME}" \
                            -e DB_OWNER="${env.DB_OWNER}" \
                            ssh-deployer bash -c 'chmod +x /tmp/restore_db.sh && /tmp/restore_db.sh'
                            
                        docker rm -f ssh-deployer
                    """
                }
            }
        }
        
        stage('Notificar') {
            steps {
                script {
                    echo "--- Notificando Éxito ---"
                    def chat_msg = """{"text": "*Restauración Exitosa*\\n*Base:* ${env.NEW_DB_NAME}\\n*URL:* ${env.FINAL_URL}"}"""
                    sh "curl -X POST -H 'Content-Type: application/json; charset=UTF-8' -d '${chat_msg}' '${env.GOOGLE_CHAT_WEBHOOK}' || true"

                    // Actualizar Odoo
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
                                    "jenkins_log": "Exito. Restaurado como ${env.NEW_DB_NAME} (Smart Naming)"
                                }]
                            ]
                        }
                    }
                    """
                    sh "curl -X POST -H 'Content-Type: application/json' -d '${odoo_payload}' '${env.ODOO_LOCAL_URL}/jsonrpc' || true"
                }
            }
        }
    }

    post {
        always {
            script {
                sh "docker rm -f rclone-worker ssh-deployer || true"
                cleanWs()
            }
        }
        failure {
            script {
                def fail_msg = """{"text": "*Fallo en Pipeline*\\nRevisar Logs en Jenkins."}"""
                sh "curl -X POST -H 'Content-Type: application/json; charset=UTF-8' -d '${fail_msg}' '${env.GOOGLE_CHAT_WEBHOOK}' || true"
                
                // Avisar a Odoo del error
                if (params.ODOO_ID) {
                     def error_payload = """
                    {
                        "jsonrpc": "2.0", "method": "call",
                        "params": {
                            "service": "object", "method": "execute_kw",
                            "args": [
                                "${env.ODOO_LOCAL_DB}", 2, "${env.ODOO_LOCAL_PASS}",
                                "backup.automation", "write",
                                [[${params.ODOO_ID}], {"state": "error", "jenkins_log": "Fallo en Jenkins. Ver consola."}]
                            ]
                        }
                    }
                    """
                    sh "curl -X POST -H 'Content-Type: application/json' -d '${error_payload}' '${env.ODOO_LOCAL_URL}/jsonrpc' || true"
                }
            }
        }
    }
}