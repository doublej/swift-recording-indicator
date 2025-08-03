#!/bin/bash

echo "Testing fixed app..."

(
    echo "health"
    sleep 1
    
    echo "show"
    sleep 5
    
    echo "hide"
    sleep 1
    
) | ../.build/release/TranscriptionIndicator

echo "Test complete"