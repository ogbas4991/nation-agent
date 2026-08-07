#!/bin/bash
# NATION AGENT — APK App Wrapper
# Packages the web dashboard as an Android WebView APK.
# Usage: nation-apk-app.sh [build|deploy|clean|help]
set -euo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

CMD="${1:-build}"
TOOLS="${NATION_TOOLS:-$HOME/.kiro/tools}"
BUILD_DIR="${NATION_DIR:-$HOME/.kiro}/build/nation-app"
APK_OUT="${NATION_DIR:-$HOME/.kiro}/build/nation-agent.apk"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
mkdir -p "$BUILD_DIR" "$(dirname "$LOG")"
TS=$(date '+%Y-%m-%d %H:%M:%S')
log() { echo "[$TS] [APK-APP] $*" >> "$LOG" 2>/dev/null || true; }
die() { echo "ERROR: $*" >&2; exit 1; }

scaffold_project() {
    mkdir -p "$BUILD_DIR/app/src/main/java/com/nation/agent"
    mkdir -p "$BUILD_DIR/app/src/main/res/values"

    cat > "$BUILD_DIR/settings.gradle" << 'EOF'
rootProject.name = 'nation-app'
include ':app'
EOF

    cat > "$BUILD_DIR/build.gradle" << 'EOF'
buildscript {
    repositories { google(); mavenCentral() }
    dependencies { classpath 'com.android.tools.build:gradle:8.1.0' }
}
allprojects { repositories { google(); mavenCentral() } }
EOF

    cat > "$BUILD_DIR/app/build.gradle" << 'EOF'
apply plugin: 'com.android.application'
android {
    compileSdkVersion 34
    defaultConfig {
        applicationId "com.nation.agent"
        minSdkVersion 21
        targetSdkVersion 34
        versionCode 1
        versionName "3.0"
    }
    buildTypes { debug { debuggable true } }
}
dependencies { implementation 'androidx.appcompat:appcompat:1.6.1' }
EOF

    cat > "$BUILD_DIR/app/src/main/AndroidManifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.nation.agent">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <application
        android:label="NATION AGENT"
        android:theme="@style/AppTheme"
        android:usesCleartextTraffic="true"
        android:hardwareAccelerated="true">
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

    cat > "$BUILD_DIR/app/src/main/java/com/nation/agent/MainActivity.java" << 'EOF'
package com.nation.agent;
import android.app.Activity;
import android.os.Bundle;
import android.webkit.*;
import android.view.Window;
public class MainActivity extends Activity {
    WebView webView;
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().requestFeature(Window.FEATURE_NO_TITLE);
        webView = new WebView(this);
        webView.getSettings().setJavaScriptEnabled(true);
        webView.getSettings().setDomStorageEnabled(true);
        webView.getSettings().setUseWideViewPort(true);
        webView.getSettings().setLoadWithOverviewMode(true);
        webView.getSettings().setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onReceivedError(WebView v, int code, String desc, String url) {
                v.loadData("<html><body style='background:#0d1117;color:#c9d1d9;font-family:monospace;padding:40px'>"
                    +"<h2 style='color:#e3b341'>⚡ NATION AGENT</h2>"
                    +"<p>Dashboard offline. Start it:</p>"
                    +"<code style='color:#58a6ff'>papy web</code><br><br>"
                    +"<button onclick='location.reload()' style='background:#238636;color:#fff;border:none;"
                    +"padding:8px 16px;border-radius:4px;cursor:pointer'>Retry</button>"
                    +"</body></html>","text/html","utf-8");
            }
        });
        setContentView(webView);
        webView.loadUrl("http://localhost:7070");
    }
    @Override public void onBackPressed() {
        if (webView.canGoBack()) webView.goBack(); else super.onBackPressed();
    }
}
EOF

    cat > "$BUILD_DIR/app/src/main/res/values/styles.xml" << 'EOF'
<resources>
    <style name="AppTheme" parent="Theme.AppCompat.NoActionBar"/>
</resources>
EOF
}

case "$CMD" in
  build)
    log "build"
    echo "=== NATION AGENT APK Build ==="
    "$TOOLS/nation-apk.sh" deps
    echo ""
    if [ ! -d "$BUILD_DIR/app" ]; then
        echo "Scaffolding project..."
        scaffold_project
    fi
    echo "Building..."
    "$TOOLS/nation-apk.sh" build "$BUILD_DIR"
    APK=$(find "$BUILD_DIR" -name "*debug*.apk" 2>/dev/null | head -1 || true)
    if [ -n "$APK" ] && [ -f "$APK" ]; then
        cp "$APK" "$APK_OUT"
        echo "APK: $APK_OUT ($(du -sh "$APK_OUT" | cut -f1))"
        echo "Deploy:  papy apk deploy $APK_OUT"
        echo "Host:    papy apk host $APK_OUT 8080"
    else
        die "Build failed. Install gradle: pkg install gradle"
    fi
    ;;
  deploy)
    [ -f "$APK_OUT" ] || die "Run build first"
    "$TOOLS/nation-apk.sh" deploy "$APK_OUT" "${2:-}"
    ;;
  clean)
    rm -rf "$BUILD_DIR"
    echo "Cleaned: $BUILD_DIR"
    ;;
  help|--help|-h)
    echo "Usage: nation-apk-app.sh [build|deploy [device_ip]|clean]"
    echo "  build          Build NATION AGENT WebView APK"
    echo "  deploy [ip]    Deploy to device via ADB"
    echo "  clean          Remove build directory"
    ;;
  *) die "Unknown command: $CMD" ;;
esac
