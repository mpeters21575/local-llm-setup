<#
.SYNOPSIS
    Software installation functions
#>

function Install-Chocolatey {
    Write-Log "Checking Chocolatey installation..." -Level INFO
    
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Log "Installing Chocolatey..." -Level INFO
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = 
            [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
            'https://community.chocolatey.org/install.ps1'))
        
        # Refresh environment
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + 
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        Write-Log "Chocolatey installed successfully" -Level SUCCESS
    } else {
        Write-Log "Chocolatey already installed" -Level SUCCESS
        choco upgrade chocolatey -y
    }
}

function Install-RancherDesktop {
    param([PSCustomObject]$Config)
    
    Write-Log "Checking Rancher Desktop installation..." -Level INFO
    
    $rancherPath = "$env:LOCALAPPDATA\Programs\Rancher Desktop\Rancher Desktop.exe"
    
    if (-not (Test-Path $rancherPath)) {
        Write-Log "Installing Rancher Desktop..." -Level INFO
        choco install rancher-desktop -y --params="'/NoAutoStart'"
        
        Write-Log "Waiting for installation to complete..." -Level INFO
        Start-Sleep -Seconds 30
        
        Write-Log "Rancher Desktop installed" -Level SUCCESS
    } else {
        Write-Log "Rancher Desktop already installed" -Level SUCCESS
    }
    
    # Configure Rancher Desktop
    $configPath = "$env:APPDATA\rancher-desktop\settings.json"
    if (-not (Test-Path (Split-Path $configPath))) {
        New-Item -ItemType Directory -Path (Split-Path $configPath) -Force | Out-Null
    }
    
    $rancherConfig = @{
        version = 8
        application = @{
            adminAccess = $false
            pathManagementStrategy = "rcfiles"
            updater = @{ enabled = $false }
        }
        virtualMachine = @{
            memoryInGB = $Config.MaxMemoryGB
            numberCPUs = [Environment]::ProcessorCount - 2
        }
        containerEngine = @{
            allowedImages = @{ enabled = $false }
            name = "containerd"
        }
        kubernetes = @{ enabled = $false }
    } | ConvertTo-Json -Depth 10
    
    Set-Content -Path $configPath -Value $rancherConfig -Force
    Write-Log "Rancher Desktop configured" -Level SUCCESS
    
    # Start Rancher Desktop if not running
    $process = Get-Process "rancher-desktop" -ErrorAction SilentlyContinue
    if (-not $process) {
        Write-Log "Starting Rancher Desktop..." -Level INFO
        Start-Process $rancherPath
        Start-Sleep -Seconds 45
    }
}

function Install-OllamaInRancher {
    param([PSCustomObject]$Config)
    
    Write-Log "Setting up Ollama in Rancher Desktop..." -Level INFO
    
    $nerdctlPath = "$env:LOCALAPPDATA\Programs\Rancher Desktop\resources\resources\win32\bin\nerdctl.exe"
    
    # Wait for nerdctl to be available
    $maxWait = 60
    $waited = 0
    while (-not (Test-Path $nerdctlPath) -and $waited -lt $maxWait) {
        Start-Sleep -Seconds 5
        $waited += 5
        Write-Log "Waiting for Rancher Desktop to initialize... ($waited/$maxWait seconds)" -Level INFO
    }
    
    if (-not (Test-Path $nerdctlPath)) {
        throw "nerdctl not found after waiting. Please restart Rancher Desktop manually."
    }
    
    # Pull Ollama container
    Write-Log "Pulling Ollama container..." -Level INFO
    & $nerdctlPath pull ollama/ollama:latest
    
    # Stop existing container if running
    $existing = & $nerdctlPath ps -a --filter "name=ollama" --format "{{.ID}}"
    if ($existing) {
        Write-Log "Removing existing Ollama container..." -Level INFO
        & $nerdctlPath rm -f ollama
    }
    
    # Create volume
    & $nerdctlPath volume create ollama_data | Out-Null
    
    # Run container
    Write-Log "Starting Ollama container..." -Level INFO
    & $nerdctlPath run -d `
        --name ollama `
        --restart always `
        -p "$($Config.OllamaPort):11434" `
        -v ollama_data:/root/.ollama `
        -e OLLAMA_HOST=0.0.0.0 `
        ollama/ollama:latest
    
    Start-Sleep -Seconds 10
    
    # Verify
    $status = & $nerdctlPath ps --filter "name=ollama" --format "{{.Status}}"
    if ($status -match "Up") {
        Write-Log "Ollama container running successfully" -Level SUCCESS
    } else {
        throw "Failed to start Ollama container"
    }
}

function Install-LLMModel {
    param([PSCustomObject]$Config)
    
    Write-Log "Installing LLM model: $($Config.ModelName)" -Level INFO
    Write-Log "This may take 30-60 minutes (40-50GB download)..." -Level WARNING
    
    $nerdctlPath = "$env:LOCALAPPDATA\Programs\Rancher Desktop\resources\resources\win32\bin\nerdctl.exe"
    
    Write-Log "Pulling model $($Config.ModelName)..." -Level INFO
    & $nerdctlPath exec ollama ollama pull $Config.ModelName
    
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Model installed successfully" -Level SUCCESS
    } else {
        throw "Failed to install model $($Config.ModelName)"
    }
    
    # Test model
    Write-Log "Testing model..." -Level INFO
    $test = & $nerdctlPath exec ollama ollama run $Config.ModelName "Say OK"
    Write-Log "Model test response: $test" -Level SUCCESS
}

