pipeline {
  agent any

  environment {
    AWS_REGION = "ap-south-1"
    ECR_REPO = "development/namespace"
    BUILD_TAG = "${BUILD_NUMBER}"
  }

  stages {
    stage('1. Checkout Code') {
      steps {
        git credentialsId: 'github-creds', url: 'https://github.com/mokadi-suryaprasad/python-demoapp.git', branch: 'main'
      }
    }

    stage('2. Setup Python Virtual Environment & Install Dependencies') {
      steps {
        sh '''
          set -e
          python3.12 -m venv venv
          . venv/bin/activate
          pip install --upgrade pip
          pip install -r src/requirements.txt
        '''
      }
    }

    stage('3. Run Unit Tests') {
      steps {
        sh 'echo "No Test cases running"'
      }
    }

    stage('4. SonarQube Scan') {
      steps {
        echo '🔍 Running SonarQube Scan for Python project'
        withSonarQubeEnv('sonar') {
          withCredentials([string(credentialsId: 'SONAR_TOKEN', variable: 'SONAR_TOKEN')]) {
            sh '''
              export PATH=$PATH:/opt/sonar-scanner/bin
              sonar-scanner \
                -Dsonar.projectKey=python-app \
                -Dsonar.sources=src \
                -Dsonar.python.version=3.12 \
                -Dsonar.host.url=http://43.205.195.108:9000 \
                -Dsonar.login=$SONAR_TOKEN
            '''
          }
        }
      }
    }

    stage('5. Upload Artifact to S3') {
      steps {
        withCredentials([[
          $class: 'AmazonWebServicesCredentialsBinding',
          accessKeyVariable: 'AWS_ACCESS_KEY_ID',
          secretKeyVariable: 'AWS_SECRET_ACCESS_KEY',
          credentialsId: 'aws-credentials'
        ]]) {
          sh '''
            set -e
            zip -r python-artifact.zip src
            DATE=$(date +%F)
            aws s3 cp python-artifact.zip s3://pythonbuildfiles/python-service/$DATE/build-$BUILD_TAG.zip
          '''
        }
      }
    }

    stage('6. Docker Build') {
      steps {
        sh 'docker build -t $ECR_REPO:$BUILD_TAG .'
      }
    }

    stage('7. Trivy Image Scan') {
      steps {
        sh 'trivy image $ECR_REPO:$BUILD_TAG --exit-code 0 --severity CRITICAL,HIGH || true'
      }
    }

    stage('8. Push to AWS ECR') {
      steps {
        withCredentials([[
          $class: 'AmazonWebServicesCredentialsBinding',
          accessKeyVariable: 'AWS_ACCESS_KEY_ID',
          secretKeyVariable: 'AWS_SECRET_ACCESS_KEY',
          credentialsId: 'aws-credentials'
        ]]) {
          sh '''
            set -e
            ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
            aws ecr get-login-password --region $AWS_REGION | \
              docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

            docker tag $ECR_REPO:$BUILD_TAG $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$BUILD_TAG
            docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$BUILD_TAG
          '''
        }
      }
    }

    stage('9. OWASP ZAP DAST Scan & Report') {
      steps {
          sh '''
            set -e

            # Start your app container
            docker run -d -p 8081:8080 --name python-zaptest $ECR_REPO:$BUILD_TAG

            # Wait for app to be ready (tune this as needed)
            sleep 20

            # Run OWASP ZAP baseline scan
            docker run --rm --network="host" -v $WORKSPACE:/zap/wrk -t owasp/zap2docker-weekly \
            zap-baseline.py \
           -t http://localhost:8080 \
           -r dast-report.html \
           -J dast-report.json || true

          # Stop and remove the app container
          docker rm -f python-zaptest
          '''

      }
    }

    stage('10. Update K8s Deployment YAML & Git Push') {
      steps {
        script {
          def ecr_url = "023703779855.dkr.ecr.${env.AWS_REGION}.amazonaws.com/${env.ECR_REPO}"
          sh """
            set -e
            sed -i "s|image: .*|image: ${ecr_url}:${BUILD_TAG}|" deploy/kubernetes/deployment.yaml

            git config --global user.email "mspr9773@gmail.com"
            git config --global user.name "M Surya Prasad"
            git add deploy/kubernetes/deployment.yaml
            git commit -m "Update image tag to ${BUILD_TAG}"
            git push origin main
          """
        }
      }
    }
  }

  post {
    always {
      echo '📋 Publishing OWASP ZAP DAST Report...'
      publishHTML(target: [
        reportDir: '.', 
        reportFiles: 'dast-report.html', 
        reportName: 'OWASP ZAP DAST Report'
      ])
      cleanWs()
    }
  }
}
