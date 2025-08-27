#!/bin/bash

# Script to run TradingPlatform with proper bundle resources

BUILD_DIR=".build/arm64-apple-macosx/debug"
APP="TradingPlatform"
BUNDLE="TradingPlatform_TradingPlatform.bundle"

# Check if app exists
if [ ! -f "$BUILD_DIR/$APP" ]; then
    echo "App not found. Building..."
    swift build
fi

# Check if bundle exists
if [ ! -d "$BUILD_DIR/$BUNDLE" ]; then
    echo "Bundle not found at $BUILD_DIR/$BUNDLE"
    exit 1
fi

echo "Starting TradingPlatform..."
echo "Bundle location: $BUILD_DIR/$BUNDLE"
echo ""

# Run from the build directory so bundle paths are correct
cd $BUILD_DIR && ./$APP