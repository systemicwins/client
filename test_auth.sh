#!/bin/bash

echo "Testing authentication with demo credentials..."
echo ""

# Test login endpoint
echo "Testing POST https://api.relentless.market/auth/login"
curl -X POST https://api.relentless.market/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo"}' \
  -s | python3 -m json.tool

echo ""
echo "Authentication test complete!"