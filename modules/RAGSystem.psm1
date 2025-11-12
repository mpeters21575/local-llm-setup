<#
.SYNOPSIS
    RAG system setup with local embeddings (100% offline)
.DESCRIPTION
    Implements Retrieval-Augmented Generation using ChromaDB and sentence-transformers
    All embeddings are generated locally - NO external API calls
#>

Import-Module (Join-Path $PSScriptRoot "Utilities.psm1") -Force

function Initialize-RAGSystem {
    <#
    .SYNOPSIS
        Sets up the RAG system with local vector database and embedding model
    #>
    param([PSCustomObject]$Config)

    Write-Log "Setting up RAG system with local embeddings..." -Level INFO
    Write-Log "Embedding Model: $($Config.EmbeddingModel)" -Level INFO

    # Create directories
    if (-not (Test-Path $Config.DocumentsPath)) {
        New-Item -ItemType Directory -Path $Config.DocumentsPath -Force | Out-Null
        Write-Log "Created documents directory: $($Config.DocumentsPath)" -Level INFO

        # Create sample document
        $sampleDoc = @"
# Welcome to Local LLM with RAG

This is a sample document to demonstrate the RAG (Retrieval-Augmented Generation) system.

## What is RAG?

RAG allows the LLM to retrieve relevant information from your documents before generating responses.

## How it works:

1. Documents are chunked into smaller pieces
2. Each chunk is embedded using a local model (no internet required)
3. Embeddings are stored in a vector database (ChromaDB)
4. When you ask a question, relevant chunks are retrieved
5. The LLM uses these chunks as context to generate better answers

## Supported File Types:

- Text files (.txt, .md)
- Code files (.py, .ps1, .js, .java, etc.)
- Configuration files (.json, .yaml, .xml)
- PDF documents (.pdf) *
- Word documents (.docx) *

* Requires additional Python packages

Add your own documents to: $($Config.DocumentsPath)

Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

        $samplePath = Join-Path $Config.DocumentsPath "Welcome.md"
        Set-Content -Path $samplePath -Value $sampleDoc -Force
        Write-Log "Created sample document: $samplePath" -Level INFO
    }

    if (-not (Test-Path $Config.VectorDBPath)) {
        New-Item -ItemType Directory -Path $Config.VectorDBPath -Force | Out-Null
        Write-Log "Created vector database directory: $($Config.VectorDBPath)" -Level INFO
    }

    # Ensure Python is installed
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Log "Python not found. Should have been installed by Install-ClaudeOllamaProxy." -Level WARNING
        Write-Log "Installing Python now..." -Level INFO
        choco install python -y
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
    }

    # Install required Python packages for RAG
    Write-Log "Installing Python packages for RAG system..." -Level INFO
    Write-Log "This includes: chromadb, sentence-transformers, torch" -Level INFO

    $packagesToInstall = @(
        "chromadb",
        "sentence-transformers",
        "torch",
        "transformers"
    )

    foreach ($package in $packagesToInstall) {
        Write-Log "Installing $package..." -Level INFO
        python -m pip install --quiet $package 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Log "✓ Installed $package" -Level SUCCESS
        } else {
            Write-Log "Warning: Failed to install $package" -Level WARNING
        }
    }

    # Download embedding model to local cache
    Write-Log "Downloading embedding model: $($Config.EmbeddingModel)..." -Level INFO
    Write-Log "This is a one-time download (~80MB), model will be cached locally" -Level INFO

    $downloadScript = @"
from sentence_transformers import SentenceTransformer
import sys

try:
    print(f"Downloading model: $($Config.EmbeddingModel)")
    model = SentenceTransformer('$($Config.EmbeddingModel)')
    print(f"Model downloaded and cached successfully")
    print(f"Embedding dimension: {model.get_sentence_embedding_dimension()}")

    # Test embedding
    test_embedding = model.encode(["This is a test"])
    print(f"Test embedding generated: {len(test_embedding[0])} dimensions")
    sys.exit(0)
