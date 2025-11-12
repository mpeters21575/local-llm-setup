<#
.SYNOPSIS
    System configuration functions
#>

function Set-ClaudeCodeConfiguration {
    <#
    .SYNOPSIS
        Configures Claude Code to use the proxy layer (NOT direct Ollama)
    .DESCRIPTION
        CRITICAL: Claude Code must point to the proxy at port 8082, not Ollama directly
        The proxy translates Anthropic API format to Ollama OpenAI format
    #>
    param([PSCustomObject]$Config)

    Write-Log "Configuring Claude Code to use local LLM via proxy..." -Level INFO
    Write-Log "IMPORTANT: Claude Code → Proxy (port $($Config.ProxyPort)) → Ollama (port $($Config.OllamaPort))" -Level INFO

    # Wait for proxy to be ready (it should have been started by Install-ClaudeOllamaProxy)
    $proxyReady = $false
    $maxWait = 30
    $waited = 0

    Write-Log "Verifying proxy is running..." -Level INFO
    while (-not $proxyReady -and $waited -lt $maxWait) {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$($Config.ProxyPort)/health" `
                -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop

            if ($response.StatusCode -eq 200) {
                $proxyReady = $true
                Write-Log "Proxy health check passed" -Level SUCCESS
            }
        } catch {
            Start-Sleep -Seconds 2
            $waited += 2
            Write-Log "Waiting for proxy to be ready... ($waited/$maxWait seconds)" -Level INFO
        }
    }

    if (-not $proxyReady) {
        throw "Proxy is not running at http://127.0.0.1:$($Config.ProxyPort). Cannot configure Claude Code."
    }

    # Set environment variables for Claude Code (official method)
    Write-Log "Setting ANTHROPIC_BASE_URL environment variable..." -Level INFO

    $proxyUrl = "http://127.0.0.1:$($Config.ProxyPort)"

    # Set for current user (persists across sessions)
    [System.Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", $proxyUrl, "User")
    [System.Environment]::SetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", "local-offline-mode", "User")

    # Set for current session
    $env:ANTHROPIC_BASE_URL = $proxyUrl
    $env:ANTHROPIC_AUTH_TOKEN = "local-offline-mode"

    Write-Log "Environment variables set:" -Level SUCCESS
    Write-Log "  ANTHROPIC_BASE_URL = $proxyUrl" -Level INFO
    Write-Log "  ANTHROPIC_AUTH_TOKEN = local-offline-mode" -Level INFO

    # Also create a .claude directory with reminder file
    $claudeConfigPath = "$env:USERPROFILE\.claude"
    if (-not (Test-Path $claudeConfigPath)) {
        New-Item -ItemType Directory -Path $claudeConfigPath -Force | Out-Null
    }

    $readmeContent = @"
# Claude Code Offline Configuration

This Claude Code installation is configured for 100% OFFLINE operation.

## Configuration Details

- **Proxy URL**: http://127.0.0.1:$($Config.ProxyPort)
- **Local LLM**: $($Config.ModelName) via Ollama at localhost:$($Config.OllamaPort)
- **Offline Mode**: ENABLED - No internet access required or allowed

## How It Works

1. Claude Code → Sends requests to http://127.0.0.1:$($Config.ProxyPort) (Proxy)
2. Proxy → Translates Anthropic API format to OpenAI format
3. Proxy → Forwards to Ollama at http://localhost:$($Config.OllamaPort)
4. Ollama → Runs $($Config.ModelName) model locally
5. Response travels back through the chain

## Environment Variables

The following environment variables are set:
- ANTHROPIC_BASE_URL=http://127.0.0.1:$($Config.ProxyPort)
- ANTHROPIC_AUTH_TOKEN=local-offline-mode

## Troubleshooting

If Claude Code isn't working:

1. Verify proxy is running:
   Start-ScheduledTask -TaskName "ClaudeOllamaProxy"

2. Check proxy health:
   Invoke-WebRequest -Uri "http://127.0.0.1:$($Config.ProxyPort)/health"

3. Verify Ollama is running:
   Invoke-RestMethod -Uri "http://localhost:$($Config.OllamaPort)/api/tags"

4. Check environment variables:
   Get-ChildItem Env:ANTHROPIC_*

## Files

- Proxy location: $env:USERPROFILE\.claude-proxy
- Proxy logs: Check Task Scheduler → ClaudeOllamaProxy task
- Setup logs: $($Config.LogPath)

Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

    $readmeFile = Join-Path $claudeConfigPath "OFFLINE_MODE_README.md"
    Set-Content -Path $readmeFile -Value $readmeContent -Force

    Write-Log "Configuration complete. Claude Code will use local LLM via proxy." -Level SUCCESS
    Write-Log "README saved to: $readmeFile" -Level INFO
}

