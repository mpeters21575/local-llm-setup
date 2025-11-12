# Local LLM Setup with Claude Code Integration

Production-ready PowerShell automation for setting up a local Large Language Model (LLM) environment with Claude Code, running 100% offline on Windows 11.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Windows](https://img.shields.io/badge/Windows-11-0078D6.svg)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 🎯 Features

- **🤖 Claude Sonnet 4.5-equivalent LLM** - Uses Qwen2.5 72B or Llama 3.1 70B
- **🔒 100% Offline Operation** - No internet connectivity required or allowed
- **📚 Document Learning (RAG)** - Ingest your own documents with local embeddings (ChromaDB + sentence-transformers)
- **💬 Chat Summarization** - Automated conversation analysis and topic extraction
- **🐳 Containerized** - Runs in Rancher Desktop with Ollama
- **🛡️ Secure** - Firewall-enforced offline mode with no telemetry
- **⚡ Production-Ready** - Comprehensive error handling, logging, and verification
- **🔌 Proxy Layer** - Translates Claude Code → Ollama seamlessly

## 🏗️ Architecture (How Offline Mode Works)

This setup uses a **proxy layer** to enable Claude Code to work with local Ollama:

```
┌──────────────────────────────────────────────────────────────────┐
│                         YOU                                       │
└──────────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────────┐
│                     CLAUDE CODE CLI                               │
│  Environment: ANTHROPIC_BASE_URL=http://127.0.0.1:8082          │
└──────────────────────────────────────────────────────────────────┘
                            ↓
                  Anthropic API Format
                  POST /v1/messages
                            ↓
┌──────────────────────────────────────────────────────────────────┐
│              PROXY (claude-code-ollama-proxy)                    │
│  • Translates: Anthropic API → OpenAI API                        │
│  • Maps: claude-sonnet → qwen2.5:72b                            │
│  • Port: 8082 (localhost only)                                   │
└──────────────────────────────────────────────────────────────────┘
                            ↓
                   OpenAI API Format
                   POST /v1/chat/completions
                            ↓
┌──────────────────────────────────────────────────────────────────┐
│                    OLLAMA (Container)                            │
│  • Model: Qwen2.5 72B / Llama 3.1 70B                           │
│  • Port: 11434 (localhost only)                                  │
│  • Running in: Rancher Desktop                                   │
└──────────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────────┐
│                    LLM MODEL INFERENCE                            │
│  • 40GB+ model loaded in memory                                  │
│  • 100% local processing                                         │
└──────────────────────────────────────────────────────────────────┘
```

### RAG System (Document Learning)

```
Documents → Python Script → Local Embeddings (sentence-transformers)
    ↓
ChromaDB Vector Database (Local)
    ↓
Retrieved Context → Injected into LLM Prompts
```

**Key Points:**
- ✅ **No External API Calls**: All embeddings generated locally
- ✅ **Proxy Auto-Starts**: Windows scheduled task ensures it's always running
- ✅ **Firewall Protected**: Internet access blocked for all components
- ✅ **Transparent**: Claude Code works normally, unaware it's using local LLM

## 📋 Prerequisites

### System Requirements
- **OS**: Windows 11 (Windows 10 may work but not tested)
- **RAM**: 32GB minimum (28GB allocated to LLM)
- **Disk Space**: 150GB free (model is ~40-50GB)
- **CPU**: Multi-core processor (8+ cores recommended)
- **Virtualization**: Hyper-V enabled
- **Permissions**: Administrator access

### Software (Automatically Installed)
- PowerShell 5.1 or later
- Chocolatey package manager
- Rancher Desktop
- Ollama
- Claude Code
- Python 3.x

## 🚀 Quick Start

### 1. Clone the Repository
```powershell
git clone https://github.com/yourusername/local-llm-setup.git
cd local-llm-setup
```

### 2. Configure Settings

Edit `config/settings.json` with your preferences:
```json
{
  "ModelName": "qwen2.5:72b",
  "OllamaPort": "11434",
  "DocumentsPath": "C:\\Users\\YourUsername\\Documents\\LLM_Knowledge",
  "MaxMemoryGB": 28
}
```

### 3. Run Setup (as Administrator)
```powershell
# Right-click PowerShell and select "Run as Administrator"
cd path\to\local-llm-setup
.\Setup-LocalLLM.ps1
```

### 4. Wait for Installation

⏱️ **Estimated Time**: 45-90 minutes
- System validation: ~2 minutes
- Software installation: ~10 minutes
- Model download: ~30-60 minutes (depending on disk speed)
- Configuration & testing: ~5 minutes

## 📁 Project Structure
```
local-llm-setup/
├── Setup-LocalLLM.ps1           # Main orchestrator script
├── README.md                    # This file
├── LICENSE                      # MIT License
├── .gitignore                   # Git ignore rules
│
├── config/
│   └── settings.json           # Configuration settings
│
├── modules/
│   ├── Utilities.psm1          # Logging, config, helpers
│   ├── SystemChecks.psm1       # Requirements validation
│   ├── Installation.psm1       # Software installation
│   ├── Configuration.psm1      # System configuration
│   └── RAGSystem.psm1          # Document processing
│
└── docs/
    ├── USAGE.md                # Detailed usage guide
    ├── TROUBLESHOOTING.md      # Common issues & solutions
    └── ARCHITECTURE.md         # Technical architecture
```

## 📖 Usage

### Basic Claude Code Commands
```powershell
# Start interactive chat
claude chat

# Single query
claude "Explain how PowerShell pipelines work"

# Help
claude --help
```

### Document Ingestion
```powershell
# Place documents in your configured DocumentsPath
# Default: C:\Users\YourUsername\Documents\LLM_Knowledge

# Supported formats: .txt, .md, .pdf, .docx, .py, .ps1, .json, .xml, .yaml

# Run ingestion
.\Ingest-Documents.ps1

# Or specify custom path
.\Ingest-Documents.ps1 -DocsPath "C:\MyDocs"
```

### Chat Summarization
```powershell
# Summarize a chat conversation
.\Summarize-Chat.ps1 -ChatFile "conversation.txt"

# Save summary to file
.\Summarize-Chat.ps1 -ChatFile "chat.txt" -OutputFile "summary.txt"
```

### Managing Ollama
```powershell
# Check container status
nerdctl ps --filter "name=ollama"

# View logs
nerdctl logs ollama

# Restart container
nerdctl restart ollama

# List installed models
nerdctl exec ollama ollama list

# Pull additional models
nerdctl exec ollama ollama pull llama3.1:70b
```

## 🔧 Configuration

### Model Selection

The script defaults to **Qwen2.5 72B** (most similar to Claude Sonnet 4.5). Alternative models:
```json
{
  "ModelName": "qwen2.5:72b",     // Recommended (best quality)
  "ModelName": "llama3.1:70b",    // Alternative (good quality)
  "ModelName": "mixtral:8x7b"     // Lighter option (less RAM)
}
```

### Memory Allocation

Adjust based on your system:
```json
{
  "MaxMemoryGB": 28  // Leave ~4GB for Windows
}
```

### Custom Paths
```json
{
  "DocumentsPath": "D:\\MyKnowledge",
  "VectorDBPath": "D:\\VectorDB",
  "LogPath": "D:\\Logs"
}
```

## 🧪 Testing & Verification

The setup script automatically runs 7 verification tests:

1. ✅ Rancher Desktop running
2. ✅ Ollama container status
3. ✅ Ollama API responsiveness
4. ✅ Claude Code installation
5. ✅ Model inference functionality
6. ✅ Offline mode configuration
7. ✅ Firewall rules

View detailed test results in: `%USERPROFILE%\LLM_Setup_Logs\`

## 🐛 Troubleshooting

### Common Issues

**Issue**: Model download is slow
```powershell
# Solution: Check disk I/O, this is normal for 40-50GB download
# Monitor progress:
nerdctl exec ollama ollama list
```

**Issue**: Ollama container won't start
```powershell
# Solution: Restart Rancher Desktop
Stop-Process -Name "rancher-desktop" -Force
Start-Process "$env:LOCALAPPDATA\Programs\Rancher Desktop\Rancher Desktop.exe"
```

**Issue**: Claude Code can't connect
```powershell
# Solution 1: Verify proxy is running
Start-ScheduledTask -TaskName "ClaudeOllamaProxy"
Invoke-WebRequest -Uri "http://127.0.0.1:8082/health"

# Solution 2: Check environment variable
$env:ANTHROPIC_BASE_URL  # Should be: http://127.0.0.1:8082

# Solution 3: Verify Ollama is accessible
Invoke-RestMethod -Uri "http://localhost:11434/api/tags"

# Solution 4: Check proxy logs in Task Scheduler
```

**Issue**: Out of memory errors
```powershell
# Solution: Use a smaller model
# Edit config/settings.json:
# "ModelName": "mixtral:8x7b"
```

For more detailed troubleshooting, see [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

## 📊 Performance

### Model Comparison

| Model | Size | RAM Required | Quality | Speed |
|-------|------|--------------|---------|-------|
| Qwen2.5 72B | ~40GB | 28GB+ | ⭐⭐⭐⭐⭐ | Medium |
| Llama 3.1 70B | ~39GB | 28GB+ | ⭐⭐⭐⭐ | Medium |
| Mixtral 8x7B | ~26GB | 20GB+ | ⭐⭐⭐ | Fast |

### Typical Response Times

- Simple queries: 2-5 seconds
- Complex reasoning: 10-30 seconds
- Document summarization: 30-60 seconds

## 🔒 Security & Privacy

- ✅ **No Internet Access** - Firewall rules block all external connections
- ✅ **No Telemetry** - All tracking disabled
- ✅ **Local Processing** - All data stays on your machine
- ✅ **No API Keys** - No external services required
- ✅ **Encrypted Storage** - Documents processed locally

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Development Guidelines

- Follow PowerShell best practices
- Add comprehensive error handling
- Update documentation
- Test on Windows 11
- Maintain modular structure

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Anthropic](https://www.anthropic.com/) - For Claude and Claude Code
- [Ollama](https://ollama.ai/) - For local LLM runtime
- [Rancher Desktop](https://rancherdesktop.io/) - For container management
- [Qwen Team](https://github.com/QwenLM/Qwen) - For the Qwen models
- [Meta AI](https://ai.meta.com/) - For Llama models
- [mattlqx/claude-code-ollama-proxy](https://github.com/mattlqx/claude-code-ollama-proxy) - For the proxy layer
- [ChromaDB](https://www.trychroma.com/) - For local vector database
- [sentence-transformers](https://www.sbert.net/) - For local embeddings

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/local-llm-setup/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/local-llm-setup/discussions)
- **Documentation**: [Wiki](https://github.com/yourusername/local-llm-setup/wiki)

## 🗺️ Roadmap

- [x] **RAG with local embeddings** - ✅ Implemented with ChromaDB + sentence-transformers
- [x] **Proxy layer for offline operation** - ✅ Implemented with claude-code-ollama-proxy
- [x] **Network isolation** - ✅ Firewall rules enforce offline mode
- [ ] Support for additional models (Mistral, Phi-3, etc.)
- [ ] GUI installation wizard
- [ ] Advanced RAG features (re-ranking, hybrid search)
- [ ] Multi-modal support (images, audio)
- [ ] Docker Compose alternative to Rancher
- [ ] Linux and macOS support
- [ ] Model fine-tuning capabilities
- [ ] Web UI for chat interface

## 📈 Changelog

### v1.0.0 (2025-01-12)
- **Initial Release - Full Offline Operation**
- ✅ Qwen2.5 72B and Llama 3.1 70B support
- ✅ Claude Code integration via proxy layer (claude-code-ollama-proxy)
- ✅ RAG system with local embeddings (ChromaDB + sentence-transformers)
- ✅ Chat summarization agent
- ✅ Document ingestion agent
- ✅ Network isolation with firewall rules
- ✅ Automated proxy startup (Windows scheduled task)
- ✅ Environment variable configuration (ANTHROPIC_BASE_URL)
- ✅ Comprehensive logging and error handling
- ✅ Offline mode verification tests
- ✅ 100% offline architecture - NO external API calls

---

**⭐ If you find this project helpful, please consider giving it a star!**

Made with ❤️ for the AI community