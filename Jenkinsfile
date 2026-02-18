pipeline {
    agent any 

    parameters {
        string(name: 'ODOO_URL', description: 'URL de producción')
        string(name: 'VERSION', description: 'Versión Destino (v15/v19)')
        string(name: 'BACKUP_DATE', defaultValue: 'latest', description: 'Fecha YYYYMMDD o latest')
        string(name: 'EXECUTED_BY', defaultValue: 'Sistema', description: 'Usuario Odoo')
        string(name: 'ODOO_ID', defaultValue: '', description: 'ID del registro en Odoo')
        string(name: 'BACKUP_TYPE', defaultValue: 'dump', description: 'Formato')
    }

    environment {
        // --- CREDENCIALES ---
        SSH_KEY_ID = 'jenkins-ssh-key' 
        GOOGLE_CHAT_WEBHOOK = credentials('GOOGLE_CHAT_WEBHOOK')
        ODOO_LOCAL_PASS = credentials('odoo-local-api-key') 
        
        // --- CONFIG ---
        IP_TEST_V15 = "148.113.165.227" 
        IP_TEST_V19 = "158.69.210.128"
        ODOO_LOCAL_URL = "https://faceable-maddison-unharangued.ngrok-free.dev" 
        ODOO_LOCAL_DB = "prueba"
    }

    stages {
        stage('1. Preparar Entorno') {
            steps {
                script {
                    cleanWs()
                    checkout scm 
                }
            }
        }

        stage('2. Descargar Backup') {
            steps {
                script {
                    withCredentials([file(credentialsId: 'rclone-config-file', variable: 'RCLONE_CONF_PATH')]) {
                        sh """
                            echo "--- Iniciando Worker de Descarga ---"
                            docker rm -f rclone-worker || true
                            
                            docker run -d --name rclone-worker --network host ubuntu:22.04 sleep infinity
                            
                            docker exec rclone-worker apt-get update -qq
                            # INSTALAMOS TZDATA (Vital para la fecha)
                            docker exec -e DEBIAN_FRONTEND=noninteractive rclone-worker apt-get install -y curl unzip tzdata -qq
                            
                            docker exec rclone-worker sh -c 'curl https://rclone.org/install.sh | bash'
                            
                            # Config Rclone
                            docker exec rclone-worker mkdir -p /root/.config/rclone
                            docker cp \$RCLONE_CONF_PATH rclone-worker:/root/.config/rclone/rclone.conf
                            
                            # Scripts
                            docker exec rclone-worker mkdir -p /workspace
                            docker cp scripts/download_backup.sh rclone-worker:/workspace/
                            docker exec rclone-worker chmod +x /workspace/download_backup.sh
                            
                            # Ejecutar Descarga (Pasando TZ explícitamente)
                            docker exec \
                                -e TZ="America/Guayaquil" \
                                -e ODOO_URL="${params.ODOO_URL}" \
                                -e VERSION="${params.VERSION}" \
                                -e BACKUP_DATE="${params.BACKUP_DATE}" \
                                rclone-worker /workspace/download_backup.sh
                        """
                        
                        // Traer resultados
                        sh """
                            docker cp rclone-worker:/workspace/filename.txt .
                            docker cp rclone-worker:/workspace/dbname.txt .
                            FILENAME=\$(cat filename.txt)
                            docker cp rclone-worker:/workspace/\$FILENAME .
                            docker rm -f rclone-worker
                        """
                    }
                }
            }
        }
        stage('3. Restaurar') {
            steps {
                script {
                    // 1. Preparar Datos
                    env.LOCAL_BACKUP_FILE = readFile('filename.txt').trim()
                    env.DB_NAME_ORIGINAL = readFile('dbname.txt').trim()
                    
                    def cleanName = env.DB_NAME_ORIGINAL.replace("-ee15", "").replace("-ee", "")
                    def dateSuffix = sh(returnStdout: true, script: 'TZ="America/Guayaquil" date +%Y%m%d').trim()
                    if (env.LOCAL_BACKUP_FILE =~ /\d{8}/) {
                        dateSuffix = (env.LOCAL_BACKUP_FILE =~ /\d{8}/)[0]
                    }

                    // 2. Variables de entorno
                    env.TARGET_IP = (params.VERSION == 'v15') ? env.IP_TEST_V15 : env.IP_TEST_V19
                    env.DB_OWNER = (params.VERSION == 'v15') ? 'odoo15' : 'odoo19'
                    env.BASE_NAME = cleanName
                    env.DATE_SUFFIX = dateSuffix
                    env.ODOO_SUFFIX = (params.VERSION == 'v15') ? 'ee15n2' : 'ee19'

                    echo "--- Despliegue a ${env.TARGET_IP} (Forzando IPv4) ---"
                    
                    // --- DIAGNÓSTICO RÁPIDO ---
                    // Esto nos dirá con qué IP está saliendo realmente Jenkins
                    sh "curl -4 -s --connect-timeout 5 ifconfig.me || echo 'No curl output'"

                    // 3. Bloque SSH (Estructura Mentor + Fix IPv4)
                    withCredentials([
                        sshUserPrivateKey(credentialsId: 'jenkins-ssh-key', 
                                          keyFileVariable: 'SSH_KEY', 
                                          usernameVariable: 'SSH_USER')
                    ]) {
                        // Usamos comillas simples para seguridad (igual que el mentor)
                        sh '''
                            set -e
                            chmod 600 "$SSH_KEY"

                            # --- PASO A: Smart Naming ---
                            echo ">> Calculando nombre disponible..."
                            export SSH_KEY_FILE="$SSH_KEY"
                            
                            # Nos aseguramos que el script sea ejecutable
                            chmod +x scripts/get_db_name.sh
                            
                            # Ejecutamos el script. (IMPORTANTE: El script sh también debe usar -4 o la variable SSH_KEY_FILE)
                            ./scripts/get_db_name.sh > final_db_name.txt
                        '''
                        
                        env.NEW_DB_NAME = readFile('final_db_name.txt').trim()
                        env.FINAL_URL = "https://${env.NEW_DB_NAME}.odooecuador.online/web/login"
                        
                        // Variable para el siguiente bloque
                        env.NEW_DB_NAME_ENV = env.NEW_DB_NAME

                        sh '''
                            set -e
                            echo ">> Enviando archivos a $TARGET_IP..."

                            # --- PASO B: Transferencia SCP (CON -4 OBLIGATORIO) ---
                            # Agregamos -4 para evitar que se pierda por IPv6
                            scp -4 -i "$SSH_KEY" -o StrictHostKeyChecking=no "$LOCAL_BACKUP_FILE" "ubuntu@$TARGET_IP:/tmp/"
                            scp -4 -i "$SSH_KEY" -o StrictHostKeyChecking=no scripts/restore_db.sh "ubuntu@$TARGET_IP:/tmp/"
                            
                            echo ">> Restaurando base: $NEW_DB_NAME_ENV ..."
                            
                            # --- PASO C: Ejecución Remota SSH (CON -4 OBLIGATORIO) ---
                            ssh -4 -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@$TARGET_IP" \
                                "export NEW_DB_NAME='$NEW_DB_NAME_ENV' && \
                                 export DB_OWNER='$DB_OWNER' && \
                                 export LOCAL_BACKUP_FILE='$LOCAL_BACKUP_FILE' && \
                                 chmod +x /tmp/restore_db.sh && \
                                 /tmp/restore_db.sh"
                        '''
                    }
                }
            }
        }
        
        
    post {
        always {
            script {
                echo "--- Limpieza General ---"
                sh "docker rm -f rclone-worker || true"
                cleanWs()
            }
        }
        
        success {
            script {
                echo "Pipeline Exitoso. Ejecutando notificación..."
                
                def r_id = params.RECORD_ID ?: "0"
                def url  = env.FINAL_URL
                def msg  = "Restauración Exitosa.\\nBase: ${env.NEW_DB_NAME}"
                
                // Usamos la credencial corregida (Username with Password)
                withCredentials([usernamePassword(credentialsId: 'odoo-local-api-key', 
                                                  usernameVariable: 'USER_IGNORE', 
                                                  passwordVariable: 'ODOO_PASS')]) {
                    withEnv([
                        "ODOO_URL=https://faceable-maddison-unharangued.ngrok-free.dev",  // <--- PON TU URL REAL
                        "ODOO_DB=prueba"              // <--- PON TU BASE REAL
                    ]) {
                        sh "chmod +x scripts/notify_odoo.sh"
                        sh "./scripts/notify_odoo.sh '${r_id}' 'done' '${url}' '${msg}'"
                    }
                }
            }
        }
        
        failure {
            script {
                echo "Pipeline Fallido. Reportando error..."
                
                def r_id = params.RECORD_ID ?: "0"
                def msg  = "Fallo en Jenkins. Ver logs: ${env.BUILD_URL}"

                withCredentials([usernamePassword(credentialsId: 'odoo-local-api-key', 
                                                  usernameVariable: 'USER_IGNORE', 
                                                  passwordVariable: 'ODOO_PASS')]) {
                    withEnv([
                        "ODOO_URL=https://faceable-maddison-unharangued.ngrok-free.dev", 
                        "ODOO_DB=prueba"
                    ]) {
                        sh "chmod +x scripts/notify_odoo.sh"
                        sh "./scripts/notify_odoo.sh '${r_id}' 'error' 'N/A' '${msg}'"
                    }
                }
            }
        }
    }
}