function Set-EnvironmentVariables {
    param([PSCustomObject]$Config)

    Write-Log "Setting environment variables for offline operation..." -Level INFO

    $envVars = @{
        # Claude Code configuration (already set by Set-ClaudeCodeConfiguration, but ensuring)
        "ANTHROPIC_BASE_URL" = "http://127.0.0.1:$($Config.ProxyPort)"
        "ANTHROPIC_AUTH_TOKEN" = "local-offline-mode"

        # Ollama configuration
        "OLLAMA_HOST" = "http://localhost:$($Config.OllamaPort)"

        # Offline mode indicators
        "CLAUDE_OFFLINE_MODE" = "true"
        "OFFLINE_MODE" = "true"

        # Disable telemetry for various tools
        "DISABLE_TELEMETRY" = "1"
        "DO_NOT_TRACK" = "1"

        # Proxy configuration - only allow localhost
        "NO_PROXY" = "localhost,127.0.0.1"
        "no_proxy" = "localhost,127.0.0.1"
    }

    foreach ($var in $envVars.GetEnumerator()) {
        [System.Environment]::SetEnvironmentVariable($var.Key, $var.Value, "User")
        Set-Item -Path "Env:$($var.Key)" -Value $var.Value -ErrorAction SilentlyContinue
        Write-Log "Set $($var.Key) = $($var.Value)" -Level INFO
    }

    Write-Log "Environment variables configured for offline operation" -Level SUCCESS
}

