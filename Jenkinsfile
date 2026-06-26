pipeline {
    agent any
    parameters {
        string(name: 'TESTER', defaultValue: 'liwt', description: '测试人员名称 (必填)')
        choice(name: 'INFRA', choices: ['vllm', 'sglang'], description: '推理框架')
        choice(name: 'PD', choices: ['agg', 'disagg'], description: 'PD分离模式,agg 表示非 PD 分离, disagg 表示 PD 分离')
        string(name: 'CHIP', defaultValue: 'nvidia-h100', description: '芯片平台名称')
        string(name: 'MODEL', defaultValue: 'kimi-k2.5', description: '模型服务名称（served-model-name）')
        string(name: 'BASE_URL', defaultValue: 'http://10.201.149.10:8080/v1', description: 'API 地址（必填，请注意带有/v1后缀）')
        password(name: 'API_KEY', defaultValue: '', description: 'API Key (默认为空，如果服务端未设置API认证则保持默认即可)')
        text(name: 'RECIPIENTS', defaultValue: 'liwt@zetyun.com', description: '邮件接收者（逗号分隔）')
        string(name: 'WORK_DIR', defaultValue: '/dingofs/data1/userdata/liwt/maas-image/IFBench', description: '测试仓库目录，请不要改动')
    }
    environment {
        SSH_CREDENTIALS = 'HOST_SSH_KEY'
        REMOTE_HOST = '10.201.132.50'
        REMOTE_USER = 'root'
    }

    stages {
        stage('API 连通性预检') {
            steps {
                sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                    script {
                        def safeModelName = params.MODEL.contains('/') ? params.MODEL.tokenize('/').last() : params.MODEL
                        if (!safeModelName) {
                            safeModelName = 'unknown'
                        }
                        env.SAFE_MODEL_NAME = safeModelName

                        def apiKey = params.API_KEY ? params.API_KEY.toString().trim() : ''
                        def authHeaderLine = apiKey ?
                            "-H \"Authorization: Bearer ${apiKey}\" \\" :
                            ''
                        try {
                            sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << 'ENDSSH'
set -o pipefail
{
    echo "=== 检查 API 连通性 (/models) ==="
    HTTP_CODE=\$(curl -s --connect-timeout 10 -m 30 -o /dev/null -w "%{http_code}" ${params.BASE_URL}/models)
    if [ "\${HTTP_CODE}" != "200" ]; then
        echo "ERROR: API 连通性检查失败, HTTP状态码: \${HTTP_CODE}, URL: ${params.BASE_URL}/models"
        exit 1
    fi
    echo "API /models 连通性检查通过, HTTP状态码: \${HTTP_CODE}"

    echo "=== 检查 Chat Completions 接口 ==="
    CHAT_RESP=\$(curl -s --connect-timeout 10 -m 60 -w "\\n%{http_code}" \\
        ${authHeaderLine}
        -H "Content-Type: application/json" \\
        -d '{"model":"${params.MODEL}","messages":[{"role":"user","content":"hello"}],"max_tokens":10}' \\
        ${params.BASE_URL}/chat/completions)
    CHAT_HTTP_CODE=\$(echo "\${CHAT_RESP}" | tail -1)
    if [ "\${CHAT_HTTP_CODE}" != "200" ]; then
        echo "ERROR: Chat Completions 接口检查失败, HTTP状态码: \${CHAT_HTTP_CODE}"
        echo "响应内容: \$(echo "\${CHAT_RESP}" | head -n -1)"
        exit 1
    fi
    echo "Chat Completions 接口检查通过, HTTP状态码: \${CHAT_HTTP_CODE}"
} 2>&1 | tee /tmp/connectivity_${BUILD_NUMBER}.log
ENDSSH
"""
                        } catch (Exception e) {
                            env.CONNECTIVITY_FAILED = 'true'
                            currentBuild.result = 'UNSTABLE'
                            println("=== API 连通性预检失败,后续阶段(环境检查、运行IFBench测试)将跳过 ===")
                        }
                    }
                }
            }
        }

        stage('环境检查') {
            when {
                expression { env.CONNECTIVITY_FAILED != 'true' }
            }
            steps {
                sshagent(credentials: ["${SSH_CREDENTIALS}"]) {
                    sh """
ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << 'ENDSSH'
set -e
cd ${params.WORK_DIR}
echo "工作目录: \$(pwd)"
ls -la

echo "=== 设置权限 ==="
chmod +x ifbench_test.sh
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
            when {
                expression { env.CONNECTIVITY_FAILED != 'true' }
            }
            steps {
                script {
                    def apiKey = params.API_KEY ? params.API_KEY.toString().trim() : ''
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
./ifbench_test.sh "${params.BASE_URL}" "${apiKey}" "${params.MODEL}" "${params.CHIP}" > output/${params.TESTER}/${BUILD_NUMBER}/${params.CHIP}/${SAFE_MODEL_NAME}/ifb_results_build${BUILD_NUMBER}.log 2>&1
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
    ./reports/${BUILD_NUMBER}/ 2>/dev/null \
    && echo "测试结果目录已拉取: ${targetDir}" \
    || echo "WARN: 测试结果目录拉取失败(可能测试阶段未执行,例如连通性检查失败)"
scp -o StrictHostKeyChecking=no \
    ${REMOTE_USER}@${REMOTE_HOST}:${params.WORK_DIR}/.env \
    ./reports/${BUILD_NUMBER}/ 2>/dev/null || true
echo "=== 拉取连通性预检日志 ==="
scp -o StrictHostKeyChecking=no \
    ${REMOTE_USER}@${REMOTE_HOST}:/tmp/connectivity_${BUILD_NUMBER}.log \
    ./reports/${BUILD_NUMBER}/connectivity_${BUILD_NUMBER}.log 2>/dev/null \
    && echo "连通性预检日志已拉取" \
    || echo "WARN: 连通性预检日志拉取失败(可能未执行预检)"
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

                        def connectivityLogFile = "reports/${BUILD_NUMBER}/connectivity_${BUILD_NUMBER}.log"
                        def connectivityLogContent = fileExists(connectivityLogFile) ? readFile(connectivityLogFile) : ""
                        def failureReason = ""
                        def connectivityFailureReason = ""
                        if (connectivityLogContent.contains("API 连通性检查失败") ||
                            connectivityLogContent.contains("Chat Completions 接口检查失败")) {
                            failureReason = "连通性检查未通过"
                            println("DEBUG: 识别到连通性检查失败, 失败原因: ${failureReason}")
                            def logLines = connectivityLogContent.split('\n')
                            def collected = []
                            def inFailureSection = false
                            for (def ll : logLines) {
                                if (ll.contains("检查 API 连通性") || ll.contains("Chat Completions 接口检查")) {
                                    inFailureSection = true
                                }
                                if (inFailureSection) {
                                    if (!collected.isEmpty() && ll.trim().startsWith("===") &&
                                        !ll.contains("检查 API 连通性") && !ll.contains("Chat Completions 接口检查")) {
                                        break
                                    }
                                    collected.add(ll)
                                }
                            }
                            connectivityFailureReason = collected.join('\n').trim()
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
                            <tr><td>测试模型</td><td>${params.MODEL}</td></tr>
                            <tr><td>模型URL</td><td>${api}</td></tr>
                            <tr><td>请求数</td><td>${prompts}</td></tr>
                            <tr><td><b>测试参数</b></td><td>
                                TOP_P: ${topP}<br>
                                TOP_K: ${topK}<br>
                                Temperature: ${temperature}<br>
                                Max Tokens: ${maxTokens}<br>
                                Workers: ${workers}
                            </td></tr>
                            <tr><td>Errors</td><td>${errors}</td></tr>
                            <tr><td>Changed</td><td>${changed}</td></tr>
                            <tr style="background-color: #c8e6c9;"><td><b>Accuracy (Strict)</b></td><td><b>${accuracyStrict}</b></td></tr>
                            <tr style="background-color: #fff9c4;"><td><b>Accuracy (Loose)</b></td><td><b>${accuracyLoose}</b></td></tr>
                        </table>
                        """
                        def hasResult = fileExists(logFile) && logContent.length() > 0
                        def resultStatus = hasResult ? "成功" : "失败/无结果"
                        if (failureReason) {
                            resultStatus = failureReason
                        }
                        def resultDir = env.RESULT_DIR ?: 'N/A'

                        def connectivityFailureHtml = ""
                        if (failureReason) {
                            def escapedReason = connectivityFailureReason
                                .replace('&', '&amp;')
                                .replace('<', '&lt;')
                                .replace('>', '&gt;')
                            connectivityFailureHtml = """
    <div style="background-color: #ffebee; color: #000000; border-left: 4px solid #d32f2f; padding: 12px 15px; margin-top: 15px; border-radius: 3px;">
        <h3 style="color: #d32f2f; margin-top: 0; margin-bottom: 8px;">⚠️ 连通性检查未通过</h3>
        <p style="margin-top: 0; margin-bottom: 8px; color: #000000;">本次测试未能正常执行用例，原因是 API 连通性检查失败：</p>
        <pre style="background-color: #ffffff; color: #000000; padding: 10px; border-radius: 3px; overflow-x: auto; white-space: pre-wrap; margin: 0; font-family: Menlo, Consolas, monospace; font-size: 12px;">${escapedReason}</pre>
    </div>"""
                        }

                        def emailBody = """
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 900px; margin: 0 auto; background-color: #fff; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .header { background-color: ${(!failureReason && hasResult) ? '#4CAF50' : '#f44336'}; color: white; padding: 20px; border-radius: 5px 5px 0 0; }
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
                <tr><th>项目</th><td>值</td></tr>
                <tr><th>构建编号</th><td>#${BUILD_NUMBER}</td></tr>
                <tr><th>测试人员</th><td>${params.TESTER}</td></tr>
                <tr><th>芯片平台</th><td>${params.CHIP}</td></tr>
                <tr><th>推理框架</th><td>${params.INFRA}</td></tr>
                <tr><th>模型名称</th><td>${params.MODEL}</td></tr>
                <tr><th>PD分离模式</th><td>${params.PD}</td></tr>
                <tr><th>执行时间</th><td>${currentBuild.durationString}</td></tr>
                <tr><th>测试状态</th><td>${resultStatus}</td></tr>
                <tr><th>构建状态</th><td>${currentBuild.currentResult}</td></tr>
            </table>

            ${connectivityFailureHtml}

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
                        def attachmentPattern = failureReason ?
                            "reports/${BUILD_NUMBER}/connectivity_${BUILD_NUMBER}.log" :
                            "reports/${BUILD_NUMBER}/**/ifb_results_build${BUILD_NUMBER}.log"
                        emailext(
                            subject: "[模型推理 - IFBench精度测试报告] #${BUILD_NUMBER} ${params.CHIP} - ${params.MODEL}",
                            body: emailBody,
                            to: "${params.RECIPIENTS}",
                            mimeType: 'text/html',
                            attachmentsPattern: attachmentPattern
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