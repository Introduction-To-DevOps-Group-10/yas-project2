pipeline {
    agent any

    environment {
        // Cập nhật lại username Docker Hub của bạn
        DOCKERHUB_USERNAME = 'tunas106' 
        // ID Credentials bạn đã tạo ở Giai đoạn 2
        DOCKERHUB_CREDENTIALS = 'dockerhub-credentials' 
    }

    stages {
        stage('Checkout') {
            steps {
                // Trong Multibranch Pipeline, 'checkout scm' tự động checkout đúng branch đang trigger
                checkout scm 
            }
        }

        stage('Lấy Commit ID') {
            steps {
                script {
                    // Biến env.GIT_COMMIT luôn có sẵn trong Multibranch. 
                    // Ta lấy 7 ký tự đầu để làm tag cho ngắn gọn và chuẩn xác.
                    env.SHORT_COMMIT = env.GIT_COMMIT.take(7)
                    echo "Mã Commit đang build: ${env.SHORT_COMMIT}"
                }
            }
        }

        stage('Build & Push Mẫu (Tax Service)') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${DOCKERHUB_CREDENTIALS}",
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh 'echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin'
                }

                script {
                    def svc = 'tax'
                    
                    echo "========== Building: ${svc} =========="
                    // Build file .jar
                    sh "mvn clean package -pl ${svc} -am -DskipTests"

                    // Build Docker image với tag là SHORT_COMMIT
                    sh """
                        docker build \
                            -t ${DOCKERHUB_USERNAME}/yas-${svc}:${env.SHORT_COMMIT} \
                            ./${svc}
                    """

                    // Push image lên Docker Hub
                    sh "docker push ${DOCKERHUB_USERNAME}/yas-${svc}:${env.SHORT_COMMIT}"

                    // Dọn dẹp local image
                    sh "docker rmi ${DOCKERHUB_USERNAME}/yas-${svc}:${env.SHORT_COMMIT} || true"
                    echo "========== Done: ${svc} =========="
                }
            }
        }
    }

    post {
        always {
            sh 'docker logout || true'
        }
        success {
            echo "✅ Build thành công! Image tag: ${env.SHORT_COMMIT}"
        }
    }
}
