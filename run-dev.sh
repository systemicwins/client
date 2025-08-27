#!/bin/bash

# Run the trading platform in development mode
# This will automatically use offline mode without requiring login

echo "Starting Trading Platform in Development Mode..."
echo "Using offline mode - no login required"
echo ""

# Set environment variable and run the application
TRADER_ENV=development swift run TradingPlatform