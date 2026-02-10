pipeline {
    agent any 

    parameters {
        string(name: 'ODOO_URL', defaultValue: '', description: 'URL de producción')
        choice(name: 'BACKUP_TYPE', choices: ['dump', 'zip'], description: 'Formato')
        choice(name: 'VERSION', choices: ['v15', 'v19'], description: 'Versión Destino')
        string(name: 'EXECUTED_BY', defaultValue: 'Sistema', description: 'Triggered by')
        string(name: 'ODOO_ID', defaultValue: '', description: 'ID Odoo')
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
        ODOO_LOCAL_URL = "https://faceable-maddison-unharangued.ngrok-free.dev" 
        ODOO_LOCAL_DB = "prueba"
    }

    stages {
        stage('1. Iniciar VPN') {
            steps {
                script {
                    sh "docker rm -f vpn-sidecar || true"
                    configFileProvider([configFile(fileId: 'vpn-pasante-file', targetLocation: 'pasante.ovpn')]) {
                        sh "docker run -d --name vpn-sidecar --cap-add=NET_ADMIN --device /dev/net/tun ubuntu:22.04 sleep infinity"
                        sh "docker exec vpn-sidecar sh -c 'apt-get update && apt-get install -y openvpn iproute2'"
                        sh "docker cp pasante.ovpn vpn-sidecar:/etc/openvpn/client.conf"
                        sh "docker exec -d vpn-sidecar openvpn --config /etc/openvpn/client.conf --daemon"
                    }
                    sleep 15
                }
            }
        }

        stage('2. Descargar Backup') {
            steps {
                script {
                    def selected_cred_id = 'vault-integralis360.website'
                    if (params.ODOO_URL.contains('.sdb-integralis360.com')) selected_cred_id = 'vault-sdb-integralis360.com'
                    else if (params.ODOO_URL.contains('.dic-integralis360.com')) selected_cred_id = 'dic-integralis360.com'
                    else if (params.ODOO_URL.contains('lns')) selected_cred_id = 'dic-lns'
                    else if (params.ODOO_URL.contains('.ee19')) selected_cred_id = 'vault-ee19-integralis360.website'
                    
                    withCredentials([string(credentialsId: selected_cred_id, variable: 'TEMP_PWD')]) {
                        sh """
                            docker rm -f vpn-worker || true
                            docker run -d --name vpn-worker \\
                                -e MASTER_PWD="\${TEMP_PWD}" \\
                                -e ODOO_URL="${params.ODOO_URL}" \\
                                -e BACKUP_TYPE="${params.BACKUP_TYPE}" \\
                                --network container:vpn-sidecar \\
                                ubuntu:22.04 sleep infinity
                            
                            docker exec vpn-worker mkdir -p /workspace
                            
                            # Copiamos los scripts desde la carpeta que bajó Git
                            docker cp scripts/extract.py vpn-worker:/workspace/
                            docker cp scripts/download_backup.sh vpn-worker:/workspace/
                            
                            docker exec vpn-worker chmod +x /workspace/download_backup.sh
                            docker exec vpn-worker /workspace/download_backup.sh
                            
                            docker cp vpn-worker:/workspace/filename.txt .
                            docker cp vpn-worker:/workspace/dbname.txt .
                            FILENAME=\$(cat filename.txt)
                            docker cp vpn-worker:/workspace/\$FILENAME .
                            
                            docker rm -f vpn-worker
                        """
                    }
                }
            }
        }

        stage('3. Restaurar Backup') {
            steps {
                script {
                    env.LOCAL_BACKUP_FILE = readFile('filename.txt').trim()
                    env.DB_NAME = readFile('dbname.txt').trim()
                    
                    def cleanName = env.DB_NAME.replace("-ee15", "").replace("-ee", "")
                    env.NEW_DB_NAME = "${cleanName}-" + sh(returnStdout: true, script: 'date +%Y%m%d').trim() + "-" + ((params.VERSION == 'v15') ? 'ee15n2' : 'ee19')
                    
                    if (params.VERSION == 'v15') {
                        env.TARGET_IP = env.IP_TEST_V15
                        env.SELECTED_PASS = env.SSH_PASS_V15
                        env.DB_OWNER = 'odoo15'
                    } else {
                        env.TARGET_IP = env.IP_TEST_V19
                        env.SELECTED_PASS = env.SSH_PASS_V19
                        env.DB_OWNER = 'odoo19'
                    }
                    env.FINAL_URL = "https://${env.NEW_DB_NAME}.odooecuador.online/web/login"

                    sh """
                        docker rm -f vpn-deploy || true
                        docker run -d --name vpn-deploy \\
                            -e MY_SSH_PASS="${env.SELECTED_PASS}" \\
                            -e LOCAL_BACKUP_FILE="${env.LOCAL_BACKUP_FILE}" \\
                            -e NEW_DB_NAME="${env.NEW_DB_NAME}" \\
                            -e TARGET_IP="${env.TARGET_IP}" \\
                            -e DB_OWNER="${env.DB_OWNER}" \\
                            --network container:vpn-sidecar \\
                            ubuntu:22.04 sleep infinity

                        docker exec vpn-deploy mkdir -p /workspace
                        
                        # Copiamos el script de restauración y el backup
                        docker cp scripts/restore_db.sh vpn-deploy:/workspace/
                        docker cp ${env.LOCAL_BACKUP_FILE} vpn-deploy:/workspace/
                        
                        docker exec vpn-deploy chmod +x /workspace/restore_db.sh
                        docker exec vpn-deploy /workspace/restore_db.sh
                        
                        docker rm -f vpn-deploy
                    """
                }
            }
        }
        
        stage('Notificar') {
            steps {
                script {
                    echo "--- Notificando Éxito ---"
                    def chat_msg = """{"text": "*Respaldo Completado*\\n*Base:* ${env.NEW_DB_NAME}\\n*URL:* ${env.FINAL_URL}"}"""
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
                    sh "curl -X POST -H 'Content-Type: application/json' -d '${odoo_payload}' '${env.ODOO_LOCAL_URL}/jsonrpc' || true"
                }
            }
        }
    }

    post {
        always {
            script {
                echo "--- Limpieza Final ---"
                sh "docker rm -f vpn-sidecar vpn-worker vpn-deploy || true"
                cleanWs()
            }
        }
        failure {
            script {
                def fail_msg = """{"text": "Fallo en Pipeline*\\nRevisar Jenkins."}"""
                sh "curl -X POST -H 'Content-Type: application/json; charset=UTF-8' -d '${fail_msg}' '${env.GOOGLE_CHAT_WEBHOOK}' || true"
            }
        }
    }
}