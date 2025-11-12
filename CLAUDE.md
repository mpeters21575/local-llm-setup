# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a PowerShell-based automation project that sets up a local Large Language Model (LLM) environment with Claude Code integration, designed to run 100% offline on Windows 11. The system uses Ollama running in Rancher Desktop to serve models like Qwen2.5 72B or Llama 3.1 70B, with optional RAG (Retrieval-Augmented Generation) capabilities for document ingestion.

## System Requirements

- **OS**: Windows 11 (macOS/Linux not supported)
- **RAM**: 32GB minimum (28GB allocated to LLM)
- **Disk**: 150GB free space
- **CPU**: 8+ cores recommended
- **Virtualization**: Hyper-V enabled
- **Permissions**: Administrator access required

## Key Commands

### Running the Setup
```powershell
# Must be run as Administrator in PowerShell
.\Setup-LocalLLM.ps1

# With custom config
.\Setup-LocalLLM.ps1 -ConfigFile "path\to\settings.json"
```

**Note**: The filename was fixed - no longer has trailing space.

### Managing Ollama Container
```powershell
# Check status
nerdctl ps --filter "name=ollama"

# View logs
nerdctl logs ollama

# Restart container
nerdctl restart ollama

# List models
nerdctl exec ollama ollama list

# Pull additional models
nerdctl exec ollama ollama pull llama3.1:70b
```

### Using Claude Code
```powershell
# Interactive chat
claude chat

# Single query
claude "Your question here"

# Help
claude --help
```

### Running Agents
```powershell
# Document ingestion
.\agents\Ingest-Documents.ps1 -DocsPath "C:\Path\To\Docs"

# Chat summarization
.\agents\Summarize-Chat.ps1 -ChatFile "conversation.txt" -OutputFile "summary.txt"
```

### Testing Installation
```powershell
# Verify Ollama is accessible
Invoke-RestMethod -Uri "http://localhost:11434/api/tags"
```

## Architecture

### Offline Operation - Critical Component: Proxy Layer

**IMPORTANT**: Claude Code does NOT natively support Ollama. This project uses a **proxy layer** to translate API calls:

```
Claude Code (Anthropic API) → Proxy (Translation) → Ollama (OpenAI API) → Local Model
```

**Key Files**:
- `Installation.psm1:183-338` - `Install-ClaudeOllamaProxy` function
- `Configuration.psm1:6-123` - `Set-ClaudeCodeConfiguration` function
- Environment: `ANTHROPIC_BASE_URL=http://127.0.0.1:8082`

**How It Works**:
1. Claude Code sends requests to `http://127.0.0.1:8082` (proxy)
2. Proxy (claude-code-ollama-proxy) translates Anthropic API format to OpenAI format
3. Proxy forwards to Ollama at `localhost:11434`
4. Response is translated back and returned to Claude Code

**Proxy Management**:
```powershell
# Start proxy
Start-ScheduledTask -TaskName "ClaudeOllamaProxy"

# Check proxy health
Invoke-WebRequest -Uri "http://127.0.0.1:8082/health"

# Proxy runs automatically on login (Windows scheduled task)
```

### Modular Design

The setup process follows a 5-phase orchestration pattern in `Setup-LocalLLM.ps1`:

1. **Phase 1: System Validation** - Checks admin privileges and system requirements
2. **Phase 2: Software Installation** - Installs Chocolatey, Rancher Desktop, Ollama, models, and Claude Code
3. **Phase 3: System Configuration** - Configures Claude Code, sets firewall rules, environment variables
4. **Phase 4: RAG System Setup** - Initializes vector database and creates agent scripts
5. **Phase 5: Installation Verification** - Runs 7 comprehensive tests

### Module Structure

The project is organized into five PowerShell modules under `modules/`:

- **Utilities.psm1** - Logging, configuration loading, and helper functions
- **SystemChecks.psm1** - Administrator checks and system requirements validation
- **Installation.psm1** - Software installation logic including:
  - `Install-ClaudeOllamaProxy` (lines 183-338) - **CRITICAL for offline operation**
  - Chocolatey, Rancher Desktop, Ollama, models, Claude Code
- **Configuration.psm1** - System configuration including:
  - `Set-ClaudeCodeConfiguration` (lines 6-123) - Sets ANTHROPIC_BASE_URL to proxy
  - `Set-OfflineFirewallRules` (lines 160-275) - Blocks internet for all components
  - `Test-OfflineMode` (lines 277-340) - Verifies offline operation
