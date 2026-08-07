#!/bin/bash
# NATION AGENT — APK Build / Host / Deploy Tool
# Build Android APKs, serve them over HTTP, and deploy via ADB.
#
# Usage: nation-apk.sh <command> [args...]
#
# Commands:
#   new      <name> [package]       Scaffold a minimal Android project
#   build    [project_dir]          Build APK (debug) using gradle or apktool
#   sign     <apk> [keystore]       Sign APK (creates debug key if needed)
#   align    <apk>                  Zipalign APK for Play Store
#   host     <apk_or_dir> [port]    Serve APK over HTTP with install page
#   deploy   <apk> [device_ip]      Build + sign + push + install via ADB
#   info     <apk>                  Show APK info (package, perms, etc.)
#   decompile <apk> [output_dir]    Decompile APK with apktool
#   recompile <dir> [output_apk]    Recompile decompiled APK
#   qr       <url>                  Generate install QR code in terminal
#   deps                            Check/install build dependencies
#
set -euo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

CMD="${1:-help}"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
mkdir -p "$(dirname "$LOG")"
TS=$(date '+%Y-%m-%d %H:%M:%S')
log() { echo "[$TS] [APK] $*" >> "$LOG" 2>/dev/null || true; }
die() { echo "ERROR: $*" >&2; exit 1; }

ADB_TOOL="${NATION_TOOLS:-$HOME/.kiro/tools}/nation-adb.sh"

case "$CMD" in

  new)
    [ -n "${2:-}" ] || die "App name required"
    NAME="$2"
    PACKAGE="${3:-com.nation.$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')}"
    DIR="$PWD/$NAME"
    log "new project: $NAME ($PACKAGE)"
    echo "Creating Android project: $NAME ($PACKAGE)"
    mkdir -p "$DIR/app/src/main/java/$(echo "$PACKAGE" | tr '.' '/')"
    mkdir -p "$DIR/app/src/main/res/layout"
    mkdir -p "$DIR/app/src/main/res/values"

    # settings.gradle
    cat > "$DIR/settings.gradle" << EOF
rootProject.name = '$NAME'
include ':app'
EOF

    # build.gradle (root)
    cat > "$DIR/build.gradle" << EOF
buildscript {
    repositories { google(); mavenCentral() }
    dependencies { classpath 'com.android.tools.build:gradle:8.1.0' }
}
allprojects { repositories { google(); mavenCentral() } }
EOF

    # app/build.gradle
    cat > "$DIR/app/build.gradle" << EOF
apply plugin: 'com.android.application'

android {
    compileSdkVersion 34
    defaultConfig {
        applicationId "$PACKAGE"
        minSdkVersion 21
        targetSdkVersion 34
        versionCode 1
        versionName "1.0"
    }
    buildTypes {
        debug { debuggable true }
        release { minifyEnabled false }
    }
}
dependencies {
    implementation 'androidx.appcompat:appcompat:1.6.1'
}
EOF

    # AndroidManifest.xml
    cat > "$DIR/app/src/main/AndroidManifest.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="$PACKAGE">
    <application
        android:label="$NAME"
        android:theme="@style/AppTheme">
        <activity android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

    # MainActivity.java
    JAVA_PKG_DIR="$DIR/app/src/main/java/$(echo "$PACKAGE" | tr '.' '/')"
    cat > "$JAVA_PKG_DIR/MainActivity.java" << EOF
package $PACKAGE;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView tv = new TextView(this);
        tv.setText("$NAME - Built by NATION AGENT");
        tv.setTextSize(24);
        tv.setPadding(48, 48, 48, 48);
        setContentView(tv);
    }
}
EOF

    # strings.xml
    cat > "$DIR/app/src/main/res/values/strings.xml" << EOF
<resources>
    <string name="app_name">$NAME</string>
</resources>
EOF

    # styles.xml
    cat > "$DIR/app/src/main/res/values/styles.xml" << EOF
<resources>
    <style name="AppTheme" parent="Theme.AppCompat.Light.DarkActionBar"/>
