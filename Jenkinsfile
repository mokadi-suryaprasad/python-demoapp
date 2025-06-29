pipeline {
  agent any

  environment {
    AWS_REGION = "ap-south-1"
    ECR_REPO = "development/namespace"
    SONAR_TOKEN = credentials('SONAR_TOKEN')
    BUILD_TAG = "${BUILD_NUMBER}"
  }

  stages {
    stage('1. Checkout Code') {
      steps {
        git credentialsId: 'github-creds', url: 'https://github.com/mokadi-suryaprasad/python-demoapp.git', branch: 'master'
      }
    }

    stage('2. Setup Python & Install Dependencies') {
      steps {
        sh '''
          python3.13 -m venv venv
          . venv/bin/activate
          pip install --upgrade pip
          pip install -r src/requirements.txt
        '''
      }
    }

    stage('3. Run Unit Tests (Skipped)') {
      steps {
        echo '🟡 Skipping unit tests for now.'
      }
    }

    stage('4. Code Analysis (SonarQube)') {
      steps {
        echo '🔍 Running SonarQube Scan for Python project'
        withSonarQubeEnv('sonar') {
          sh '''
            sonar-scanner \
              -Dsonar.login=$SONAR_TOKEN
          '''
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
            zip -r python-artifact.zip src
            DATE=$(date +%F)
            aws s3 cp python-artifact.zip s3://pythonbuildfiles/python-service/$DATE/build-$BUILD_TAG.zip
          '''
        }
      }
    }

    stage('6. Docker Build') {
      steps {
        sh '''
          docker build -t $ECR_REPO:$BUILD_TAG .
        '''
      }
    }

    stage('7. Trivy Image Scan') {
      steps {
        sh '''
          trivy image $ECR_REPO:$BUILD_TAG --exit-code 1 --severity CRITICAL,HIGH || true
        '''
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
            ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
            aws ecr get-login-password --region $AWS_REGION | \
              docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

            docker tag $ECR_REPO:$BUILD_TAG $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$BUILD_TAG
            docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$BUILD_TAG
          '''
        }
      }
    }

    stage('9. Run OWASP ZAP Full Scan') {
      steps {
        sh '''
          . venv/bin/activate
          nohup python src/run.py > server.log 2>&1 &
          sleep 15
          curl -I http://localhost:5000 || echo "App not reachable"
          docker run --rm --network="host" -v $WORKSPACE:/zap/wrk ghcr.io/zaproxy/zaproxy:stable \
            zap-full-scan.py -t http://localhost:5000 -a -r zap-report.html -J zap-report.json || true
        '''
      }
    }
    stage('Upload ZAP DAST Report') {
      steps {
        publishHTML(target: [
          reportDir: '.', 
          reportFiles: 'zap-report.html', 
          reportName: 'OWASP ZAP DAST Report'
        ])
        archiveArtifacts artifacts: 'zap-report.json', fingerprint: true
      }
    }

    stage('10. Update K8s Deployment YAML & Git Push') {
      steps {
        script {
          def ecr_url = "023703779855.dkr.ecr.${env.AWS_REGION}.amazonaws.com/${env.ECR_REPO}"
          sh """
            sed -i "s|image: .*|image: ${ecr_url}:${BUILD_TAG}|" deploy/kubernetes/deployment.yaml

            git config --global user.email "mspr9773@gmail.com"
            git config --global user.name "M Surya Prasad"
            git add deploy/kubernetes/deployment.yaml
            git commit -m "Update image tag to ${BUILD_TAG}"
            git push origin master
          """
        }
      }
    }
  }

  post {
    always {
      echo '🧹 Cleaning workspace...'
      cleanWs()
    }
  }
}