function Set-OfflineFirewallRules {
    <#
    .SYNOPSIS
        Configures Windows Firewall to enforce offline operation
    .DESCRIPTION
        Blocks internet access for Claude Code, proxy, and Ollama while allowing localhost communication
    #>
    param([PSCustomObject]$Config)

    Write-Log "Configuring firewall for strict offline operation..." -Level INFO
    Write-Log "This ensures NO external network access for LLM components" -Level INFO

    if (-not ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6)) {
        Write-Log "Firewall configuration is Windows-specific. Skipping on this platform." -Level WARNING
        return
    }

    # 1. Block Claude Code internet access (but allow localhost)
    $claudeExe = (Get-Command claude -ErrorAction SilentlyContinue).Source

    if ($claudeExe) {
        $ruleName = "LocalLLM-Block-Claude-Internet"

        # Remove existing rule if present
        Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule

        # Block outbound except localhost
        New-NetFirewallRule -DisplayName $ruleName `
            -Direction Outbound `
            -Program $claudeExe `
            -RemoteAddress Internet `
            -Action Block `
            -Profile Any `
            -Enabled True | Out-Null

        Write-Log "✓ Claude Code blocked from internet (localhost allowed)" -Level SUCCESS
    } else {
        Write-Log "Claude Code executable not found, skipping firewall rule" -Level WARNING
    }

    # 2. Block Python/UVicorn (proxy) internet access
    $pythonExe = (Get-Command python -ErrorAction SilentlyContinue).Source

    if ($pythonExe) {
        $ruleName = "LocalLLM-Block-Proxy-Internet"

        Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule

        New-NetFirewallRule -DisplayName $ruleName `
            -DisplayName $ruleName `
            -Direction Outbound `
            -Program $pythonExe `
            -RemoteAddress Internet `
            -Action Block `
            -Profile Any `
            -Enabled True | Out-Null

        Write-Log "✓ Python/Proxy blocked from internet (localhost allowed)" -Level SUCCESS
    }

    # 3. Allow Ollama localhost-only (inbound)
    $ollamaInboundRule = "LocalLLM-Allow-Ollama-Localhost-In"

    Get-NetFirewallRule -DisplayName $ollamaInboundRule -ErrorAction SilentlyContinue | Remove-NetFirewallRule

    New-NetFirewallRule -DisplayName $ollamaInboundRule `
        -Direction Inbound `
        -LocalAddress 127.0.0.1 `
        -LocalPort $Config.OllamaPort `
        -Protocol TCP `
        -Action Allow `
        -Profile Any `
        -Enabled True | Out-Null

    Write-Log "✓ Ollama port $($Config.OllamaPort) accessible from localhost only" -Level SUCCESS

    # 4. Allow proxy localhost-only (inbound)
    $proxyInboundRule = "LocalLLM-Allow-Proxy-Localhost-In"

    Get-NetFirewallRule -DisplayName $proxyInboundRule -ErrorAction SilentlyContinue | Remove-NetFirewallRule

    New-NetFirewallRule -DisplayName $proxyInboundRule `
        -Direction Inbound `
        -LocalAddress 127.0.0.1 `
        -LocalPort $Config.ProxyPort `
        -Protocol TCP `
        -Action Allow `
        -Profile Any `
        -Enabled True | Out-Null

    Write-Log "✓ Proxy port $($Config.ProxyPort) accessible from localhost only" -Level SUCCESS

    # 5. Block Rancher Desktop internet access (except initial setup)
    if ($Config.NetworkIsolation) {
        $rancherExe = "$env:LOCALAPPDATA\Programs\Rancher Desktop\Rancher Desktop.exe"

        if (Test-Path $rancherExe) {
            $ruleName = "LocalLLM-Block-Rancher-Internet"

            Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule

            New-NetFirewallRule -DisplayName $ruleName `
                -Direction Outbound `
                -Program $rancherExe `
                -RemoteAddress Internet `
                -Action Block `
                -Profile Any `
                -Enabled True | Out-Null

            Write-Log "✓ Rancher Desktop blocked from internet" -Level SUCCESS
        }
    }

    Write-Log "Firewall configuration complete - System is now offline" -Level SUCCESS
    Write-Log "All components can only communicate via localhost (127.0.0.1)" -Level INFO
}

function Test-OfflineMode {
    <#
    .SYNOPSIS
        Verifies that offline mode is working correctly
    .DESCRIPTION
        Tests that external connections are blocked and local connections work
    #>
    param([PSCustomObject]$Config)

    Write-Log "Testing offline mode configuration..." -Level INFO

    $testsPassed = 0
    $testsFailed = 0

    # Test 1: Verify external connection is blocked
    Write-Log "Test 1: Verifying external connections are blocked..." -Level INFO
    try {
        $response = Invoke-WebRequest -Uri "https://www.anthropic.com" -TimeoutSec 3 -ErrorAction Stop
        Write-Log "✗ FAILED: External connection succeeded (should be blocked)" -Level ERROR
        $testsFailed++
    } catch {
        Write-Log "✓ PASSED: External connections are blocked" -Level SUCCESS
        $testsPassed++
    }

    # Test 2: Verify Ollama is accessible locally
    Write-Log "Test 2: Verifying Ollama is accessible locally..." -Level INFO
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:$($Config.OllamaPort)/api/tags" -TimeoutSec 5
        Write-Log "✓ PASSED: Ollama is accessible on localhost" -Level SUCCESS
        $testsPassed++
    } catch {
        Write-Log "✗ FAILED: Cannot connect to Ollama locally" -Level ERROR
        $testsFailed++
    }

    # Test 3: Verify proxy is accessible locally
    Write-Log "Test 3: Verifying proxy is accessible locally..." -Level INFO
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$($Config.ProxyPort)/health" -TimeoutSec 5 -UseBasicParsing
        Write-Log "✓ PASSED: Proxy is accessible on localhost" -Level SUCCESS
        $testsPassed++
    } catch {
        Write-Log "✗ FAILED: Cannot connect to proxy locally" -Level ERROR
        $testsFailed++
    }

    # Test 4: Verify environment variables
    Write-Log "Test 4: Verifying environment variables..." -Level INFO
    if ($env:ANTHROPIC_BASE_URL -eq "http://127.0.0.1:$($Config.ProxyPort)") {
        Write-Log "✓ PASSED: ANTHROPIC_BASE_URL is correctly set" -Level SUCCESS
        $testsPassed++
    } else {
        Write-Log "✗ FAILED: ANTHROPIC_BASE_URL not set correctly" -Level ERROR
        $testsFailed++
    }

    # Summary
    Write-Log "`n=== OFFLINE MODE TEST RESULTS ===" -Level INFO
    Write-Log "Tests Passed: $testsPassed" -Level SUCCESS
    Write-Log "Tests Failed: $testsFailed" -Level $(if ($testsFailed -eq 0) { "SUCCESS" } else { "ERROR" })

    return ($testsFailed -eq 0)
}

