#!/bin/bash
# Setup Python virtual environment on olympus for SEC-BERT fine-tuning

echo "🚀 Setting up Python environment on olympus"
echo "=========================================="

ssh olympus << 'EOF'
cd ~/relentless/finetune

# Check if python3-full is installed
if ! dpkg -l | grep -q python3-full; then
    echo "⚠️  python3-full not installed. Please run:"
    echo "    sudo apt update && sudo apt install python3-full"
    echo ""
fi

# Try to create venv with python3-full if available
if command -v python3 &> /dev/null; then
    echo "Creating virtual environment..."
    python3 -m venv venv --system-site-packages 2>/dev/null || {
        echo "Failed to create venv. Trying with python3-venv..."
        # Try installing venv module
        sudo apt install -y python3-venv 2>/dev/null || {
            echo "Cannot install python3-venv. Requires sudo access."
            echo "Using pipx as alternative..."
            
            # Use pipx as alternative
            if ! command -v pipx &> /dev/null; then
                python3 -m pip install --user pipx
                export PATH="$PATH:$HOME/.local/bin"
            fi
            
            echo "Creating isolated environment with pipx..."
            mkdir -p ~/relentless/finetune/venv_alt
            cd ~/relentless/finetune
            
            # Install packages in user space with --break-system-packages flag
            echo "Installing packages in user space..."
            python3 -m pip install --user --break-system-packages torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.2
            python3 -m pip install --user --break-system-packages transformers scikit-learn pandas numpy tqdm yfinance requests
            
            # Create activation script
            cat > activate_user.sh << 'ACTIVATE'
#!/bin/bash
export PATH="$HOME/.local/bin:$PATH"
export PYTHONPATH="$HOME/.local/lib/python$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')/site-packages:$PYTHONPATH"
export HIP_VISIBLE_DEVICES=0
export HSA_OVERRIDE_GFX_VERSION=11.0.0
echo "User environment activated"
echo "Python: $(which python3)"
echo "Packages: ~/.local/lib/python*/site-packages"
ACTIVATE
            chmod +x activate_user.sh
            
            echo ""
            echo "✅ User-space environment ready!"
            echo "To use: source ~/relentless/finetune/activate_user.sh"
            exit 0
        }
        python3 -m venv venv --system-site-packages
    }
    
    source venv/bin/activate
    
    echo "Installing PyTorch with ROCm support..."
    pip install --upgrade pip
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.2
    
    echo "Installing other dependencies..."
    pip install transformers scikit-learn pandas numpy tqdm yfinance requests
    
    echo "✅ Virtual environment ready!"
    echo "To activate: source ~/relentless/finetune/venv/bin/activate"
fi

# Test GPU access
echo -e "\n🧪 Testing PyTorch with AMD GPU..."
source venv/bin/activate 2>/dev/null || source activate_user.sh 2>/dev/null
python3 -c "
import torch
print(f'PyTorch version: {torch.__version__}')
print(f'CUDA/ROCm available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'Device count: {torch.cuda.device_count()}')
    for i in range(torch.cuda.device_count()):
        print(f'Device {i}: {torch.cuda.get_device_name(i)}')
    print('GPU memory:', torch.cuda.get_device_properties(0).total_memory / 1024**3, 'GB')
else:
    print('Will use CPU for training')
"
EOF