param([switch]$SkipModelWarmup, [switch]$EnableModelRuntime)
$ErrorActionPreference = 'Stop'
$chatAiRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../ai-service')).Path
$chatEnvPath = Join-Path $chatAiRoot '.env'
$chatEnvText = [IO.File]::ReadAllText($chatEnvPath)
. (Join-Path $chatAiRoot 'scripts/set-local-storage.ps1')
function Get-ChatSetting([string]$Name, [string]$Default) {
    $chatMatch = [regex]::Match($chatEnvText, "(?m)^${Name}=([^\r\n]*)")
    if ($chatMatch.Success) { return $chatMatch.Groups[1].Value.Trim().Trim('"').Trim("'") }
    return $Default
}
$chatProfile = Get-ChatSetting 'AI_REVIEWED_CONFIG_DIR' './artifacts/local-public-search/configs'
if (-not [IO.Path]::IsPathRooted($chatProfile)) { $chatProfile = Join-Path $chatAiRoot $chatProfile }
if (-not (Test-Path -LiteralPath (Join-Path $chatProfile 'local_activation.json'))) {
    throw 'Missing verified local deployment. Prepare the reviewed search/corpus configuration first.'
}
$chatUsesOllama = (Get-ChatSetting 'NLU_BACKEND' 'rule') -eq 'ollama' -or
    (Get-ChatSetting 'RAG_BACKEND' 'extractive') -eq 'ollama'
if ($chatUsesOllama -and -not $EnableModelRuntime) {
    throw 'Ollama is configured. Review storage and existing models, then explicitly use -EnableModelRuntime.'
}
$chatComposeArgs = @('compose', '--project-directory', $chatAiRoot, '--env-file', $chatEnvPath,
    '-f', (Join-Path $chatAiRoot 'docker-compose.local.yml'),
    '-f', (Join-Path $chatAiRoot 'docker-compose.knowledge.local.yml'))
if ($chatUsesOllama) {
    $chatComposeArgs += @('-f', (Join-Path $chatAiRoot 'docker-compose.ollama.local.yml'))
}
$chatComposeArgs += @('--profile', 'knowledge')
function Invoke-ChatDocker {
    & docker @args
    if ($LASTEXITCODE -ne 0) { throw 'Chatbot Docker command failed. Existing data volumes have been preserved.' }
}
$null = Invoke-RestMethod -Uri 'http://127.0.0.1:8080/api/v1/events?size=1' -TimeoutSec 5
$chatServices = @('knowledge-db', 'knowledge-reader')
if ($chatUsesOllama) { $chatServices += 'ollama' }
Invoke-ChatDocker @chatComposeArgs up -d --pull never --no-build @chatServices
$chatReaderReady = $false
for ($chatAttempt = 0; $chatAttempt -lt 30; $chatAttempt++) {
    & docker @chatComposeArgs exec -T knowledge-reader python -c 'import json,urllib.request; r=json.load(urllib.request.urlopen("http://127.0.0.1:8010/health/ready",timeout=5)); assert r["status"] == "ready"' 2>$null
    if ($LASTEXITCODE -eq 0) { $chatReaderReady = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $chatReaderReady) { throw 'Knowledge retrieval is not ready. Chat configuration was not switched.' }
if (-not $SkipModelWarmup -and (Get-ChatSetting 'NLU_BACKEND' 'rule') -eq 'ollama') {
    $chatWarmup = @{ model=(Get-ChatSetting 'OLLAMA_NLU_MODEL' 'smartevent-nlu:1.5b'); prompt=''; stream=$false; keep_alive=-1; options=@{num_ctx=2048} } | ConvertTo-Json -Depth 4
    $null = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/generate' -Method Post -ContentType 'application/json' -Body $chatWarmup -TimeoutSec 180
}
Invoke-ChatDocker @chatComposeArgs up -d --pull never --no-build ai
$null = Invoke-RestMethod -Uri 'http://127.0.0.1:8001/health/live' -TimeoutSec 5
Write-Output 'Chatbot local is running. Open the web app at http://localhost:3000.'