except Exception as e:
    print(f"Error: {str(e)}", file=sys.stderr)
    sys.exit(1)
"@

    $tempScript = Join-Path $env:TEMP "download_model.py"
    Set-Content -Path $tempScript -Value $downloadScript -Force

    python $tempScript

    if ($LASTEXITCODE -eq 0) {
        Write-Log "✓ Embedding model downloaded and cached locally" -Level SUCCESS
    } else {
        Write-Log "WARNING: Failed to download embedding model. RAG may not work." -Level WARNING
    }

    Remove-Item $tempScript -ErrorAction SilentlyContinue

    # Create RAG document processor
    $processorScript = Get-RAGProcessorScript -Config $Config
    $scriptPath = Join-Path $Config.VectorDBPath "rag_processor.py"
    Set-Content -Path $scriptPath -Value $processorScript -Force
    Write-Log "Created RAG processor: $scriptPath" -Level SUCCESS

    Write-Log "RAG system initialized successfully" -Level SUCCESS
    Write-Log "Add documents to: $($Config.DocumentsPath)" -Level INFO
    Write-Log "Run: .\agents\Ingest-Documents.ps1 to process documents" -Level INFO
}

function Get-RAGProcessorScript {
    <#
    .SYNOPSIS
        Returns the Python script for processing documents with local embeddings
    #>
    param([PSCustomObject]$Config)

    return @"
#!/usr/bin/env python3
'''
RAG Document Processor - 100% Offline
Processes documents and stores embeddings in ChromaDB
Uses local sentence-transformers model - NO external API calls
'''

import os
import sys
from pathlib import Path
from typing import List, Dict
import chromadb
from chromadb.config import Settings
from sentence_transformers import SentenceTransformer

# Configuration
EMBEDDING_MODEL = '$($Config.EmbeddingModel)'
CHUNK_SIZE = $($Config.ChunkSize)
CHUNK_OVERLAP = $($Config.ChunkOverlap)
VECTOR_DB_PATH = r'$($Config.VectorDBPath)'

class RAGProcessor:
    def __init__(self):
        print(f'Initializing RAG Processor...')
        print(f'Embedding Model: {EMBEDDING_MODEL}')
        print(f'Vector DB Path: {VECTOR_DB_PATH}')

        # Initialize embedding model (local, no internet)
        print('Loading embedding model from local cache...')
        self.model = SentenceTransformer(EMBEDDING_MODEL)
        print(f'Model loaded. Embedding dimension: {self.model.get_sentence_embedding_dimension()}')

        # Initialize ChromaDB (local, persistent)
        self.client = chromadb.PersistentClient(
            path=VECTOR_DB_PATH,
            settings=Settings(
                anonymized_telemetry=False,
                allow_reset=True
            )
        )

        # Get or create collection
        try:
            self.collection = self.client.get_collection('documents')
            print(f'Using existing collection: {self.collection.count()} documents')
        except:
            self.collection = self.client.create_collection('documents')
            print('Created new collection')

    def extract_text(self, file_path: str) -> str:
        '''Extract text from supported file types'''
        ext = Path(file_path).suffix.lower()
        supported = ['.txt', '.md', '.py', '.ps1', '.js', '.java', '.c', '.cpp',
                     '.cs', '.go', '.rs', '.json', '.xml', '.yaml', '.yml', '.toml',
                     '.ini', '.cfg', '.conf', '.sh', '.bash']

        if ext not in supported:
            return None

        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                return f.read()
        except Exception as e:
            print(f'Error reading {file_path}: {e}', file=sys.stderr)
            return None

    def chunk_text(self, text: str) -> List[str]:
        '''Split text into overlapping chunks'''
        if len(text) <= CHUNK_SIZE:
            return [text]

        chunks = []
        start = 0

        while start < len(text):
            end = start + CHUNK_SIZE

            # Try to break at sentence boundary
            if end < len(text):
                for delimiter in ['. ', '.\n', '? ', '! ', '\n\n']:
                    idx = text.rfind(delimiter, start, end)
                    if idx != -1:
                        end = idx + len(delimiter)
                        break

            chunk = text[start:end].strip()
            if chunk:
                chunks.append(chunk)

            start = end - CHUNK_OVERLAP

        return chunks

    def process_documents(self, docs_path: str):
        '''Process all documents in the directory'''
        print(f'\nProcessing documents from: {docs_path}')

        if not os.path.exists(docs_path):
            print(f'Error: Directory not found: {docs_path}', file=sys.stderr)
            return

        all_chunks = []
        all_embeddings = []
        all_metadata = []
        all_ids = []

        file_count = 0
        chunk_count = 0

        for root, dirs, files in os.walk(docs_path):
            for file in files:
                file_path = os.path.join(root, file)
                text = self.extract_text(file_path)

                if text:
                    file_count += 1
                    chunks = self.chunk_text(text)

                    for i, chunk in enumerate(chunks):
                        doc_id = f'{file_path}:chunk:{i}'

                        all_chunks.append(chunk)
                        all_ids.append(doc_id)
                        all_metadata.append({
                            'source': file_path,
                            'chunk_index': i,
                            'total_chunks': len(chunks),
                            'file_type': Path(file_path).suffix
                        })

                        chunk_count += 1

                        # Progress indicator
                        if chunk_count % 10 == 0:
                            print(f'  Processed {chunk_count} chunks from {file_count} files...', end='\r')

        if chunk_count == 0:
            print('\nNo documents found to process')
            return

        print(f'\n\nGenerating embeddings for {chunk_count} chunks...')
        print('(This happens locally, no internet connection required)')

        # Generate embeddings locally
        all_embeddings = self.model.encode(
            all_chunks,
            show_progress_bar=True,
            convert_to_numpy=True
        )

        print(f'Storing embeddings in vector database...')

        # Store in ChromaDB
        self.collection.add(
            ids=all_ids,
            embeddings=all_embeddings.tolist(),
            documents=all_chunks,
            metadatas=all_metadata
        )

        print(f'\n✓ Successfully processed {file_count} files')
        print(f'✓ Created {chunk_count} chunks')
        print(f'✓ Generated {chunk_count} embeddings')
        print(f'✓ Total documents in database: {self.collection.count()}')

    def search(self, query: str, n_results: int = 5):
        '''Search for relevant documents'''
        print(f'\nSearching for: {query}')

        # Generate query embedding locally
        query_embedding = self.model.encode([query])[0]

        # Search in ChromaDB
        results = self.collection.query(
            query_embeddings=[query_embedding.tolist()],
            n_results=n_results
        )

        print(f'\nFound {len(results["documents"][0])} relevant chunks:\n')

        for i, (doc, metadata, distance) in enumerate(zip(
            results['documents'][0],
            results['metadatas'][0],
            results['distances'][0]
        )):
            print(f'{i+1}. Source: {metadata["source"]}')
            print(f'   Chunk: {metadata["chunk_index"]}/{metadata["total_chunks"]}')
            print(f'   Relevance: {1 - distance:.3f}')
            print(f'   Text: {doc[:200]}...')
            print()

def main():
    if len(sys.argv) < 2:
        print('Usage:')
        print('  python rag_processor.py <docs_path>        # Process documents')
        print('  python rag_processor.py search <query>     # Search documents')
        sys.exit(1)

    processor = RAGProcessor()

    if sys.argv[1] == 'search':
        query = ' '.join(sys.argv[2:])
        processor.search(query)
    else:
        docs_path = sys.argv[1]
        processor.process_documents(docs_path)

if __name__ == '__main__':
    main()
"@
}

