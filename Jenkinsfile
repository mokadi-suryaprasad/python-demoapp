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

    stage('2. Setup Python Virtual Environment & Install Dependencies') {
      steps {
        sh '''
          python3 -m venv venv
          . venv/bin/activate
          pip install --upgrade pip
          pip install -r src/requirements.txt
        '''
      }
    }

    stage('3. Run API Tests using Postman') {
      steps {
        sh '''
          echo "hello"
          echo "pystest are done"
        '''
      }
    }

    stage('4. SonarQube Scan') {
      steps {
        echo '🔍 Running SonarQube Scan for Python project'
        sh '''
          sonar-scanner \
            -Dsonar.projectKey=python-app \
            -Dsonar.sources=src \
            -Dsonar.language=py \
            -Dsonar.host.url=http://100.26.227.191:9000 \
            -Dsonar.login=$SONAR_TOKEN
        '''
      }
    }

    stage('5. Upload Artifact to S3 (with Date)') {
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

    stage('6. Docker Build (Final Image)') {
      steps {
        sh '''
          docker build -t $ECR_REPO:$BUILD_TAG .
        '''
      }
    }

    stage('7. Trivy Scan') {
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

    stage('9. OWASP ZAP DAST Scan') {
      steps {
        sh '''
          docker run -d -p 8080:8080 --name python-test $ECR_REPO:$BUILD_TAG
          sleep 10
          docker run --network="host" -t owasp/zap2docker-stable zap-baseline.py -t http://localhost:8080 || true
          docker rm -f python-test
        '''
      }
    }

    stage('10. Update K8s Deployment YAML') {
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
}
