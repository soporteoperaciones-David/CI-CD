pipeline {
    agent any 

    parameters {
        string(name: 'ODOO_URL', description: 'URL de producción')
        string(name: 'VERSION', description: 'Versión Destino (v15/v19)')
        string(name: 'BACKUP_DATE', defaultValue: 'latest', description: 'Fecha YYYYMMDD o latest')
        string(name: 'EXECUTED_BY', defaultValue: 'Sistema', description: 'Usuario Odoo')
        // OJO: Jenkins recibe esto como RECORD_ID o ODOO_ID. Asegúrate de usar el correcto.
        string(name: 'ODOO_ID', defaultValue: '0', description: 'ID del registro enviado por Odoo') 
        string(name: 'BACKUP_TYPE', defaultValue: 'dump', description: 'Formato')
    }

    environment {
        // --- CREDENCIALES ---
        SSH_KEY_ID = 'jenkins-ssh-key' 
        // --- CONFIG ---
        IP_TEST_V15 = "148.113.165.227" 
        IP_TEST_V19 = "158.69.210.128"
    }

    stages {
        stage('1. Preparar Entorno') {
            steps {
                script {
                    cleanWs()
                    checkout scm 
                    // Aseguramos que scripts tenga permisos por si acaso
                    sh "chmod +x scripts/*.sh || true"
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
                            docker exec -e DEBIAN_FRONTEND=noninteractive rclone-worker apt-get install -y curl unzip tzdata -qq
                            docker exec rclone-worker sh -c 'curl https://rclone.org/install.sh | bash'
                            docker exec rclone-worker mkdir -p /root/.config/rclone
                            docker cp \$RCLONE_CONF_PATH rclone-worker:/root/.config/rclone/rclone.conf
                            docker exec rclone-worker mkdir -p /workspace
                            docker cp scripts/download_backup.sh rclone-worker:/workspace/
                            docker exec rclone-worker chmod +x /workspace/download_backup.sh
                            
                            docker exec \
                                -e TZ="America/Guayaquil" \
                                -e ODOO_URL="${params.ODOO_URL}" \
                                -e VERSION="${params.VERSION}" \
                                -e BACKUP_DATE="${params.BACKUP_DATE}" \
                                rclone-worker /workspace/download_backup.sh
                        """
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
                    env.LOCAL_BACKUP_FILE = readFile('filename.txt').trim()
                    env.DB_NAME_ORIGINAL = readFile('dbname.txt').trim()
                    
                    def cleanName = env.DB_NAME_ORIGINAL.replace("-ee15", "").replace("-ee", "").replace(".com.ec", "")
                                    .replace(".com", "")
                                    .replace(".", "")
                    def dateSuffix = sh(returnStdout: true, script: 'TZ="America/Guayaquil" date +%Y%m%d').trim()
                    if (env.LOCAL_BACKUP_FILE =~ /\d{8}/) {
                        dateSuffix = (env.LOCAL_BACKUP_FILE =~ /\d{8}/)[0]
                    }

                    env.TARGET_IP = (params.VERSION == 'v15') ? env.IP_TEST_V15 : env.IP_TEST_V19
                    env.DB_OWNER = (params.VERSION == 'v15') ? 'odoo15' : 'odoo19'
                    env.BASE_NAME = cleanName
                    env.DATE_SUFFIX = dateSuffix
                    env.ODOO_SUFFIX = (params.VERSION == 'v15') ? 'ee15n2' : 'ee19'

                    echo "--- Despliegue a ${env.TARGET_IP} ---"
                    sh "curl -4 -s --connect-timeout 5 ifconfig.me || echo 'No curl output'"

                    withCredentials([
                        sshUserPrivateKey(credentialsId: 'jenkins-ssh-key', keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')
                    ]) {
                        sh '''
                            set -e
                            chmod 600 "$SSH_KEY"
                            export SSH_KEY_FILE="$SSH_KEY"
                            chmod +x scripts/get_db_name.sh
                            ./scripts/get_db_name.sh > final_db_name.txt
                        '''
                        
                        env.NEW_DB_NAME = readFile('final_db_name.txt').trim()
                        env.FINAL_URL = "https://${env.NEW_DB_NAME}.odooecuador.online/web/login"
                        env.NEW_DB_NAME_ENV = env.NEW_DB_NAME

                        sh '''
                            set -e
                            scp -4 -i "$SSH_KEY" -o StrictHostKeyChecking=no "$LOCAL_BACKUP_FILE" "ubuntu@$TARGET_IP:/tmp/"
                            scp -4 -i "$SSH_KEY" -o StrictHostKeyChecking=no scripts/restore_db.sh "ubuntu@$TARGET_IP:/tmp/"
                            
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
    } 
    
    post {     
        success {
            script {
                echo "Pipeline Exitoso. Ejecutando notificación..."
                
                // CAMBIO AQUÍ: Leemos ODOO_ID
                def r_id = params.ODOO_ID ?: "0"
                def url  = env.FINAL_URL
                def msg  = "Restauración Exitosa.\\nBase: ${env.NEW_DB_NAME}"
                
                withCredentials([usernamePassword(credentialsId: 'odoo-local-api-key', 
                                                  usernameVariable: 'USER_IGNORE', 
                                                  passwordVariable: 'ODOO_PASS')]) {
                    withEnv([
                        "ODOO_URL=https://faceable-maddison-unharangued.ngrok-free.dev",
                        "ODOO_DB=prueba"
                    ]) {
                        sh "chmod +x scripts/notify_odoo.sh"
                        // Pasamos r_id al script
                        sh "./scripts/notify_odoo.sh '${r_id}' 'done' '${url}' '${msg}'"
                    }
                }
            }
        }
        
        failure {
            script {
                echo "Pipeline Fallido. Reportando error..."
                
                // CAMBIO AQUÍ: Leemos ODOO_ID
                def r_id = params.ODOO_ID ?: "0"
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
        cleanup {
            script {
                echo "--- 🧹 Limpieza Final (Ahora sí) ---"
                sh "docker rm -f rclone-worker || true"
                cleanWs() // ¡Aquí es seguro borrar!
            }
        }
    } 

} 