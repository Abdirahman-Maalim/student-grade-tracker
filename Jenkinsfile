// Jenkinsfile — CI for Student Grade Tracker
//
// Jenkins (GCE VM) -> Artifact Registry -> Git commit -> ArgoCD on GKE
//
// Every push to main: Checkout -> Install -> Test -> Docker Build -> Push
//                     -> Update k8s-gke/ (GitOps commit) -> Archive
//
// Jenkins never talks to the cluster. It pushes images and commits the new tag
// to k8s-gke/kustomization.yaml; ArgoCD watches that overlay and deploys it.
//
// Prerequisites (terraform/jenkins + ansible/jenkins.yml):
//   - node, npm, git, docker on the VM; jenkins user in the docker group
//   - VM service account with artifactregistry.writer on the repository;
//     docker authenticates through the gcloud credential helper (no password)
//   - Jenkins credential github-creds: Username/Password =
//     GitHub user + fine-grained PAT (this repo only, Contents: read/write)

pipeline {
    agent any

    parameters {
        booleanParam(name: 'PUBLISH', defaultValue: true,
            description: 'Build and push images to Artifact Registry and commit the new tag to k8s-gke/ (untick for a test-only run)')
    }

    environment {
        REGISTRY        = 'us-central1-docker.pkg.dev/project-aa2f0371-cdbf-4df1-8c0/grade-tracker'
        BACKEND_IMAGE   = "${REGISTRY}/backend"
        FRONTEND_IMAGE  = "${REGISTRY}/frontend"
        OVERLAY         = 'k8s-gke/kustomization.yaml'
        GIT_BRANCH_NAME = 'main'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 30, unit: 'MINUTES')
    }

    triggers {
        // GitHub webhook -> http://<jenkins>:8080/github-webhook/ (replaces polling)
        githubPush()
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
                    env.SKIP_BUILD    = lastMsg.contains('[skip ci]') ? 'true' : 'false'
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
                    expression { params.PUBLISH }
                }
            }
            steps {
                sh '''
                    docker build -t ${BACKEND_IMAGE}:${IMAGE_TAG}  backend
                    docker build -t ${FRONTEND_IMAGE}:${IMAGE_TAG} frontend
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
                // No stored password: docker uses the gcloud credential helper,
                // which signs in as the VM's service account.
                sh '''
                    docker push ${BACKEND_IMAGE}:${IMAGE_TAG}
                    docker push ${FRONTEND_IMAGE}:${IMAGE_TAG}
                '''
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
                        # Both images share one tag, so every newTag line in the overlay gets it.
                        sed -i -E "s#^( *newTag:).*#\\1 ${IMAGE_TAG}#" ${OVERLAY}
                        git diff --stat

                        git config user.name  "jenkins-ci"
                        git config user.email "jenkins-ci@users.noreply.github.com"
                        git add ${OVERLAY}
                        git commit -m "ci: deploy ${IMAGE_TAG} to GKE [skip ci]"

                        # main may have moved while we built; replay our one commit on top.
                        git fetch origin ${GIT_BRANCH_NAME}
                        git rebase origin/${GIT_BRANCH_NAME}

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
                    echo "commit=${SHORT_SHA}"                     >  dist/build-info.txt
                    echo "build=${BUILD_NUMBER}"                   >> dist/build-info.txt
                    echo "image_tag=${IMAGE_TAG}"                  >> dist/build-info.txt
                    echo "backend=${BACKEND_IMAGE}:${IMAGE_TAG}"   >> dist/build-info.txt
                    echo "frontend=${FRONTEND_IMAGE}:${IMAGE_TAG}" >> dist/build-info.txt
                    tar -czf dist/grade-tracker-${IMAGE_TAG}.tar.gz \
                        frontend backend/src backend/package.json k8s k8s-gke \
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
            // Images live in Artifact Registry; keep the VM's 30 GB disk clean.
            sh '''
                docker image rm ${BACKEND_IMAGE}:${IMAGE_TAG} ${FRONTEND_IMAGE}:${IMAGE_TAG} >/dev/null 2>&1 || true
                docker image prune -f >/dev/null 2>&1 || true
            '''
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
Image tag    : ${env.IMAGE_TAG}
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
}