- **RAGSystem.psm1** - Document processing with **local embeddings**:
  - Uses ChromaDB for vector storage (100% local)
  - Uses sentence-transformers for embeddings (no external API)
  - Embedding model: sentence-transformers/all-MiniLM-L6-v2 (~80MB)
  - Python script: `rag_processor.py` (generated during setup)

All modules are imported at the start of `Setup-LocalLLM.ps1` and provide cmdlets that are called in sequence.

### RAG System (Document Learning)

**100% Offline RAG Implementation**:
1. Documents placed in `DocumentsPath` (default: `%USERPROFILE%\Documents\LLM_Knowledge`)
2. `rag_processor.py` processes documents:
   - Extracts text from supported file types
   - Chunks text (500 chars with 50 char overlap)
   - Generates embeddings using local sentence-transformers model
   - Stores in ChromaDB vector database (persistent, local)
3. Retrieved context can be injected into LLM prompts

**No external API calls** - all processing happens locally.

### Agent Scripts

Two agent scripts are generated during setup and placed in `agents/`:

- **Ingest-Documents.ps1** - Processes documents (txt, md, pdf, docx, py, ps1, json, xml, yaml) and stores them in a vector database for RAG functionality
- **Summarize-Chat.ps1** - Analyzes chat conversations and extracts key topics, decisions, and summaries

### Configuration

Main configuration is in `config/settings.json`:

```json
{
  "ModelName": "qwen2.5:72b",           // LLM model (qwen2.5:72b, llama3.1:70b, mixtral:8x7b)
  "OllamaPort": "11434",                // Ollama API port
  "DocumentsPath": "C:\\Users\\...\\LLM_Knowledge",  // RAG document path
  "MaxMemoryGB": 28                      // Memory allocation for LLM
}
```

### Key Design Patterns

1. **Error Handling**: `$ErrorActionPreference = "Stop"` at script level with try-catch in main function
2. **Logging**: Centralized logging through `Write-Log` cmdlet from Utilities module
3. **Progressive Enhancement**: Each phase builds on previous phases, with verification at the end
4. **Offline-First**: Firewall rules enforce no external connectivity after setup
5. **Containerization**: Ollama runs in Rancher Desktop (nerdctl) for isolation

## Important Implementation Details

### PowerShell Module Loading

All modules are imported with `-Force` flag to ensure reload on every run:
```powershell
Import-Module (Join-Path $modulePath "Utilities.psm1") -Force
```

### Timing Constraints

- **Total setup time**: 45-90 minutes
- **Model download**: 30-60 minutes (40-50GB models)
- **Software installation**: ~10 minutes
- Sleep delays are used (e.g., `Start-Sleep -Seconds 10`) after Rancher Desktop startup

### Model Options

The system supports three model tiers:
- **Qwen2.5 72B** (~40GB): Recommended, closest to Claude Sonnet 4.5
- **Llama 3.1 70B** (~39GB): Alternative, good quality
- **Mixtral 8x7B** (~26GB): Lighter option for systems with less RAM

### Security Model

The system enforces offline operation through:
1. Firewall rules blocking external connections
2. Disabled telemetry in all components
3. Local-only processing (no API keys required)
4. All data stays on the local machine

## Common Development Patterns

### When Adding New Modules

1. Create the `.psm1` file in `modules/`
2. Define cmdlets using `function FunctionName { ... }` with proper `[CmdletBinding()]`
3. Export functions at module level if needed
4. Import in `Setup-LocalLLM.ps1` with `-Force` flag
5. Call functions in appropriate phase of the main orchestration

### When Creating New Agents

Agents should:
- Accept parameters for configuration (paths, files, etc.)
- Load necessary modules from the `modules/` directory
- Use the logging system from Utilities module
- Handle errors gracefully with try-catch
- Interact with Ollama API at `http://localhost:11434`

### When Modifying Configuration

1. Update `config/settings.json` with new properties
2. Ensure `Get-Configuration` cmdlet in Utilities.psm1 handles new properties
3. Pass config object through the orchestration pipeline
4. Update README.md with new configuration options

## File Naming Note

**IMPORTANT**: The main setup script has a trailing space in its filename: `Setup-LocalLLM.ps1 ` (note the space after .ps1). This is an unusual naming convention and should be considered when:
- Referencing the file in documentation
- Using file operations in code
- Creating git operations or file moves

Consider renaming this file to `Setup-LocalLLM.ps1` (without trailing space) for consistency.

## Expected Response Times

- Simple queries: 2-5 seconds
- Complex reasoning: 10-30 seconds
- Document summarization: 30-60 seconds

These times depend on system specs and model selected.
