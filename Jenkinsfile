pipeline {
    agent any

    environment {
        // NHỚ THAY ĐỔI 2 BIẾN NÀY THÀNH THÔNG TIN THẬT CỦA BẠN
        DOCKERHUB_USERNAME = 'tunas106' 
        DOCKERHUB_CREDENTIALS = 'dockerhub-credentials' 
    }

    stages {
        stage('Checkout') {
            steps {
                // Tự động checkout đúng nhánh đang có commit mới
                checkout scm 
            }
        }

        stage('Lấy Commit ID') {
            steps {
                script {
                    // Lấy 7 ký tự đầu của mã Commit để làm Tag cho Docker Image
                    env.SHORT_COMMIT = env.GIT_COMMIT.take(7)
                    echo "Mã Commit (Tag) cho lần build này là: ${env.SHORT_COMMIT}"
                }
            }
        }

        stage('Build & Push All Services') {
            steps {
                // Đăng nhập Docker Hub an toàn qua Credentials
                withCredentials([usernamePassword(
                    credentialsId: "${DOCKERHUB_CREDENTIALS}",
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh 'echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin'
                }

                // Vòng lặp build 10 services
                script {
                    def services = [
                        'media', 'product', 'cart', 'order', 'rating',
                        'customer', 'location', 'inventory', 'tax', 'search'
                    ]

                    for (svc in services) {
                        echo "=========================================================="
                        echo "========== ĐANG XỬ LÝ SERVICE: ${svc.toUpperCase()} =========="
                        echo "=========================================================="

                        // 1. Build file JAR bằng Maven (bỏ qua Test để tăng tốc độ)
                        sh "mvn clean package -pl ${svc} -am -DskipTests"

                        // 2. Build Docker Image với tag là mã Commit
                        sh """
                            docker build \
                                -t ${DOCKERHUB_USERNAME}/yas-${svc}:${env.SHORT_COMMIT} \
                                ./${svc}
                        """

                        // 3. Push Image lên Docker Hub
                        sh "docker push ${DOCKERHUB_USERNAME}/yas-${svc}:${env.SHORT_COMMIT}"

                        // 4. Xóa Image ở local để giải phóng dung lượng cho Jenkins server
                        sh "docker rmi ${DOCKERHUB_USERNAME}/yas-${svc}:${env.SHORT_COMMIT} || true"
                        
                        echo "========== HOÀN TẤT SERVICE: ${svc.toUpperCase()} ==========\n"
                    }
                }
            }
        }
    }

    post {
        always {
            // Luôn logout Docker Hub khi kết thúc để đảm bảo bảo mật
            sh 'docker logout || true'
        }
        success {
            echo "✅ TUYỆT VỜI! Tất cả 10 services đã được build và push thành công lên Docker Hub với Tag: ${env.SHORT_COMMIT}"
        }
        failure {
            echo "❌ CÓ LỖI XẢY RA! Quá trình pipeline đã thất bại. Vui lòng kiểm tra lại log của các Stage ở trên để tìm nguyên nhân."
        }
    }
}
