# SEC-BERT Fine-Tuning for Russell 2000 Health Scoring

## Overview
This system fine-tunes SEC-BERT on Russell 2000 company SEC filings to predict company health scores (0-100%) using machine learning instead of keyword matching.

## Architecture

```
SEC Filing Text → SEC-BERT (Fine-tuned) → Health Score (0-100%)
                        ↑
                Russell 2000 Training Data
```

## Training Data

The model is trained on:
- **Russell 2000 sector leaders**: Top performing small-cap companies
- **Health scores**: Based on actual financial performance and stock returns
- **SEC filing patterns**: Real language from 10-K, 10-Q, and 8-K filings

### Score Distribution
- **85-100%**: Exceptional companies (WING, TXRH, KRYS, SMCI)
- **70-85%**: Strong performers (INSM, COHR, AAON)
- **55-70%**: Good/Average companies (GBCI, MIDD)
- **40-55%**: Fair performers
- **Below 40%**: Struggling companies

## Setup Instructions

### 1. Install Dependencies
```bash
pip install torch transformers coremltools scikit-learn pandas yfinance tqdm
```

### 2. Collect Training Data
```bash
python collect_russell2000_training_data.py
```
This creates `russell2000_training_data.json` with labeled examples.

### 3. Fine-tune the Model
```bash
python finetune_secbert_russell2000.py
```
This will:
- Load SEC-BERT base model
- Fine-tune on Russell 2000 patterns
- Convert to CoreML format
- Output: `SECBERT_Russell2000_Health.mlmodel`

### 4. Deploy the Model
```bash
# Move model to the app
mv SECBERT_Russell2000_Health.mlmodel Sources/TradingPlatform/Models/
mv secbert_health_vocab.json Sources/TradingPlatform/Resources/
mv secbert_health_special_tokens.json Sources/TradingPlatform/Resources/
```

### 5. Update Package.swift
Add the new model to resources:
```swift
resources: [
    .process("Resources"),
    .process("Models/SECBERT_Russell2000_Health.mlmodel")
]
```

## How It Works

### Training Process
1. **Data Collection**: Gather SEC filing excerpts from Russell 2000 companies
2. **Labeling**: Assign health scores based on:
   - Stock performance (6-month returns)
   - Market capitalization
   - Sector performance
   - Volatility metrics
3. **Fine-tuning**: Train SEC-BERT to predict scores using MSE loss
4. **Validation**: Test on held-out companies

### Model Architecture
```python
SEC-BERT Base (768 dims)
    ↓
Dropout (0.1)
    ↓
Linear (768 → 256)
    ↓
ReLU + Dropout
    ↓
Linear (256 → 64)
    ↓
ReLU + Dropout
    ↓
Linear (64 → 1)
    ↓
Sigmoid (0-1 range)
    ↓
Scale to 0-100%
```

### Inference Pipeline
1. **Text Input**: SEC filing text (MD&A, Risk Factors, etc.)
2. **Tokenization**: Convert to BERT tokens (max 512)
3. **Model Inference**: Neural network prediction
4. **Score Output**: 0-100% health score
5. **Confidence**: Based on prediction decisiveness

## Performance Metrics

Expected performance after fine-tuning:
- **MAE**: ~5-8% (Mean Absolute Error)
- **Correlation**: 0.7-0.8 with actual stock performance
- **Inference Speed**: ~100ms per filing on CPU

## Integration with App

The fine-tuned model integrates seamlessly:

```swift
// In SECBERTService
let healthModel = SECBERTHealthModel()
let assessment = healthModel.analyzeFilingHealth(
    filingText: combinedSECText,
    symbol: "WING"
)

print("Health Score: \(assessment.score)%")
print("Method: \(assessment.method)") // .machineLearning or .keywordBased
```

## Advantages Over Keyword Matching

1. **Context Understanding**: ML model understands context, not just keywords
2. **Nuanced Scoring**: Captures subtle language patterns
3. **Sector Awareness**: Learns sector-specific language
4. **Continuous Learning**: Can be retrained with new data
5. **Russell 2000 Calibrated**: Specifically trained on successful small-caps

## Fallback Strategy

If the ML model is not available, the system automatically falls back to keyword-based scoring:
- Check for model file existence
- Attempt loading and compilation
- If fails, use `CompanyHealthScorer` (keyword-based)
- Log the scoring method used

## Updating the Model

To retrain with new data:
1. Update `RUSSELL_2000_TRAINING_SET` with new companies
2. Collect recent SEC filings
3. Re-run the fine-tuning pipeline
4. Deploy the updated model

## Testing

Test the fine-tuned model:
```bash
# In Python
python -c "
from finetune_secbert_russell2000 import test_model
model, tokenizer = load_model('SECBERT_Russell2000_Health.mlmodel')
test_model(model, tokenizer)
"
```

## Performance Optimization

For faster inference:
1. **Batch Processing**: Process multiple filings together
2. **Text Chunking**: Split long filings into chunks
3. **Caching**: Cache tokenization results
4. **GPU Acceleration**: Use Metal Performance Shaders on M1/M2

## Monitoring

Track model performance in production:
- Log prediction scores and confidence
- Compare with actual stock performance
- Identify drift or degradation
- Retrain periodically with new data