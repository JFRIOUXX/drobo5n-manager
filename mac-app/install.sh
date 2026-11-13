#!/bin/sh
# Compile DroboMenuBar, l'installe dans ~/Applications et la lance à chaque
# ouverture de session (LaunchAgent). À relancer après toute modification du code.
#
#   ./install.sh            compile, installe, démarre
#   ./install.sh uninstall  arrête l'app et retire le LaunchAgent et le bundle
set -eu
cd "$(dirname "$0")"

APP="$HOME/Applications/DroboMenuBar.app"
LABEL="com.jf.drobo5n-manager"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
LOG="/tmp/drobo-menubar.log"

stop_app() {
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    pkill -x DroboMenuBar 2>/dev/null || true
}

if [ "${1:-}" = "uninstall" ]; then
    stop_app
    rm -f "$PLIST"
    rm -rf "$APP"
    echo "DroboMenuBar removed. (Its Keychain item, if any, is left in place.)"
    exit 0
fi

echo "==> Building"
swift build -c release

echo "==> Bundling"
mkdir -p dist/DroboMenuBar.app/Contents/MacOS
cp .build/release/DroboMenuBar dist/DroboMenuBar.app/Contents/MacOS/DroboMenuBar
# Signature ad hoc : pas besoin de compte développeur Apple.
codesign --force --deep --sign - dist/DroboMenuBar.app

echo "==> Installing to $APP"
stop_app
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$APP"
ditto dist/DroboMenuBar.app "$APP"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$APP/Contents/MacOS/DroboMenuBar</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>ProcessType</key>
	<string>Interactive</string>
	<key>StandardOutPath</key>
	<string>$LOG</string>
	<key>StandardErrorPath</key>
	<string>$LOG</string>
</dict>
</plist>
EOF

echo "==> Starting"
launchctl bootstrap "$DOMAIN" "$PLIST"
# Juste après le remplacement du bundle, macOS refuse souvent le premier
# démarrage par launchd (OS_REASON_CODESIGNING) ; le suivant passe.
attempt=1
while [ "$attempt" -le 4 ]; do
    sleep 3
    if pgrep -x DroboMenuBar >/dev/null; then
        echo "DroboMenuBar is running. Look for the dot and \"DR\" in the menu bar."
        echo "Log: $LOG"
        exit 0
    fi
    launchctl kickstart "$DOMAIN/$LABEL" 2>/dev/null || true
    attempt=$((attempt + 1))
done

echo "DroboMenuBar did not start. Check:" >&2
echo "  launchctl print $DOMAIN/$LABEL | grep -E 'state|last exit'" >&2
exit 1
