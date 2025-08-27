#!/bin/bash

# Script to run SEC-BERT API server
echo "=========================================="
echo "SEC-BERT Health Analysis Server"
echo "=========================================="

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed"
    exit 1
fi

# Check if model exists
if [ ! -f "models/secbert_russell2000_actual.pth" ]; then
    echo "Error: Fine-tuned model not found at models/secbert_russell2000_actual.pth"
    echo "Please ensure the model has been transferred from the training server"
    exit 1
fi

# Install required packages if needed
echo "Checking dependencies..."
pip3 install -q flask flask-cors torch transformers 2>/dev/null

# Start the server
echo ""
echo "Starting SEC-BERT API server..."
echo "The server will be available at http://localhost:8000"
echo ""
echo "API Endpoints:"
echo "  POST /analyze       - Analyze single text"
echo "  POST /batch_analyze - Analyze multiple texts"
echo "  GET  /health       - Health check"
echo ""
echo "Press Ctrl+C to stop the server"
echo "=========================================="

# Run the server
python3 secbert_api_server.py