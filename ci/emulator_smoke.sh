#!/usr/bin/env bash
# Auto-run smoke test APK rilisan di Android emulator (CI).
# Alur: install -> launch -> tunggu engine init -> cek crash -> 2 screenshot -> cek masih hidup.
# Lulus = EMULATOR_SMOKE_PASS. Screenshot emulator-1.png / emulator-2.png di workspace.
set -euo pipefail

PKG="com.secretarrow.rblox"
APK_DIR="${APK_DIR:-apk}"

echo "== Perangkat =="
adb devices -l
echo "Android: $(adb shell getprop ro.build.version.release | tr -d '\r') (SDK $(adb shell getprop ro.build.version.sdk | tr -d '\r'))"

APK=""
for k in RBlox-x86_64.apk RBlox-universal.apk; do
  if [ -f "$APK_DIR/$k" ]; then APK="$APK_DIR/$k"; break; fi
done
if [ -z "$APK" ]; then
  echo "::error::APK x86_64/universal tidak ditemukan di $APK_DIR"
  ls -la "$APK_DIR" || true
  exit 1
fi
echo "== APK terpilih: $APK =="

echo "== Install =="
if ! adb install -r "$APK"; then
  echo "::error::adb install gagal"
  adb logcat -d | tail -60 || true
  exit 1
fi

echo "== Launch =="
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1

# 1) Tunggu aktivitas game menjadi ResumedActivity (maks ~120 dtk)
BOOT=0
for i in $(seq 1 48); do
  CUR=$(adb shell dumpsys activity activities 2>/dev/null | grep -m1 "ResumedActivity" || true)
  echo "[$i] ${CUR:-<kosong>}"
  if echo "$CUR" | grep -q "$PKG"; then BOOT=1; break; fi
  sleep 2.5
done
if [ "$BOOT" != "1" ]; then
  echo "::error::Aktivitas game tidak pernah menjadi ResumedActivity"
  adb shell dumpsys activity activities 2>/dev/null | head -60 || true
  adb logcat -d 2>/dev/null | tail -120 || true
  exit 1
fi

# 2) Tunggu log inisialisasi engine "Godot Engine v..." (maks ~60 dtk)
GODOT_LOG=0
for i in $(seq 1 30); do
  if adb logcat -d 2>/dev/null | grep -q "Godot Engine v"; then GODOT_LOG=1; break; fi
  sleep 2
done
if [ "$GODOT_LOG" != "1" ]; then
  echo "::error::Log 'Godot Engine v...' tidak ditemukan — engine gagal init"
  adb logcat -d 2>/dev/null | tail -150 || true
  exit 1
fi
echo "== Log engine =="
adb logcat -d 2>/dev/null | grep -m3 "Godot Engine" || true
echo "== Backend render =="
adb logcat -d 2>/dev/null | grep -iE "falling back|opengl|vulkan" | head -8 || true

# 3) Beri waktu scene utama termuat & dirender (renderer software di emulator lambat)
sleep 30

PID=$(adb shell pidof "$PKG" | tr -d '\r\n ')
echo "PID: ${PID:-<mati>}"
if [ -z "$PID" ]; then
  echo "::error::Proses game mati setelah boot (crash?)"
  adb logcat -d -b crash 2>/dev/null | tail -80 || true
  exit 1
fi

# 4) Cek crash buffer khusus paket game
CRASH=$(adb logcat -d -b crash 2>/dev/null | grep -c "$PKG" || true)
if [ "${CRASH:-0}" != "0" ]; then
  echo "::error::Crash terdeteksi di logcat crash-buffer ($CRASH baris)"
  adb logcat -d -b crash 2>/dev/null | head -60 || true
  exit 1
fi

# 5) Screenshot 1 — kondisi menu utama
adb exec-out screencap -p > emulator-1.png
echo "Screenshot 1: $(du -h emulator-1.png | cut -f1)"

# 6) Interaksi sentuh (uji input; bisa membuka gameplay) lalu screenshot 2
adb shell input tap 540 1200 || true
sleep 15
adb exec-out screencap -p > emulator-2.png
echo "Screenshot 2: $(du -h emulator-2.png | cut -f1)"

# 7) Pastikan proses masih hidup setelah interaksi
PID2=$(adb shell pidof "$PKG" | tr -d '\r\n ')
if [ -z "$PID2" ]; then
  echo "::error::Proses game mati setelah interaksi sentuh"
  adb logcat -d -b crash 2>/dev/null | tail -80 || true
  exit 1
fi

echo "EMULATOR_SMOKE_PASS"
