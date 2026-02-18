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

        stage('3. Restaurar (Directo)') {
            steps {
                script {
                    env.LOCAL_BACKUP_FILE = readFile('filename.txt').trim()
                    env.DB_NAME_ORIGINAL = readFile('dbname.txt').trim()
                    
                    def cleanName = env.DB_NAME_ORIGINAL.replace("-ee15", "").replace("-ee", "")
                    
                    // Calculamos fecha (Hora Ecuador)
                    def dateSuffix = sh(returnStdout: true, script: 'TZ="America/Guayaquil" date +%Y%m%d').trim()
                    if (env.LOCAL_BACKUP_FILE =~ /\d{8}/) {
                        dateSuffix = (env.LOCAL_BACKUP_FILE =~ /\d{8}/)[0]
                    }

                    // Definimos variables de entorno para usar dentro del sh
                    env.TARGET_IP = (params.VERSION == 'v15') ? env.IP_TEST_V15 : env.IP_TEST_V19
                    env.DB_OWNER = (params.VERSION == 'v15') ? 'odoo15' : 'odoo19'
                    env.BASE_NAME = cleanName
                    env.DATE_SUFFIX = dateSuffix
                    env.ODOO_SUFFIX = (params.VERSION == 'v15') ? 'ee15n2' : 'ee19'

                    echo "--- Iniciando Despliegue Directo a ${env.TARGET_IP} ---"

                    // Usamos withCredentials
                    withCredentials([sshUserPrivateKey(credentialsId: 'jenkins-ssh-key', keyFileVariable: 'MY_KEY_FILE', usernameVariable: 'SSH_USER')]) {
                        
                        // SOLUCIÓN SEGURIDAD: Usamos comillas simples para que Groovy no interpocle la llave
                        // y usamos las variables de entorno ($MY_KEY_FILE) directamente en bash.
                        
                        sh '''
                            # 1. Asegurar permisos de la llave temporal (evita "WARNING: UNPROTECTED PRIVATE KEY FILE!")
                            chmod 600 "$MY_KEY_FILE"

                            # 2. Smart Naming
                            echo ">> Calculando nombre disponible..."
                            export SSH_KEY_FILE="$MY_KEY_FILE"
                            
                            chmod +x scripts/get_db_name.sh
                            ./scripts/get_db_name.sh > final_db_name.txt
                        '''
                        
                        env.NEW_DB_NAME = readFile('final_db_name.txt').trim()
                        env.FINAL_URL = "https://${env.NEW_DB_NAME}.odooecuador.online/web/login"

                        // 3. Transferencia y Restauración
                        echo ">> Enviando backup..."
                        
                        sh '''
                            # Transferencia con SCP (-i para la llave, -4 para IPv4)
                            # Usamos timeout de 30s para no esperar eternamente si hay bloqueo
                            scp -4 -i "$MY_KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=30 "$LOCAL_BACKUP_FILE" ubuntu@$TARGET_IP:/tmp/
                            scp -4 -i "$MY_KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=30 scripts/restore_db.sh ubuntu@$TARGET_IP:/tmp/
                            
                            echo ">> Ejecutando restauración remota en $NEW_DB_NAME..."
                            ssh -4 -i "$MY_KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=30 ubuntu@$TARGET_IP \
                                "export NEW_DB_NAME='$NEW_DB_NAME' && \
                                 export DB_OWNER='$DB_OWNER' && \
                                 export LOCAL_BACKUP_FILE='$LOCAL_BACKUP_FILE' && \
                                 chmod +x /tmp/restore_db.sh && /tmp/restore_db.sh"
                        '''
                    }
                }
            }
        }
        
        stage('Notificar') {
            steps {
                script {
                    echo "--- Notificando Éxito ---"
                    def chat_msg = """{"text": "*Restauración Exitosa*\\n*Base:* ${env.NEW_DB_NAME}\\n*URL:* ${env.FINAL_URL}"}"""
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