</resources>
EOF

    # gradlew wrapper stub
    cat > "$DIR/gradlew" << 'GRADLEW'
#!/bin/bash
exec gradle "$@"
GRADLEW
    chmod +x "$DIR/gradlew"

    echo ""
    echo "Project created: $DIR"
    echo "Package: $PACKAGE"
    echo ""
    echo "Build with: nation-apk.sh build $DIR"
    echo "Deploy with: nation-apk.sh deploy $DIR/app/build/outputs/apk/debug/app-debug.apk"
    ;;

  build)
    DIR="${2:-.}"
    log "build $DIR"
    [ -d "$DIR" ] || die "Directory not found: $DIR"
    cd "$DIR"

    echo "=== Building APK: $DIR ==="

    if [ -f "gradlew" ] && [ "${NATION_HAS_GRADLE:-0}" = "1" ]; then
        echo "Using: gradle assembleDebug"
        bash gradlew assembleDebug
        APK=$(find . -name "*debug*.apk" | head -1)
    elif command -v gradle &>/dev/null; then
        echo "Using: gradle assembleDebug"
        gradle assembleDebug
        APK=$(find . -name "*debug*.apk" | head -1)
    elif command -v apktool &>/dev/null; then
        echo "Using: apktool"
        apktool b . -o output.apk
        APK="output.apk"
    else
        die "No build tool found. Install gradle: pkg install gradle  OR  apt install gradle"
    fi

    if [ -n "${APK:-}" ] && [ -f "$APK" ]; then
        echo ""
        echo "Build successful: $APK"
        echo "Size: $(du -sh "$APK" | cut -f1)"
    else
        die "Build failed — APK not found"
    fi
    ;;

  sign)
    [ -n "${2:-}" ] || die "APK path required"
    [ -f "$2" ] || die "APK not found: $2"
    APK="$2"
    KEYSTORE="${3:-$HOME/.kiro/build/debug.keystore}"
    log "sign $APK"

    mkdir -p "$(dirname "$KEYSTORE")"

    # Create debug keystore if missing
    if [ ! -f "$KEYSTORE" ]; then
        echo "Creating debug keystore: $KEYSTORE"
        keytool -genkeypair -v \
            -keystore "$KEYSTORE" \
            -alias androiddebugkey \
            -keyalg RSA -keysize 2048 \
            -validity 10000 \
            -storepass android \
            -keypass android \
            -dname "CN=Android Debug, O=Android, C=US" 2>/dev/null || die "keytool not found. Install: pkg install java-jdk"
    fi

    SIGNED="${APK%.apk}-signed.apk"

    if command -v apksigner &>/dev/null; then
        apksigner sign \
            --ks "$KEYSTORE" \
            --ks-key-alias androiddebugkey \
            --ks-pass pass:android \
            --key-pass pass:android \
            --out "$SIGNED" \
            "$APK"
    elif command -v jarsigner &>/dev/null; then
        cp "$APK" "$SIGNED"
        jarsigner -keystore "$KEYSTORE" \
            -storepass android \
            -keypass android \
            "$SIGNED" androiddebugkey
    else
        die "No signing tool found. Install: pkg install android-tools OR pkg install java-jdk"
    fi

    echo "Signed APK: $SIGNED"
    ;;

  align)
    [ -n "${2:-}" ] || die "APK path required"
    [ -f "$2" ] || die "APK not found: $2"
    APK="$2"
    ALIGNED="${APK%.apk}-aligned.apk"
    log "align $APK"
    command -v zipalign &>/dev/null || die "zipalign not found. Install: pkg install android-tools"
    zipalign -v 4 "$APK" "$ALIGNED"
    echo "Aligned APK: $ALIGNED"
    ;;

  host)
    [ -n "${2:-}" ] || die "APK path or directory required"
    TARGET="$2"
    PORT="${3:-8080}"
    log "host $TARGET on :$PORT"

    # Gather APKs to serve
    if [ -d "$TARGET" ]; then
        APK_DIR="$TARGET"
    else
        APK_DIR=$(dirname "$TARGET")
    fi

    echo "Hosting APKs from: $APK_DIR on port $PORT"
    echo "Install URL: http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo localhost):$PORT"
    echo "Press Ctrl+C to stop."

    python3 - "$APK_DIR" "$PORT" << 'PYEOF'
