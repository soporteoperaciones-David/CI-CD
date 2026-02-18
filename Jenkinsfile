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

        stage('3. Restaurar (SSH Seguro)') {
            steps {
                script {
                    env.LOCAL_BACKUP_FILE = readFile('filename.txt').trim()
                    env.DB_NAME_ORIGINAL = readFile('dbname.txt').trim()
                    
                    def cleanName = env.DB_NAME_ORIGINAL.replace("-ee15", "").replace("-ee", "")
                    
                    // Ajuste zona horaria manual
                    def dateSuffix = sh(returnStdout: true, script: 'TZ="America/Guayaquil" date +%Y%m%d').trim()
                    if (env.LOCAL_BACKUP_FILE =~ /\d{8}/) {
                        dateSuffix = (env.LOCAL_BACKUP_FILE =~ /\d{8}/)[0]
                    }

                    def odooVerSuffix = (params.VERSION == 'v15') ? 'ee15n2' : 'ee19'
                    
                    if (params.VERSION == 'v15') {
                        env.TARGET_IP = env.IP_TEST_V15
                        env.DB_OWNER = 'odoo15'
                    } else {
                        env.TARGET_IP = env.IP_TEST_V19
                        env.DB_OWNER = 'odoo19'
                    }

                    echo "--- Iniciando Despliegue con Llave SSH ---"
                    
                    withCredentials([sshUserPrivateKey(credentialsId: env.SSH_KEY_ID, keyFileVariable: 'MY_SSH_KEY_FILE', usernameVariable: 'SSH_USER')]) {
                        sh """
                            docker rm -f ssh-deployer || true
                            
                            # --network host: VITAL
                            docker run -d --name ssh-deployer --network host ubuntu:22.04 sleep infinity
                            
                            docker exec ssh-deployer apt-get update -qq 
                            docker exec ssh-deployer apt-get install -y openssh-client curl -qq

                            # Copiamos scripts y backup
                            docker cp scripts/restore_db.sh ssh-deployer:/tmp/
                            docker cp scripts/get_db_name.sh ssh-deployer:/tmp/
                            docker cp "${env.LOCAL_BACKUP_FILE}" ssh-deployer:/tmp/
                            
                            # Instalamos llave
                            docker cp \$MY_SSH_KEY_FILE ssh-deployer:/tmp/id_rsa
                            docker exec ssh-deployer chmod 600 /tmp/id_rsa
                            
                            # PASO A: Smart Naming (Corregido para usar IPv4 y script actualizado)
                            echo ">> Calculando nombre único..."
                            docker exec \
                                -e SSH_KEY_FILE="/tmp/id_rsa" \
                                -e TARGET_IP="${env.TARGET_IP}" \
                                -e BASE_NAME="${cleanName}" \
                                -e DATE_SUFFIX="${dateSuffix}" \
                                -e ODOO_SUFFIX="${odooVerSuffix}" \
                                ssh-deployer bash -c 'chmod +x /tmp/get_db_name.sh && /tmp/get_db_name.sh > /tmp/final_db_name.txt'
                            
                            docker cp ssh-deployer:/tmp/final_db_name.txt .
                        """
                        
                        env.NEW_DB_NAME = readFile('final_db_name.txt').trim()
                        env.FINAL_URL = "https://${env.NEW_DB_NAME}.odooecuador.online/web/login"
                        
                        // PASO B: Restauración (Agregado -4 para forzar IPv4)
                        sh """
                            echo ">> Enviando archivos al servidor..."
                            # SCP con -4 (IPv4 Only)
                            docker exec ssh-deployer scp -4 -i /tmp/id_rsa -o StrictHostKeyChecking=no -o ConnectTimeout=20 /tmp/"${env.LOCAL_BACKUP_FILE}" ubuntu@${env.TARGET_IP}:/tmp/
                            docker exec ssh-deployer scp -4 -i /tmp/id_rsa -o StrictHostKeyChecking=no -o ConnectTimeout=20 /tmp/restore_db.sh ubuntu@${env.TARGET_IP}:/tmp/
                        
                            echo ">> Restaurando base: ${env.NEW_DB_NAME}..."
                            # SSH con -4 (IPv4 Only)
                            docker exec ssh-deployer ssh -4 -i /tmp/id_rsa -o StrictHostKeyChecking=no -o ConnectTimeout=20 ubuntu@${env.TARGET_IP} \
                                "export NEW_DB_NAME='${env.NEW_DB_NAME}' && \
                                 export DB_OWNER='${env.DB_OWNER}' && \
                                 export LOCAL_BACKUP_FILE='${env.LOCAL_BACKUP_FILE}' && \
                                 chmod +x /tmp/restore_db.sh && /tmp/restore_db.sh"
                                
                            docker rm -f ssh-deployer
                        """
                    }
                }
            }
        }
        
        stage('Notificar') {
            steps {
                script {
                    echo "--- Notificando Éxito ---"
                    def chat_msg = """{"text": "✅ *Restauración Exitosa*\\n*Base:* ${env.NEW_DB_NAME}\\n*URL:* ${env.FINAL_URL}"}"""
                    sh "curl -X POST -H 'Content-Type: application/json; charset=UTF-8' -d '${chat_msg}' '${env.GOOGLE_CHAT_WEBHOOK}' || true"
                    
                    // Notificar Odoo (Tu código existente aquí)
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
                 // Tu notificación de error existente
                 sh "echo Falla" 
            }
        }
    }
}