function Install-ClaudeCode {
    Write-Log "Installing Claude Code..." -Level INFO

    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Log "Claude Code already installed, upgrading..." -Level INFO
        choco upgrade claude-code -y
    } else {
        choco install claude-code -y
    }

    # Refresh environment
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Log "Claude Code installed successfully" -Level SUCCESS
    } else {
        throw "Claude Code installation failed"
    }
}

function Install-ClaudeOllamaProxy {
    <#
    .SYNOPSIS
        Installs and configures the proxy layer for Claude Code to communicate with Ollama
    .DESCRIPTION
        CRITICAL for offline operation - translates Anthropic API format to Ollama OpenAI format
    #>
    param([PSCustomObject]$Config)

    Write-Log "Installing Claude-Ollama Proxy (CRITICAL for offline operation)..." -Level INFO

    # Check if Python is installed
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Log "Python not found. Installing Python..." -Level INFO
        choco install python -y

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
    }

    # Install UV package manager if not present
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Log "Installing UV package manager..." -Level INFO

        try {
            $uvInstaller = Invoke-WebRequest -Uri "https://astral.sh/uv/install.ps1" -UseBasicParsing
            $uvInstaller.Content | Invoke-Expression

            # Add UV to PATH for current session
            $uvPath = "$env:USERPROFILE\.local\bin"
            if (Test-Path $uvPath) {
                $env:Path = "$uvPath;$env:Path"
            }
        } catch {
            Write-Log "Failed to install UV, trying alternative method..." -Level WARNING
            pip install uv
        }
    }

    # Clone proxy repository
    $proxyPath = "$env:USERPROFILE\.claude-proxy"

    if (Test-Path $proxyPath) {
        Write-Log "Proxy directory exists, updating..." -Level INFO
        Push-Location $proxyPath
        git pull
        Pop-Location
    } else {
        Write-Log "Cloning claude-code-ollama-proxy repository..." -Level INFO
        git clone https://github.com/mattlqx/claude-code-ollama-proxy.git $proxyPath
    }

    # Create .env configuration
    Write-Log "Configuring proxy..." -Level INFO

    $envContent = @"
PREFERRED_PROVIDER=ollama
OLLAMA_API_BASE=http://localhost:$($Config.OllamaPort)
BIG_MODEL=$($Config.ModelName)
SMALL_MODEL=llama3:8b
PORT=$($Config.ProxyPort)
HOST=127.0.0.1
"@

    Set-Content -Path "$proxyPath\.env" -Value $envContent -Force
    Write-Log "Proxy configuration saved to $proxyPath\.env" -Level SUCCESS

    # Create startup script
    $startScriptContent = @"
# Claude-Ollama Proxy Startup Script
Set-Location '$proxyPath'

Write-Host "Starting Claude-Ollama Proxy..." -ForegroundColor Cyan
Write-Host "Proxy will listen on http://127.0.0.1:$($Config.ProxyPort)" -ForegroundColor Cyan

# Start proxy
& uv run uvicorn server:app --host 127.0.0.1 --port $($Config.ProxyPort)
"@

    $startScriptPath = "$proxyPath\start-proxy.ps1"
    Set-Content -Path $startScriptPath -Value $startScriptContent -Force

    # Create Windows scheduled task for auto-start
    Write-Log "Creating scheduled task for proxy auto-start..." -Level INFO

    $taskName = "ClaudeOllamaProxy"
    $taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    if ($taskExists) {
        Write-Log "Removing existing scheduled task..." -Level INFO
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startScriptPath`""

    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1)

    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Proxy for Claude Code to use local Ollama LLM (offline operation)" `
        -Force | Out-Null

    Write-Log "Scheduled task created: $taskName" -Level SUCCESS

    # Start proxy now
    Write-Log "Starting proxy service..." -Level INFO
    Start-ScheduledTask -TaskName $taskName

    # Wait for proxy to start
    Write-Log "Waiting for proxy to initialize..." -Level INFO
    Start-Sleep -Seconds 5

    # Verify proxy is running
    $maxWait = 30
    $waited = 0
    $proxyReady = $false

    while (-not $proxyReady -and $waited -lt $maxWait) {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$($Config.ProxyPort)/health" `
                -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop

            if ($response.StatusCode -eq 200) {
                $proxyReady = $true
                Write-Log "Proxy is running and healthy" -Level SUCCESS
            }
        } catch {
            Start-Sleep -Seconds 2
            $waited += 2
            Write-Log "Waiting for proxy... ($waited/$maxWait seconds)" -Level INFO
        }
    }

    if (-not $proxyReady) {
        Write-Log "WARNING: Proxy may not have started correctly. Check task scheduler." -Level WARNING
        Write-Log "You can manually start it with: Start-ScheduledTask -TaskName ClaudeOllamaProxy" -Level INFO
    }

    Write-Log "Proxy installation completed. Listening on http://127.0.0.1:$($Config.ProxyPort)" -Level SUCCESS
    Write-Log "This proxy translates Claude Code API calls to Ollama format" -Level INFO
}

Export-ModuleMember -Function @(
    'Install-Chocolatey',
    'Install-RancherDesktop',
    'Install-OllamaInRancher',
    'Install-LLMModel',
    'Install-ClaudeCode',
    'Install-ClaudeOllamaProxy'
)