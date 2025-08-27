#!/bin/bash
# Setup script for fine-tuning SEC-BERT on olympus host

echo "🚀 Setting up SEC-BERT fine-tuning on olympus"
echo "============================================="

# Check if we have GPU available
echo -e "\n📊 Checking system capabilities..."
ssh olympus "nvidia-smi --query-gpu=name,memory.total --format=csv 2>/dev/null || echo 'No NVIDIA GPU detected, will use CPU'"

# Setup Python environment
echo -e "\n🐍 Setting up Python environment..."
ssh olympus << 'EOF'
cd ~/relentless/finetune

# Create virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate and install dependencies
source venv/bin/activate

echo "Installing dependencies..."
pip install --upgrade pip
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
pip install transformers>=4.30.0
pip install coremltools>=6.0
pip install scikit-learn pandas numpy tqdm
pip install yfinance requests

echo "✅ Python environment ready"
EOF

echo -e "\n📋 Environment setup complete on olympus"