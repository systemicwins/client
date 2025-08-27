#!/bin/bash
# Setup script for fine-tuning SEC-BERT on olympus host with AMD GPU (ROCm)

echo "🚀 Setting up SEC-BERT fine-tuning on olympus with AMD GPU support"
echo "======================================================"

# Check AMD GPU availability
echo -e "\n📊 Checking AMD GPU capabilities..."
ssh olympus << 'EOF'
echo "GPU Hardware:"
lspci | grep -i "vga\|3d\|display" || echo "No GPU detected"

# Check ROCm installation
echo -e "\nROCm Status:"
if command -v rocm-smi &> /dev/null; then
    rocm-smi --showproductname 2>/dev/null || echo "ROCm installed but GPU not accessible"
else
    echo "ROCm not installed or not in PATH"
fi

# Check if we can use system Python with pip
echo -e "\nPython Environment:"
python3 --version

# Try to use pip with --user flag instead of venv
echo -e "\nInstalling packages with --user flag (no venv needed)..."

# Install PyTorch with ROCm support
echo "Installing PyTorch with ROCm support..."
python3 -m pip install --user --upgrade pip

# For AMD GPUs, we need PyTorch with ROCm support
# ROCm 5.7 is common, adjust version as needed
python3 -m pip install --user torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm5.7

# Install other dependencies
echo "Installing ML dependencies..."
python3 -m pip install --user transformers>=4.30.0
python3 -m pip install --user scikit-learn pandas numpy tqdm
python3 -m pip install --user yfinance requests

# Note: coremltools doesn't work on Linux, we'll handle conversion locally
echo -e "\n⚠️  Note: CoreML conversion will be done on macOS after training"

# Test PyTorch with AMD GPU
echo -e "\n🧪 Testing PyTorch with AMD GPU..."
python3 -c "
import torch
print(f'PyTorch version: {torch.__version__}')
print(f'ROCm/HIP available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'Device count: {torch.cuda.device_count()}')
    for i in range(torch.cuda.device_count()):
        print(f'Device {i}: {torch.cuda.get_device_name(i)}')
else:
    print('No ROCm/HIP support detected, will use CPU')
"

echo -e "\n✅ Setup complete!"
EOF