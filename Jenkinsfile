pipeline {
    agent any

    environment {
        // Cập nhật thông tin của bạn
        DOCKERHUB_USERNAME = 'tunas106' 
        DOCKERHUB_CREDENTIALS = 'dockerhub-credentials' 
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm 
            }
        }

        stage('Xác định Service thay đổi') {
            steps {
                script {
                    // Lấy 7 ký tự đầu của mã Commit
                    env.SHORT_COMMIT = env.GIT_COMMIT.take(7)
                    echo "Mã Commit (Tag) hiện tại: ${env.SHORT_COMMIT}"

                    // Danh sách toàn bộ 10 service của YAS
                    def allServices = [
                        'media', 'product', 'cart', 'order', 'rating',
                        'customer', 'location', 'inventory', 'tax', 'search'
                    ]
                    def changedServices = []

                    // Dùng git diff-tree để lấy danh sách các file bị thay đổi trong commit này
                    def changedFilesStr = sh(script: "git diff-tree --no-commit-id --name-only -r ${env.GIT_COMMIT} || true", returnStdout: true).trim()
                    def changedFiles = changedFilesStr ? changedFilesStr.split('\n') : []

                    // Trích xuất tên thư mục gốc của các file bị thay đổi
                    for (file in changedFiles) {
                        def topFolder = file.split('/')[0] // Lấy thư mục ngoài cùng
                        
                        // Nếu thư mục đó nằm trong danh sách service và chưa được add vào list
                        if (allServices.contains(topFolder) && !changedServices.contains(topFolder)) {
                            changedServices.add(topFolder)
                        }
                    }

                    // Chuyển mảng thành chuỗi để lưu vào biến môi trường
                    env.CHANGED_SERVICES = changedServices.join(',')

                    if (env.CHANGED_SERVICES == '') {
                        echo "⚠️ Không có thay đổi nào trong các thư mục code của service."
                    } else {
                        echo "🔥 Các service có thay đổi và sẽ được build: ${env.CHANGED_SERVICES}"
                    }
                }
            }
        }

        stage('Build & Push Changed Services') {
            // Stage này CHỈ CHẠY nếu có ít nhất 1 service thay đổi
            when {
                expression { return env.CHANGED_SERVICES != '' }
            }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${DOCKERHUB_CREDENTIALS}",
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh 'echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin'
                }

                script {
                    // Tách chuỗi thành mảng các service cần build
                    def servicesToBuild = env.CHANGED_SERVICES.split(',')

                    for (svc in servicesToBuild) {
                        echo "=========================================================="
                        echo "========== ĐANG XỬ LÝ SERVICE: ${svc.toUpperCase()} =========="
                        echo "=========================================================="

                        // Build bằng Maven
                        sh "mvn clean package -pl ${svc} -am -DskipTests"

                        // Build Docker Image
                        sh """
                            docker build \
                                -t ${DOCKERHUB_USERNAME}/yas-${svc}:${env.SHORT_COMMIT} \
                                ./${svc}
                        """

                        // Push lên Docker Hub
                        sh "docker push ${DOCKERHUB_USERNAME}/yas-${svc}:${env.SHORT_COMMIT}"

                        // Dọn dẹp Image local
                        sh "docker rmi ${DOCKERHUB_USERNAME}/yas-${svc}:${env.SHORT_COMMIT} || true"
                        
                        echo "========== HOÀN TẤT: ${svc.toUpperCase()} ==========\n"
                    }
                }
            }
        }
    }

    post {
        always {
            sh 'docker logout || true'
        }
        success {
            echo "✅ Pipeline hoàn tất thành công!"
            script {
                if (env.CHANGED_SERVICES != '') {
                    echo "Đã build và push các service: ${env.CHANGED_SERVICES} với Tag: ${env.SHORT_COMMIT}"
                } else {
                    echo "Không có thay đổi code nào liên quan đến các service. Bỏ qua bước build."
                }
            }
        }
        failure {
            echo "❌ Pipeline thất bại. Hãy kiểm tra lại log."
        }
    }
}
