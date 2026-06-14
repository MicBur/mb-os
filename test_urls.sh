#!/bin/bash
# Test various Antigravity download URLs
URLS=(
  "https://storage.googleapis.com/antigravity-public/Antigravity-2.0.11-x86_64.tar.gz"
  "https://storage.googleapis.com/antigravity-public/Antigravity-2.0.11-linux-x64.tar.gz"
  "https://storage.googleapis.com/antigravity-public/antigravity-linux-x64.tar.gz"
  "https://storage.googleapis.com/antigravity-public/Antigravity-linux-x64.tar.gz"
  "https://storage.googleapis.com/antigravity-public/desktop/Antigravity-2.0.11-x86_64.tar.gz"
  "https://storage.googleapis.com/antigravity-public/releases/Antigravity-2.0.11-x86_64.tar.gz"
  "https://storage.googleapis.com/antigravity-public/latest/Antigravity-linux-x64.tar.gz"
  "https://storage.googleapis.com/antigravity-desktop/Antigravity-linux-x64.tar.gz"
  "https://storage.googleapis.com/antigravity-releases/Antigravity-linux-x64.tar.gz"
)

for url in "${URLS[@]}"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
  echo "$code $url"
done