function New-DocumentIngestionScript {
    <#
    .SYNOPSIS
        Creates the document ingestion script in the agents folder
    #>
    param(
        [PSCustomObject]$Config,
        [string]$ScriptRoot
    )

    $script = @"
<#
.SYNOPSIS
    Ingest documents into the RAG system with local embeddings

.DESCRIPTION
    Processes documents from the specified directory and stores them in ChromaDB
    with embeddings generated locally using sentence-transformers

.PARAMETER DocsPath
    Path to the directory containing documents to process

.EXAMPLE
    .\Ingest-Documents.ps1
    .\Ingest-Documents.ps1 -DocsPath "C:\MyDocuments"

.NOTES
    - Supported file types: .txt, .md, .py, .ps1, .js, .json, .xml, .yaml, etc.
    - All processing happens locally - NO internet required
    - Embeddings are generated using: $($Config.EmbeddingModel)
#>

param(
    [string]`$DocsPath = "$($Config.DocumentsPath)"
)

Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          RAG DOCUMENT INGESTION - 100% OFFLINE                 ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "📁 Document Path:  `$DocsPath" -ForegroundColor White
Write-Host "🧠 Embedding Model: $($Config.EmbeddingModel)" -ForegroundColor White
Write-Host "💾 Vector Database: $($Config.VectorDBPath)" -ForegroundColor White
Write-Host "`n"

if (-not (Test-Path `$DocsPath)) {
    Write-Host "✗ Error: Directory not found: `$DocsPath" -ForegroundColor Red
    Write-Host "`nCreate the directory and add documents, then run this script again." -ForegroundColor Yellow
    exit 1
}

`$fileCount = (Get-ChildItem -Path `$DocsPath -File -Recurse).Count

if (`$fileCount -eq 0) {
    Write-Host "✗ No files found in: `$DocsPath" -ForegroundColor Red
    Write-Host "`nAdd some documents (.txt, .md, .py, etc.) and run this script again." -ForegroundColor Yellow
    exit 1
}

Write-Host "Found `$fileCount files in `$DocsPath" -ForegroundColor Green
Write-Host "`nProcessing documents (this may take a few minutes)...`n" -ForegroundColor Cyan

# Run the RAG processor
python "$($Config.VectorDBPath)\rag_processor.py" "`$DocsPath"

if (`$LASTEXITCODE -eq 0) {
    Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║          ✓ DOCUMENTS PROCESSED SUCCESSFULLY                    ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

    Write-Host "Your documents are now available for RAG queries!" -ForegroundColor White
    Write-Host "`nTo search your documents:" -ForegroundColor Cyan
    Write-Host "  python ``"$($Config.VectorDBPath)\rag_processor.py``" search ``"your query here``"`n" -ForegroundColor Yellow
} else {
    Write-Host "`n✗ Error processing documents" -ForegroundColor Red
    Write-Host "Check the error messages above for details.`n" -ForegroundColor Yellow
    exit 1
}
"@

    $agentsPath = Join-Path $ScriptRoot "agents"
    if (-not (Test-Path $agentsPath)) {
        New-Item -ItemType Directory -Path $agentsPath -Force | Out-Null
    }

    $scriptPath = Join-Path $agentsPath "Ingest-Documents.ps1"
    Set-Content -Path $scriptPath -Value $script -Force
    Write-Log "Created: $scriptPath" -Level SUCCESS
}

function New-ChatSummarizationScript {
    <#
    .SYNOPSIS
        Creates the chat summarization script in the agents folder
    #>
    param(
        [PSCustomObject]$Config,
        [string]$ScriptRoot
    )

    $script = @"
<#
.SYNOPSIS
    Summarize chat conversations using local LLM

.DESCRIPTION
    Analyzes chat conversations and provides summaries including:
    - Main topics discussed
    - Key decisions made
    - Action items identified
    - Important questions raised

    All processing happens locally via Ollama - NO internet required

.PARAMETER ChatFile
    Path to the chat file to summarize (text file)

.PARAMETER OutputFile
    Optional path to save the summary

.EXAMPLE
    .\Summarize-Chat.ps1 -ChatFile "chat.txt"
    .\Summarize-Chat.ps1 -ChatFile "chat.txt" -OutputFile "summary.txt"

.NOTES
    - Uses local LLM: $($Config.ModelName)
    - 100% offline operation
#>

param(
    [Parameter(Mandatory=`$true)]
    [string]`$ChatFile,

    [string]`$OutputFile = ""
)

Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          CHAT SUMMARIZATION - 100% OFFLINE                     ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Validate input file
if (-not (Test-Path `$ChatFile)) {
    Write-Host "✗ Error: Chat file not found: `$ChatFile" -ForegroundColor Red
    exit 1
}

`$fileSize = (Get-Item `$ChatFile).Length / 1KB
Write-Host "📄 Chat File:  `$ChatFile (`$([Math]::Round(`$fileSize, 2)) KB)" -ForegroundColor White
Write-Host "🤖 Model:      $($Config.ModelName)" -ForegroundColor White
Write-Host "🌐 API:        http://localhost:$($Config.OllamaPort) (local)`n" -ForegroundColor White

# Read chat content
`$chatContent = Get-Content `$ChatFile -Raw

if (`$chatContent.Length -eq 0) {
    Write-Host "✗ Error: Chat file is empty" -ForegroundColor Red
    exit 1
}

# Prepare prompt for summarization
`$prompt = @"
Analyze this chat conversation and provide a comprehensive summary:

## Instructions:
1. Identify and list the main topics discussed (bullet points)
2. Extract key decisions that were made
3. List any action items or tasks mentioned
4. Note important questions that were raised or need answers

## Chat Conversation:
---
`$chatContent
---

## Summary:
"@

# Prepare API request
`$body = @{
    model = "$($Config.ModelName)"
    prompt = `$prompt
    stream = `$false
    options = @{
        temperature = 0.3
        num_predict = 2000
    }
} | ConvertTo-Json

Write-Host "Generating summary using local LLM..." -ForegroundColor Cyan
Write-Host "(This may take 30-60 seconds depending on chat length)`n" -ForegroundColor Yellow

try {
    # Call local Ollama API
    `$response = Invoke-RestMethod ``
        -Uri "http://localhost:$($Config.OllamaPort)/api/generate" ``
        -Method Post ``
        -Body `$body ``
        -ContentType "application/json" ``
        -TimeoutSec 300

    `$summary = `$response.response

    # Display summary
    Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                        SUMMARY                                  ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

    Write-Host `$summary -ForegroundColor White

    Write-Host "`n╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

    # Save to file if requested
    if (`$OutputFile) {
        `$fullSummary = @"
CHAT SUMMARY
Generated: `$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Source: `$ChatFile
Model: $($Config.ModelName)

`$summary
"@

        `$fullSummary | Out-File `$OutputFile -Encoding UTF8
        Write-Host "✓ Summary saved to: `$OutputFile" -ForegroundColor Green
    }

    Write-Host "`n✓ Summarization completed successfully`n" -ForegroundColor Green

} catch {
    Write-Host "`n✗ Error generating summary:" -ForegroundColor Red
    Write-Host `$_.Exception.Message -ForegroundColor Red

    Write-Host "`nTroubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Verify Ollama is running: nerdctl ps --filter ``"name=ollama``"" -ForegroundColor Yellow
    Write-Host "  2. Test Ollama API: Invoke-RestMethod ``"http://localhost:$($Config.OllamaPort)/api/tags``"" -ForegroundColor Yellow
    Write-Host "  3. Check logs in: $($Config.LogPath)`n" -ForegroundColor Yellow

    exit 1
}
"@

    $agentsPath = Join-Path $ScriptRoot "agents"
    if (-not (Test-Path $agentsPath)) {
        New-Item -ItemType Directory -Path $agentsPath -Force | Out-Null
    }

    $scriptPath = Join-Path $agentsPath "Summarize-Chat.ps1"
    Set-Content -Path $scriptPath -Value $script -Force
    Write-Log "Created: $scriptPath" -Level SUCCESS
}

Export-ModuleMember -Function @(
    'Initialize-RAGSystem',
    'New-DocumentIngestionScript',
    'New-ChatSummarizationScript'
)