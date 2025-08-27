#!/bin/bash

# Run the trading platform in production mode
# This will connect to the production API at api.relentless.market

echo "Starting Trading Platform in Production Mode..."
echo "Connecting to: https://api.relentless.market"
echo "Please login with your credentials"
echo ""

# Set environment variable and run the application
TRADER_ENV=production swift run TradingPlatform