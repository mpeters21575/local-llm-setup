<#
.SYNOPSIS
    Utility functions for logging and common operations
#>

$script:LogPath = "$env:USERPROFILE\LLM_Setup_Logs"

function Initialize-Logging {
    param([string]$LogPath)
    $script:LogPath = $LogPath
    if (-not (Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    $color = switch ($Level) {
        "INFO" { "Cyan" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
    }
    
    Write-Host $logMessage -ForegroundColor $color
    
    $logFile = Join-Path $script:LogPath "setup_$(Get-Date -Format 'yyyyMMdd').log"
    Add-Content -Path $logFile -Value $logMessage
}

function Get-Configuration {
    param([string]$ConfigFile)

    if (Test-Path $ConfigFile) {
        $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        Write-Log "Configuration loaded from: $ConfigFile" -Level SUCCESS
    } else {
        Write-Log "Config file not found. Using defaults..." -Level WARNING
        $config = Get-DefaultConfiguration

        # Save default config
        $configDir = Split-Path $ConfigFile -Parent
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
        $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile
        Write-Log "Default configuration saved to: $ConfigFile" -Level INFO
    }

    # Expand environment variables in paths
    if ($config.DocumentsPath) {
        $config.DocumentsPath = [System.Environment]::ExpandEnvironmentVariables($config.DocumentsPath)
    }
    if ($config.VectorDBPath) {
        $config.VectorDBPath = [System.Environment]::ExpandEnvironmentVariables($config.VectorDBPath)
    }
    if ($config.LogPath) {
        $config.LogPath = [System.Environment]::ExpandEnvironmentVariables($config.LogPath)
    }

    return $config
}

function Get-DefaultConfiguration {
    return [PSCustomObject]@{
        ModelName = "qwen2.5:72b"
        AlternativeModels = @("llama3.1:70b", "mixtral:8x7b")
        OllamaPort = "11434"
        ProxyPort = "8082"
        ProxyEnabled = $true
        DocumentsPath = "$env:USERPROFILE\Documents\LLM_Knowledge"
        VectorDBPath = "$env:USERPROFILE\.llm_vectordb"
        LogPath = "$env:USERPROFILE\LLM_Setup_Logs"
        MaxMemoryGB = 28
        EmbeddingModel = "sentence-transformers/all-MiniLM-L6-v2"
        ChunkSize = 500
        ChunkOverlap = 50
        OfflineMode = $true
        DisableTelemetry = $true
        NetworkIsolation = $true
        RancherDesktopVersion = "latest"
        ClaudeCodePackage = "claude-code"
    }
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3,
        
        [Parameter(Mandatory = $false)]
        [int]$DelaySeconds = 5
    )
    
    $attempt = 0
    $success = $false
    
    while (-not $success -and $attempt -lt $MaxRetries) {
        try {
            $attempt++
            & $ScriptBlock
            $success = $true
        } catch {
            if ($attempt -lt $MaxRetries) {
                Write-Log "Attempt $attempt failed. Retrying in $DelaySeconds seconds..." -Level WARNING
                Start-Sleep -Seconds $DelaySeconds
            } else {
                throw
            }
        }
    }
}

function Test-Port {
    param(
        [string]$Address = "localhost",
        [int]$Port,
        [int]$TimeoutMs = 1000
    )
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connect = $tcpClient.BeginConnect($Address, $Port, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        
        if ($wait) {
            $tcpClient.EndConnect($connect)
            $tcpClient.Close()
            return $true
        } else {
            $tcpClient.Close()
            return $false
        }
    } catch {
        return $false
    }
}

Export-ModuleMember -Function @(
    'Initialize-Logging',
    'Write-Log',
    'Get-Configuration',
    'Get-DefaultConfiguration',
    'Invoke-WithRetry',
    'Test-Port'
)