#!/bin/bash

echo "Testing fixed app..."

(
    echo "health"
    sleep 1
    
    echo "show"
    echo "🔴 Red circle should be visible now - check your screen!"
    sleep 10
    
    echo "hide"
    sleep 1
    
) | ../.build/release/TranscriptionIndicator

echo "Test complete"