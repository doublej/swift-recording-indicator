#!/bin/bash
{
  sleep 2
  echo '{"id":"test1","v":1,"command":"show"}'
  while true; do
    sleep 10
    echo '{"id":"ping","v":1,"command":"health"}'
  done
} | ./release/TranscriptionIndicator