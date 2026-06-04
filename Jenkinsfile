pipeline {
    agent any
    parameters {
        string(name: 'TESTER', description: '测试人员名称 (必填)')
        choice(name: 'INFRA', choices: ['vllm', 'sglang'], description: '推理框架')
        choice(name: 'PD', choices: ['agg', 'disagg'], description: 'PD分离模式,agg 表示非 PD 分离, disagg 表示 PD 分离')
        string(name: 'CHIP', defaultValue: 'nvidia-h100', description: '芯片平台名称')
        string(name: 'MODEL', defaultValue: 'kimi-k2.5', description: '模型名称')
        string(name: 'BASE_URL', defaultValue: 'http://10.201.149.10:8080/v1', description: 'API 地址')
        password(name: 'API_KEY', defaultValue: '', description: 'API Key (必填)')
        text(name: 'RECIPIENTS', defaultValue: 'liwt@zetyun.com', description: '邮件接收者（逗号分隔）')
        string(name: 'WORK_DIR', defaultValue: '/dingofs/data1/userdata/liwt/maas-image/IFBench', description: '远程工作目录')
    }
    environment {
        SSH_CREDENTIALS = 'HOST_SSH_KEY'
        REMOTE_HOST = '10.201.132.50'
        REMOTE_USER = 'root'
    }

    stages {
        stage('环境检查') {
            steps {
                sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                    sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << 'ENDSSH'
set -e
cd ${params.WORK_DIR}
echo "工作目录: \$(pwd)"
ls -la

echo "=== 设置权限 ==="
chmod -R 755 ./*
if [ ! -d "${params.WORK_DIR}/.venv" ]; then
    export https_proxy=http://100.64.1.68:1080
    export http_proxy=http://100.64.1.68:1080
    echo "创建虚拟环境..."
    cd ${params.WORK_DIR}
    uv sync --frozen
    unset https_proxy
    unset http_proxy
fi

cd ${params.WORK_DIR}
source .venv/bin/activate
echo "=== 激活虚拟环境完成 ==="
#export https_proxy=http://100.64.1.68:1080
#export http_proxy=http://100.64.1.68:1080
#uv pip install .
#uv pip install -r requirements.txt
#unset https_proxy
#unset http_proxy
#echo "=== 安装依赖完成 ==="
ENDSSH
"""
                }
            }
        }

        stage('运行IFBench测试') {
            steps {
                script {
                    if (!params.API_KEY || params.API_KEY.trim() == '') {
                        error("API_KEY 参数不能为空，请输入 API Key 后重新构建")
                    }
                    def safeModelName = params.MODEL.contains('/') ? params.MODEL.tokenize('/').last() : params.MODEL
                    env.SAFE_MODEL_NAME = safeModelName
                    sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                        catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                            sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << ENDSSH
set -e
cd ${params.WORK_DIR}
echo "=== 参数信息 ==="
echo "BASE_URL: ${params.BASE_URL}"
echo "MODEL: ${params.MODEL}"
echo "CHIP: ${params.CHIP}"
echo "BUILD_NUMBER: ${BUILD_NUMBER}"
echo "=== 创建测试输出目录 ==="
mkdir -p output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${SAFE_MODEL_NAME}
chmod +x ifbench_test.sh
echo "=== 执行测试脚本 ==="
./ifbench_test.sh "${params.BASE_URL}" "${params.API_KEY}" "${params.MODEL}" "${params.CHIP}" > output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${SAFE_MODEL_NAME}/ifb_results_build${BUILD_NUMBER}.log 2>&1
echo "=== 测试脚本执行结束 ==="
ENDSSH
"""
                        }
                    }
                }
            }
        }

        stage('拉取测试结果') {
            steps {
                sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                    catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                        script {
                            def targetDir = "output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${SAFE_MODEL_NAME}"
                            env.RESULT_DIR = targetDir
                            echo "拉取测试结果目录: ${targetDir}"
                            sh """
mkdir -p reports/${BUILD_NUMBER}
scp -o StrictHostKeyChecking=no \
    -r ${REMOTE_USER}@${REMOTE_HOST}:${params.WORK_DIR}/${targetDir} \
    ./reports/${BUILD_NUMBER}/
scp -o StrictHostKeyChecking=no \
    ${REMOTE_USER}@${REMOTE_HOST}:${params.WORK_DIR}/.env \
    ./reports/${BUILD_NUMBER}/ 2>/dev/null || true
echo "=== 拉取结果 ==="
find reports/${BUILD_NUMBER}/ -type f
echo "=== 转换日志为UTF-8 ==="
find reports/${BUILD_NUMBER}/ -name 'ifb_results_build${BUILD_NUMBER}.log' -exec sh -c 'iconv -f UTF-8 -t UTF-8 "\$1" > "\$1.utf8" 2>/dev/null && mv "\$1.utf8" "\$1" || rm -f "\$1.utf8"' _ {} \\;
"""
                        }
                    }
                }
            }
        }

        stage('发送邮件') {
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                    script {
                        def logContent = ""
                        def logFile = ""
                        if (env.RESULT_DIR) {
                            logFile = "reports/${BUILD_NUMBER}/${SAFE_MODEL_NAME}/ifb_results_build${BUILD_NUMBER}.log"
                            logContent = fileExists(logFile) ? readFile(logFile) : ""
                        }
                        def prompts = extractValue(logContent, /Loaded (\d+) prompts/, 1) ?: "N/A"
                        def errors = extractValue(logContent, /Errors: (\d+)/, 1) ?: "0"
                        def changed = extractValue(logContent, /Changed (\d+) responses/, 1) ?: "0"
                        def lines = logContent.split('\n')
                        def accuracyStrict = "N/A"
                        def accuracyLoose = "N/A"
                        for (int i = 0; i < lines.size(); i++) {
                            if (lines[i].contains('Generating eval_results_strict') && i + 1 < lines.size()) {
                                def match = lines[i + 1] =~ /Accuracy: ([\d.]+)/
                                if (match.find()) {
                                    accuracyStrict = match.group(1)
                                }
                            }
                            if (lines[i].contains('Generating eval_results_loose') && i + 1 < lines.size()) {
                                def match = lines[i + 1] =~ /Accuracy: ([\d.]+)/
                                if (match.find()) {
                                    accuracyLoose = match.group(1)
                                }
                            }
                        }
                        def api = extractValue(logContent, /API: (.+)/, 1) ?: params.BASE_URL
                        def topP = extractValue(logContent, /TOP_P: ([\d.]+)/, 1) ?: "N/A"
                        def topK = extractValue(logContent, /TOP_K: (\d+)/, 1) ?: "N/A"
                        def temperature = extractValue(logContent, /TEAMPERATURE: ([\d.]+)/, 1) ?: "N/A"
                        def maxTokens = extractValue(logContent, /MAX_TOKENS: (\d+)/, 1) ?: "N/A"
                        def workers = extractValue(logContent, /WORKERS: (\d+)/, 1) ?: "N/A"
                        def htmlTable = """
                        <table border="1" style="border-collapse: collapse; width: 100%;">
                            <tr style="background-color: #e3f2fd;"><th>Metric</th><th>Value</th></tr>
                            <tr><td>构建编号</td><td>${BUILD_NUMBER}</td></tr>
                            <tr><td>请求数</td><td>${prompts}</td></tr>
                            <tr><td>测试模型</td><td>${params.MODEL}</td></tr>
                            <tr><td>模型URL</td><td>${api}</td></tr>
                            <tr><td><b>测试参数</b></td><td>
                                <b>TOP_P: ${topP}</b><br>
                                <b>TOP_K: ${topK}</b><br>
                                <b>Temperature: ${temperature}</b><br>
                                <b>Max Tokens: ${maxTokens}</b><br>
                                <b>Workers: ${workers}</b>
                            </td></tr>
                            <tr><td>Errors</td><td>${errors}</td></tr>
                            <tr><td>Changed</td><td>${changed}</td></tr>
                            <tr style="background-color: #c8e6c9;"><td><b>Accuracy (Strict)</b></td><td><b>${accuracyStrict}</b></td></tr>
                            <tr style="background-color: #fff9c4;"><td><b>Accuracy (Loose)</b></td><td><b>${accuracyLoose}</b></td></tr>
                        </table>
                        """
                        def hasResult = fileExists(logFile) && logContent.length() > 0
                        def resultStatus = hasResult ? "成功" : "失败/无结果"
                        def resultDir = env.RESULT_DIR ?: 'N/A'
                        def emailBody = """
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 900px; margin: 0 auto; background-color: #fff; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .header { background-color: ${hasResult ? '#4CAF50' : '#f44336'}; color: white; padding: 20px; border-radius: 5px 5px 0 0; }
        .content { padding: 20px; }
        table { border-collapse: collapse; width: 100%; margin-top: 15px; }
        th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
        th { background-color: #f2f2f2; }
        .footer { margin-top: 20px; padding: 15px; background-color: #f9f9f9; border-radius: 0 0 5px 5px; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2 style="margin: 0;">IFBench 测试报告 - 构建 #${BUILD_NUMBER}</h2>
        </div>
        <div class="content">
            <h3>测试概要</h3>
            <table>
                <tr><th>构建编号</th><td>#${BUILD_NUMBER}</td></tr>
                <tr><th>测试人员</th><td>${params.TESTER}</td></tr>
                <tr><th>芯片平台</th><td>${params.CHIP}</td></tr>
                <tr><th>模型名称</th><td>${params.MODEL}</td></tr>
                <tr><th>推理框架</th><td>${params.INFRA}</td></tr>
                <tr><th>PD分离模式</th><td>${params.PD}</td></tr>
                <tr><th>执行时间</th><td>${currentBuild.durationString}</td></tr>
                <tr><th>测试状态</th><td>${resultStatus}</td></tr>
                <tr><th>构建状态</th><td>${currentBuild.currentResult}</td></tr>
            </table>

            <h3>测试结果</h3>
            ${htmlTable}

            <p style="margin-top: 20px;">详细日志请查看附件。</p>
            <p>Jenkins 构建地址: <a href="${env.BUILD_URL}">${env.BUILD_URL}</a></p>
        </div>
        <div class="footer">
            此邮件由 Jenkins 自动发送，请勿回复。
        </div>
    </div>
</body>
</html>"""
                        echo "=== IFBench 测试结果 ==="
                        echo "Build Number: ${BUILD_NUMBER}"
                        echo "结果目录: ${resultDir}"
                        echo "测试状态: ${resultStatus}"
                        echo "Prompts: ${prompts}, Errors: ${errors}, Changed: ${changed}"
                        echo "Accuracy Strict: ${accuracyStrict}, Accuracy Loose: ${accuracyLoose}"
                        emailext(
                            subject: "[模型推理 - IFBench精度测试报告] #${BUILD_NUMBER} ${params.CHIP} - ${params.MODEL}",
                            body: emailBody,
                            to: "${params.RECIPIENTS}",
                            mimeType: 'text/html',
                            attachmentsPattern: "reports/${BUILD_NUMBER}/**/ifb_results_build${BUILD_NUMBER}.log"
                        )
                    }
                }
            }
        }
    }
    post {
        always {
            script {
                archiveArtifacts artifacts: "reports/${env.BUILD_NUMBER}/**", allowEmptyArchive: true, fingerprint: true
                echo "构建完成: ${currentBuild.currentResult}"
            }
        }
        cleanup {
            cleanWs()
        }
    }
}
def extractValue(String content, String pattern, int group) {
    def matcher = content =~ pattern
    if (matcher.find()) {
        return matcher.group(group)
    }
    return null
}