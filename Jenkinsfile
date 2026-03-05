pipeline {
    agent any

    environment {
        DOCKER_REPO    = "thamaraikannans/tetris"
        AWS_REGION     = "us-east-1"
        CLUSTER_NAME   = "tetris-cluster"
        TF_DIR         = "terraform"         // path to terraform folder in your repo
        K8S_DIR        = "k8s"               // path to k8s manifests folder in your repo
    }

    stages {

        // ─────────────────────────────────────────
        // 1. CHECKOUT
        // ─────────────────────────────────────────
        stage('Checkout') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/Thamaraikannan00011/tetris-eks-cicd.git'
                sh 'ls -la'
            }
        }

        // ─────────────────────────────────────────
        // 2. BUILD DOCKER IMAGE
        // ─────────────────────────────────────────
        stage('Build') {
            steps {
                dir('tetris') {
                    sh 'docker build -t ${DOCKER_REPO}:${BUILD_NUMBER} .'
                    sh 'docker tag ${DOCKER_REPO}:${BUILD_NUMBER} ${DOCKER_REPO}:latest'
                }
            }
        }

        // ─────────────────────────────────────────
        // 3. PUSH TO DOCKER HUB
        // ─────────────────────────────────────────
        stage('Push') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin
                        docker push ${DOCKER_REPO}:${BUILD_NUMBER}
                        docker push ${DOCKER_REPO}:latest
                    '''
                }
            }
        }

        // ─────────────────────────────────────────
        // 4. TERRAFORM PLAN
        // ─────────────────────────────────────────
        stage('Terraform Plan') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-creds'
                ]]) {
                    dir("${TF_DIR}") {
                        sh '''
                            terraform init -input=false
                            terraform plan -input=false -out=tfplan
                        '''
                    }
                }
            }
        }

        // ─────────────────────────────────────────
        // 5. TERRAFORM APPLY (manual approval gate)
        // ─────────────────────────────────────────
        stage('Terraform Apply') {
            input {
                message "Apply Terraform changes to AWS?"
                ok "Yes, Apply"
            }
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-creds'
                ]]) {
                    dir("${TF_DIR}") {
                        sh 'terraform apply -input=false tfplan'
                    }
                }
            }
        }

        // ─────────────────────────────────────────
        // 6. UPDATE KUBECONFIG
        // ─────────────────────────────────────────
        stage('Configure kubectl') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-creds'
                ]]) {
                    sh '''
                        aws eks update-kubeconfig \
                            --region ${AWS_REGION} \
                            --name ${CLUSTER_NAME}
                    '''
                }
            }
        }

        // ─────────────────────────────────────────
        // 7. DEPLOY TO KUBERNETES
        // Updates the image tag in the deployment
        // then applies all manifests in k8s/
        // ─────────────────────────────────────────
        stage('Deploy') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-creds'
                ]]) {
                    dir("${K8S_DIR}") {
                        sh '''
                            # Swap in the exact build number so every deploy is traceable
                            sed -i "s|image: ${DOCKER_REPO}:.*|image: ${DOCKER_REPO}:${BUILD_NUMBER}|g" deployment.yaml

                            kubectl apply -f .

                            # Wait for rollout to finish (timeout 5 min)
                            kubectl rollout status deployment/tetris --timeout=300s
                        '''
                    }
                }
            }
        }

        // ─────────────────────────────────────────
        // 8. SMOKE TEST
        // ─────────────────────────────────────────
        stage('Smoke Test') {
            steps {
                sh '''
                    ALB=$(kubectl get svc tetris-service \
                            -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || \
                          terraform -chdir=${TF_DIR} output -raw alb_dns_name)

                    echo "Testing: http://${ALB}"

                    # Retry for up to 60s (ALB target registration delay)
                    for i in $(seq 1 12); do
                        STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://${ALB}/health || true)
                        echo "Attempt $i: HTTP $STATUS"
                        if [ "$STATUS" = "200" ]; then
                            echo "Smoke test passed!"
                            exit 0
                        fi
                        sleep 5
                    done

                    echo "Smoke test failed after 60s"
                    exit 1
                '''
            }
        }
    }

    // ─────────────────────────────────────────
    // POST ACTIONS
    // ─────────────────────────────────────────
    post {
        success {
            echo """
            ✅ Pipeline succeeded!
            Image : ${DOCKER_REPO}:${BUILD_NUMBER}
            Cluster: ${CLUSTER_NAME}
            """
        }
        failure {
            echo "❌ Pipeline failed. Check logs above."
        }
        always {
            // Clean up local docker images to save disk space
            sh '''
                docker rmi ${DOCKER_REPO}:${BUILD_NUMBER} || true
                docker rmi ${DOCKER_REPO}:latest || true
            '''
        }
    }
}