import sys, os, http.server, urllib.parse, datetime

apk_dir = os.path.abspath(sys.argv[1])
port = int(sys.argv[2])

class APKHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        ts = datetime.datetime.now().strftime("%H:%M:%S")
        print(f"[{ts}] {fmt % args}")

    def do_GET(self):
        path = urllib.parse.unquote(self.path.lstrip('/'))

        if path == '' or path == '/':
            # List APKs with install buttons
            apks = [f for f in os.listdir(apk_dir) if f.endswith('.apk')]
            html = f"""<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>NATION AGENT APK Server</title>
<style>
  body{{font-family:monospace;background:#0d1117;color:#c9d1d9;padding:20px;max-width:600px;margin:0 auto}}
  h1{{color:#58a6ff;border-bottom:1px solid #30363d;padding-bottom:10px}}
  .apk{{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:16px;margin:12px 0}}
  .apk h3{{color:#e3b341;margin:0 0 8px 0}}
  a.btn{{display:inline-block;background:#238636;color:#fff;padding:8px 16px;border-radius:6px;text-decoration:none;margin:4px 4px 4px 0}}
  a.btn:hover{{background:#2ea043}}
  .size{{color:#8b949e;font-size:12px}}
  footer{{color:#8b949e;font-size:11px;margin-top:30px;border-top:1px solid #30363d;padding-top:10px}}
</style>
</head><body>
<h1>⚡ NATION AGENT APK Server</h1>
<p>Serving from: <code>{apk_dir}</code></p>
"""
            if apks:
                for apk in sorted(apks):
                    size = os.path.getsize(os.path.join(apk_dir, apk))
                    size_str = f"{size/1024/1024:.1f} MB" if size > 1024*1024 else f"{size/1024:.0f} KB"
                    html += f"""<div class="apk">
  <h3>📦 {apk}</h3>
  <span class="size">{size_str}</span><br><br>
  <a class="btn" href="/{urllib.parse.quote(apk)}">⬇ Download</a>
  <a class="btn" href="intent:{urllib.parse.quote(apk)}#Intent;scheme=http;end">📱 Install (Android)</a>
</div>"""
            else:
                html += "<p>No APK files found.</p>"
            html += f"""<footer>NATION AGENT v3 · {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</footer>
</body></html>"""
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(html.encode())
        else:
            # Serve APK file
            apk_path = os.path.join(apk_dir, path)
            if os.path.isfile(apk_path) and apk_path.endswith('.apk'):
                self.send_response(200)
                self.send_header('Content-Type', 'application/vnd.android.package-archive')
                self.send_header('Content-Disposition', f'attachment; filename="{path}"')
                self.send_header('Content-Length', os.path.getsize(apk_path))
                self.end_headers()
                with open(apk_path, 'rb') as f:
                    self.wfile.write(f.read())
            else:
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b'Not found')

