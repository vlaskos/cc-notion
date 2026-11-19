#!/bin/bash
for name in com.cc-notion.listener com.cc-notion.ngrok; do
  launchctl bootout "gui/$(id -u)/$name" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$name.plist"
  echo "removed $name"
done
