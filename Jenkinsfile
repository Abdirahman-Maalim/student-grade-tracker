// Jenkinsfile — CI for Student Grade Tracker

pipeline {
    agent any

    parameters {
        booleanParam(name: 'BUILD_IMAGES', defaultValue: false,
            description: 'Build backend + frontend Docker images (needs docker on the agent)')
        booleanParam(name: 'PUBLISH', defaultValue: false,
            description: 'Push images to Docker Hub and commit the new tags to k8s/ so ArgoCD deploys them (implies BUILD_IMAGES)')
    }

    environment {
        REGISTRY_USER   = 'abdirahmankhalif'
        BACKEND_IMAGE   = "${REGISTRY_USER}/grade-tracker-backend"
        FRONTEND_IMAGE  = "${REGISTRY_USER}/grade-tracker-frontend"
        GIT_BRANCH_NAME = 'main'
    }

    options {
        
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 30, unit: 'MINUTES')
    }

    triggers {
        pollSCM('H/2 * * * *')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.SHORT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    env.IMAGE_TAG = "1.0.${env.BUILD_NUMBER}-${env.SHORT_SHA}"
                    // Stop the loop: the tag-bump commit made by this pipeline must not rebuild itself.
                    def lastMsg = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
                    env.SKIP_BUILD = lastMsg.contains('[skip ci]') ? 'true' : 'false'
                                        env.COMMIT_MSG    = lastMsg
                    env.COMMIT_AUTHOR = sh(script: 'git log -1 --pretty=%an', returnStdout: true).trim()
                }
                echo "Commit ${env.SHORT_SHA} -> image tag ${env.IMAGE_TAG}"
            }
        }

        stage('Install') {
            when { environment name: 'SKIP_BUILD', value: 'false' }
            steps {
                sh '''
                    node --version
                    npm --version
                    cd backend
                    npm install --no-audit --no-fund
                '''
            }
        }

        stage('Test') {
            when { environment name: 'SKIP_BUILD', value: 'false' }
            steps {
                sh 'npm test'
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'reports/junit.xml'
                }
            }
        }

        stage('Docker Build') {
            when {
                allOf {
                    environment name: 'SKIP_BUILD', value: 'false'
                    anyOf { expression { params.BUILD_IMAGES }; expression { params.PUBLISH } }
                }
            }
            steps {
                sh '''
                    docker build -t ${BACKEND_IMAGE}:${IMAGE_TAG}  backend
                    docker build -t ${FRONTEND_IMAGE}:${IMAGE_TAG} frontend
                    docker image ls | grep grade-tracker
                '''
            }
        }

        stage('Push Images') {
            when {
                allOf {
                    environment name: 'SKIP_BUILD', value: 'false'
                    expression { params.PUBLISH }
                }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DH_USER', passwordVariable: 'DH_TOKEN')]) {
                    sh '''
                        echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin
                        docker push ${BACKEND_IMAGE}:${IMAGE_TAG}
                        docker push ${FRONTEND_IMAGE}:${IMAGE_TAG}
                        docker logout
                    '''
                }
            }
        }

        stage('Update Manifests (GitOps)') {
            when {
                allOf {
                    environment name: 'SKIP_BUILD', value: 'false'
                    expression { params.PUBLISH }
                }
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'github-creds',
                        usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
                    sh '''
                        sed -i -E "s#(image: ${BACKEND_IMAGE}):.*#\\1:${IMAGE_TAG}#"  k8s/backend-deployment.yaml
                        sed -i -E "s#(image: ${FRONTEND_IMAGE}):.*#\\1:${IMAGE_TAG}#" k8s/frontend-deployment.yaml
                        git diff --stat

                        git config user.name  "jenkins-ci"
                        git config user.email "jenkins-ci@users.noreply.github.com"
                        git add k8s/backend-deployment.yaml k8s/frontend-deployment.yaml
                        git commit -m "ci: deploy images ${IMAGE_TAG} [skip ci]"

                        REPO_URL=$(git config --get remote.origin.url | sed -E 's#https://##')
                        git push "https://${GH_USER}:${GH_TOKEN}@${REPO_URL}" HEAD:${GIT_BRANCH_NAME}
                    '''
                }
            }
        }

        stage('Archive') {
            when { environment name: 'SKIP_BUILD', value: 'false' }
            steps {
                sh '''
                    rm -rf dist && mkdir -p dist
                    echo "commit=${SHORT_SHA}"    >  dist/build-info.txt
                    echo "build=${BUILD_NUMBER}"  >> dist/build-info.txt
                    echo "image_tag=${IMAGE_TAG}" >> dist/build-info.txt
                    tar -czf dist/grade-tracker-${IMAGE_TAG}.tar.gz \
                        frontend backend/src backend/package.json k8s \
                        $(test -d argocd && echo argocd)
                '''
                archiveArtifacts artifacts: 'dist/**, reports/**', fingerprint: true
            }
        }
    }

        post {
        success { echo "CI passed for ${env.SHORT_SHA}" }
        failure { echo "CI failed for ${env.SHORT_SHA} - see the red stage above" }
        always {
            sh 'docker image prune -f >/dev/null 2>&1 || true'
            script {
                if (!env.NOTIFY_EMAIL) {
                    echo 'NOTIFY_EMAIL not set in Jenkins - skipping email'
                    return
                }
                def result = currentBuild.currentResult
                try {
                    mail(
                        to: env.NOTIFY_EMAIL,
                        subject: "[${result}] ${env.JOB_NAME} #${env.BUILD_NUMBER} - ${env.SHORT_SHA}",
                        body: """Build result : ${result}
Job          : ${env.JOB_NAME} #${env.BUILD_NUMBER}
Commit       : ${env.SHORT_SHA} by ${env.COMMIT_AUTHOR}
Message      : ${env.COMMIT_MSG}
Duration     : ${currentBuild.durationString}

Console : ${env.BUILD_URL}console
Tests   : ${env.BUILD_URL}testReport/
"""
                    )
                } catch (err) {
                    echo "Email not sent: ${err}"
                }
            }
        }
    }