server = http.server.HTTPServer(('0.0.0.0', port), APKHandler)
print(f"APK server running at http://0.0.0.0:{port}")
server.serve_forever()
PYEOF
    ;;

  deploy)
    [ -n "${2:-}" ] || die "APK path required"
    [ -f "$2" ] || die "APK not found: $2"
    APK="$2"
    DEVICE="${3:-}"
    log "deploy $APK to ${DEVICE:-default device}"

    echo "=== NATION AGENT APK Deploy ==="
    echo "APK: $APK"

    # Connect to device if IP provided
    if [ -n "$DEVICE" ]; then
        "$ADB_TOOL" wifi "$DEVICE" 2>/dev/null || true
        sleep 1
    fi

    # Check device connected
    if [ -x "$ADB_TOOL" ]; then
        echo ""
        echo "Device:"
        "$ADB_TOOL" devices
        echo ""
        echo "Installing APK..."
        "$ADB_TOOL" install "$APK"
        echo ""
        echo "Deploy complete!"
    else
        die "ADB tool not found: $ADB_TOOL"
    fi
    ;;

  info)
    [ -n "${2:-}" ] || die "APK path required"
    [ -f "$2" ] || die "APK not found: $2"
    APK="$2"
    log "info $APK"
    echo "=== APK Info: $(basename "$APK") ==="
    echo "Size   : $(du -sh "$APK" | cut -f1)"

    if command -v aapt &>/dev/null; then
        echo "--- aapt dump ---"
        aapt dump badging "$APK" 2>/dev/null | grep -E "package:|activity:|uses-permission:" | head -20
    elif command -v aapt2 &>/dev/null; then
        aapt2 dump badging "$APK" 2>/dev/null | head -20
    else
        echo "(aapt not installed — install: pkg install aapt)"
        echo "MD5 : $(md5sum "$APK" 2>/dev/null | cut -d' ' -f1)"
        python3 -c "
import zipfile, sys
with zipfile.ZipFile(sys.argv[1]) as z:
    files = z.namelist()
    print('Files:', len(files))
    manifest = [f for f in files if 'AndroidManifest' in f]
    print('Manifest:', manifest)
    classes = [f for f in files if f.endswith('.dex')]
    print('DEX files:', classes)
" "$APK"
    fi
    ;;

  decompile)
    [ -n "${2:-}" ] || die "APK path required"
    [ -f "$2" ] || die "APK not found: $2"
    APK="$2"
    OUTDIR="${3:-${APK%.apk}-decompiled}"
    log "decompile $APK -> $OUTDIR"
    command -v apktool &>/dev/null || die "apktool not found. Install: pkg install apktool"
    apktool d "$APK" -o "$OUTDIR"
    echo "Decompiled to: $OUTDIR"
    ;;

  recompile)
    [ -n "${2:-}" ] || die "Decompiled directory required"
    [ -d "$2" ] || die "Directory not found: $2"
    DIR="$2"
    OUTPUT="${3:-${DIR}-recompiled.apk}"
    log "recompile $DIR -> $OUTPUT"
    command -v apktool &>/dev/null || die "apktool not found. Install: pkg install apktool"
    apktool b "$DIR" -o "$OUTPUT"
    echo "Recompiled: $OUTPUT"
    ;;

  qr)
    [ -n "${2:-}" ] || die "URL required"
    URL="$2"
    log "qr $URL"
    python3 - "$URL" << 'PYEOF'
import sys, urllib.parse

url = sys.argv[1]
# Use qrenco.de terminal QR service
encoded = urllib.parse.quote(url, safe='')
import subprocess, urllib.request
try:
    with urllib.request.urlopen(f"https://qrenco.de/{encoded}", timeout=10) as r:
        print(r.read().decode())
except Exception:
    print(f"QR service unavailable. URL: {url}")
    print("Install qrencode: pkg install qrencode")
    print(f"Then run: qrencode -t ANSIUTF8 '{url}'")
PYEOF
    ;;

  deps)
    log "check deps"
    echo "=== APK Build Dependencies ==="
    for tool in gradle java keytool adb aapt apktool zipalign; do
        if command -v "$tool" &>/dev/null; then
            VER=$({ "$tool" --version 2>&1 || "$tool" version 2>&1; } | head -1 | cut -c1-50)
            echo "  ✓ $tool — $VER"
        else
            echo "  ✗ $tool — not found"
            case "$tool" in
                gradle)    echo "    Install: pkg install gradle  OR  apt install gradle" ;;
                java|keytool) echo "    Install: pkg install openjdk-17" ;;
                adb)       echo "    Install: pkg install android-tools  OR: nation-adb.sh install-tools" ;;
                aapt)      echo "    Install: pkg install aapt" ;;
                apktool)   echo "    Install: pkg install apktool" ;;
                zipalign)  echo "    Install: pkg install android-tools" ;;
            esac
        fi
    done
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *)
    die "Unknown command: $CMD. Run: nation-apk.sh help"
    ;;
esac