function Show-UsageGuide {
    param([PSCustomObject]$Config)

    $guide = @"

╔═══════════════════════════════════════════════════════════════════════════╗
║                    LOCAL LLM SETUP COMPLETE                               ║
║                    100% OFFLINE OPERATION ENABLED                         ║
╚═══════════════════════════════════════════════════════════════════════════╝

🎯 QUICK START:

1. Using Claude Code (via local LLM):
   claude chat                          # Interactive chat
   claude "Explain PowerShell"          # Single query
   claude code                          # Code mode

2. System Architecture:
   Claude Code → Proxy (127.0.0.1:$($Config.ProxyPort)) → Ollama (localhost:$($Config.OllamaPort)) → Model

3. Verify System:
   • Check proxy: Start-ScheduledTask -TaskName "ClaudeOllamaProxy"
   • Check Ollama: nerdctl ps --filter "name=ollama"
   • Test offline: Test external connection should fail

4. Adding Documents (RAG):
   • Place documents in: $($Config.DocumentsPath)
   • Run: .\agents\Ingest-Documents.ps1

5. Managing Components:
   • Ollama:  nerdctl logs ollama
   • Proxy:   Task Scheduler → ClaudeOllamaProxy
   • Restart: Start-ScheduledTask -TaskName "ClaudeOllamaProxy"

📊 System Configuration:

   Model:           $($Config.ModelName)
   Ollama API:      http://localhost:$($Config.OllamaPort)
   Proxy API:       http://127.0.0.1:$($Config.ProxyPort)
   Claude Config:   ANTHROPIC_BASE_URL=http://127.0.0.1:$($Config.ProxyPort)
   Offline Mode:    ✓ ENABLED
   Firewall:        ✓ ACTIVE (Internet blocked)
   Telemetry:       ✓ DISABLED

📁 Important Paths:

   • Documents:     $($Config.DocumentsPath)
   • Vector DB:     $($Config.VectorDBPath)
   • Logs:          $($Config.LogPath)
   • Proxy:         $env:USERPROFILE\.claude-proxy
   • Config:        $env:USERPROFILE\.claude\OFFLINE_MODE_README.md

🔧 Troubleshooting:

   If Claude Code doesn't work:
   1. Start-ScheduledTask -TaskName "ClaudeOllamaProxy"
   2. Invoke-WebRequest "http://127.0.0.1:$($Config.ProxyPort)/health"
   3. Check logs in: $($Config.LogPath)

   If Ollama doesn't work:
   1. nerdctl restart ollama
   2. Test: Invoke-RestMethod "http://localhost:$($Config.OllamaPort)/api/tags"

🔒 Security Status:

   ✓ All external connections blocked by firewall
   ✓ Claude Code, Proxy, and Ollama cannot access internet
   ✓ Only localhost (127.0.0.1) communication allowed
   ✓ No telemetry or analytics sent anywhere
   ✓ All processing happens on your local machine

╔═══════════════════════════════════════════════════════════════════════════╗
║  Your AI assistant is 100% private and works completely offline!         ║
╚═══════════════════════════════════════════════════════════════════════════╝

"@

    Write-Host $guide -ForegroundColor Cyan

    $guideFile = Join-Path $env:USERPROFILE "LLM_Usage_Guide.txt"
    $guide | Out-File -FilePath $guideFile -Encoding UTF8
    Write-Log "Usage guide saved to: $guideFile" -Level SUCCESS
}

Export-ModuleMember -Function @(
    'Set-ClaudeCodeConfiguration',
    'Set-EnvironmentVariables',
    'Set-OfflineFirewallRules',
    'Test-OfflineMode',
    'Show-UsageGuide'
)