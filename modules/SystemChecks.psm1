<#
.SYNOPSIS
    System requirements validation and cross-platform checks
#>

Import-Module (Join-Path $PSScriptRoot "Utilities.psm1") -Force

function Test-Administrator {
    Write-Log "Checking administrator privileges..." -Level INFO

    if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
        # Windows check
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)

        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw "This script must be run as Administrator on Windows"
        }
    } elseif ($IsMacOS -or $IsLinux) {
        # Unix check - warn if not root
        $isRoot = (id -u) -eq 0
        if (-not $isRoot) {
            Write-Log "Not running as root. Some operations may require sudo." -Level WARNING
        }
    }

    Write-Log "Administrator check passed" -Level SUCCESS
}

function Get-OperatingSystem {
    <#
    .SYNOPSIS
        Detects the operating system
    #>

    if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
        $osInfo = Get-CimInstance Win32_OperatingSystem
        return [PSCustomObject]@{
            Platform = "Windows"
            Version = $osInfo.Version
            Caption = $osInfo.Caption
        }
    } elseif ($IsMacOS) {
        $version = sw_vers -productVersion
        $arch = uname -m
        return [PSCustomObject]@{
            Platform = "macOS"
            Version = $version
            Architecture = $arch
        }
    } elseif ($IsLinux) {
        return [PSCustomObject]@{
            Platform = "Linux"
            Version = (uname -r)
        }
    }
}

function Test-SystemRequirements {
    Write-Log "Checking system requirements..." -Level INFO
    
    # Check RAM
    $totalRAM = [math]::Round((Get-CimInstance Win32_PhysicalMemory | 
        Measure-Object -Property Capacity -Sum).Sum / 1GB, 2)
    
    if ($totalRAM -lt 32) {
        throw "Insufficient RAM: ${totalRAM}GB. 32GB required."
    }
    Write-Log "RAM check passed: ${totalRAM}GB available" -Level SUCCESS
    
    # Check OS
    $os = Get-CimInstance Win32_OperatingSystem
    if ($os.Caption -notmatch "Windows 11") {
        Write-Log "OS: $($os.Caption). Windows 11 recommended." -Level WARNING
    } else {
        Write-Log "OS check passed: $($os.Caption)" -Level SUCCESS
    }
    
    # Check disk space
    $systemDrive = Get-PSDrive -Name $env:SystemDrive.Trim(':')
    $freeSpaceGB = [math]::Round($systemDrive.Free / 1GB, 2)
    
    if ($freeSpaceGB -lt 150) {
        Write-Log "Low disk space: ${freeSpaceGB}GB free. 150GB recommended." -Level WARNING
    } else {
        Write-Log "Disk space check passed: ${freeSpaceGB}GB free" -Level SUCCESS
    }
    
    # Check virtualization
    $hyperV = Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All -Online
    if ($hyperV.State -ne "Enabled") {
        Write-Log "Enabling Hyper-V..." -Level WARNING
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart
        Write-Log "Hyper-V enabled. System restart may be required." -Level INFO
    } else {
        Write-Log "Hyper-V check passed" -Level SUCCESS
    }
    
    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    Write-Log "PowerShell version: $psVersion" -Level INFO
}

function Test-Installation {
    param([PSCustomObject]$Config)
    
    Write-Log "Running installation verification tests..." -Level INFO
    $allTestsPassed = $true
    
    # Test 1: Rancher Desktop
    Write-Host "`n[TEST 1] Checking Rancher Desktop..." -ForegroundColor Yellow
    $rancherProcess = Get-Process "rancher-desktop" -ErrorAction SilentlyContinue
    if ($rancherProcess) {
        Write-Host "✓ Rancher Desktop is running" -ForegroundColor Green
    } else {
        Write-Host "✗ Rancher Desktop is not running" -ForegroundColor Red
        $allTestsPassed = $false
    }
    
    # Test 2: Ollama container
    Write-Host "`n[TEST 2] Checking Ollama container..." -ForegroundColor Yellow
    $nerdctlPath = "$env:LOCALAPPDATA\Programs\Rancher Desktop\resources\resources\win32\bin\nerdctl.exe"
    if (Test-Path $nerdctlPath) {
        $ollamaStatus = & $nerdctlPath ps --filter "name=ollama" --format "{{.Status}}"
        if ($ollamaStatus -match "Up") {
            Write-Host "✓ Ollama container is running" -ForegroundColor Green
        } else {
            Write-Host "✗ Ollama container is not running" -ForegroundColor Red
            $allTestsPassed = $false
        }
    } else {
        Write-Host "✗ nerdctl not found" -ForegroundColor Red
        $allTestsPassed = $false
    }
    
    # Test 3: Ollama API
    Write-Host "`n[TEST 3] Testing Ollama API..." -ForegroundColor Yellow
    if (Test-Port -Port $Config.OllamaPort) {
        try {
            $response = Invoke-RestMethod -Uri "http://localhost:$($Config.OllamaPort)/api/tags" -TimeoutSec 10
            Write-Host "✓ Ollama API is responsive" -ForegroundColor Green
            if ($response.models) {
                Write-Host "  Available models: $($response.models.name -join ', ')" -ForegroundColor Cyan
            }
        } catch {
            Write-Host "✗ Ollama API error: $_" -ForegroundColor Red
            $allTestsPassed = $false
        }
    } else {
        Write-Host "✗ Cannot connect to port $($Config.OllamaPort)" -ForegroundColor Red
        $allTestsPassed = $false
    }
    
    # Test 4: Claude Code
    Write-Host "`n[TEST 4] Checking Claude Code..." -ForegroundColor Yellow
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Host "✓ Claude Code is installed" -ForegroundColor Green
        $version = claude --version 2>&1
        Write-Host "  Version: $version" -ForegroundColor Cyan
    } else {
        Write-Host "✗ Claude Code not found" -ForegroundColor Red
        $allTestsPassed = $false
    }
    
    # Test 5: Model inference
    Write-Host "`n[TEST 5] Testing model inference..." -ForegroundColor Yellow
    try {
        $testBody = @{
            model = $Config.ModelName
            prompt = "Say 'OK' if you can read this."
            stream = $false
            options = @{ num_predict = 10 }
        } | ConvertTo-Json
        
        $testResponse = Invoke-RestMethod -Uri "http://localhost:$($Config.OllamaPort)/api/generate" `
            -Method Post -Body $testBody -ContentType "application/json" -TimeoutSec 60
        
        if ($testResponse.response) {
            Write-Host "✓ Model inference working" -ForegroundColor Green
            Write-Host "  Response: $($testResponse.response)" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "✗ Model inference failed: $_" -ForegroundColor Red
        $allTestsPassed = $false
    }
    
    # Test 6: Offline mode
    Write-Host "`n[TEST 6] Verifying offline configuration..." -ForegroundColor Yellow
    if ($env:CLAUDE_OFFLINE_MODE -eq "true") {
        Write-Host "✓ Offline mode configured" -ForegroundColor Green
    } else {
        Write-Host "⚠ Offline mode may not be properly set" -ForegroundColor Yellow
    }
    
    # Summary
    Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
    if ($allTestsPassed) {
        Write-Host "ALL TESTS PASSED ✓" -ForegroundColor Green
    } else {
        Write-Host "SOME TESTS FAILED ✗" -ForegroundColor Red
    }
    Write-Host ("=" * 70) -ForegroundColor Cyan
    
    return $allTestsPassed
}

Export-ModuleMember -Function @(
    'Test-Administrator',
    'Get-OperatingSystem',
    'Test-SystemRequirements',
    'Test-Installation'
)