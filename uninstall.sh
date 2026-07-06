#!/bin/zsh
set -euo pipefail
LABEL="com.caixinyun.thermal-fan-guard"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
AGENT="$LABEL-menubar"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT.plist"

launchctl bootout "gui/$UID" "$AGENT_PLIST" 2>/dev/null || true
rm -f "$AGENT_PLIST"
sudo launchctl bootout system "$PLIST" 2>/dev/null || true
sudo rm -rf "/Applications/Thermal Fan Guard.app"
sudo rm -f "$PLIST" /usr/local/libexec/thermal-fan-guard \
  /Users/Shared/com.caixinyun.thermal-fan-guard.status.json \
  /Users/Shared/com.caixinyun.thermal-fan-guard.history.json \
  /Users/Shared/com.caixinyun.thermal-fan-guard.command.json
echo "Uninstalled; automatic fan control restored on daemon termination."
