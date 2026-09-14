#!/usr/bin/env bash
# Auto-run smoke test APK rilisan di Android emulator (CI).
# Alur: install -> launch -> tunggu engine init -> cek crash -> screenshot (opsional)
#       -> interaksi sentuh -> cek masih hidup.
# Lulus = EMULATOR_SMOKE_PASS. Bukti visual render asli disediakan job `screenshots`.
#
# Catatan backend: emulator CI tanpa GPU host hanya bisa menginisialisasi Vulkan
# SwiftShader yang merender HITAM senyap di Godot 4 (jalur GL emugl gagal init,
# -feature -Vulkan membuat app mati). Ini keterbatasan emulator, bukan bug game —
# karena itu kegagalan render TIDAK membuat smoke test gagal; yang diverifikasi
# adalah siklus hidup proses: install, launch, init engine, tanpa crash, input hidup.
set -euo pipefail

PKG="com.secretarrow.rblox"
APK_DIR="${APK_DIR:-apk}"
SHOT_OK=0

# Deteksi screenshot hitam kosong (informasional — render SwiftShader memang hitam)
check_not_black() {
  local f="$1"
  if command -v identify >/dev/null 2>&1; then
    local COLORS
    COLORS=$(identify -format "%k" "$f" 2>/dev/null || echo 0)
    echo "Warna unik $f: ${COLORS:-0}"
    if [ "${COLORS:-0}" -ge 16 ]; then
      return 0
    fi
  fi
  return 1
}

# pidof exit 1 bila proses mati — jangan biarkan pipefail membunuh script diam-diam
alive() {
  adb shell pidof "$PKG" 2>/dev/null | tr -d '\r\n ' || true
}

dump_diag() {
  echo "== Diagnostik logcat =="
  adb logcat -d -b crash 2>/dev/null | tail -50 || true
  adb logcat -d 2>/dev/null | grep -iE "godot|FATAL EXCEPTION" | tail -30 || true
}

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

# Suppress dialog sistem "Viewing full screen" (overlay immersive-mode first-launch)
adb shell settings put secure immersive_mode_confirmations confirmed || true

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
  dump_diag
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
  dump_diag
  exit 1
fi
echo "== Log engine =="
adb logcat -d 2>/dev/null | grep -m3 "Godot Engine" || true
echo "== Backend render =="
adb logcat -d 2>/dev/null | grep -iE "falling back|opengl|vulkan" | grep -ivE "vold|nativeloader|init|signature" | head -8 || true

# 3) Beri waktu scene utama termuat & dirender (renderer software di emulator lambat)
sleep 30

# 4) Proses harus tetap hidup + tidak ada crash
PID=$(alive)
echo "PID: ${PID:-<mati>}"
if [ -z "$PID" ]; then
  echo "::error::Proses game mati setelah boot (crash?)"
  dump_diag
  exit 1
fi
CRASH=$(adb logcat -d -b crash 2>/dev/null | grep -c "$PKG" || true)
if [ "${CRASH:-0}" != "0" ]; then
  echo "::error::Crash terdeteksi di logcat crash-buffer ($CRASH baris)"
  adb logcat -d -b crash 2>/dev/null | head -60 || true
  exit 1
fi

# 5) Screenshot 1 — kondisi menu utama (dapat berupa hitam di emulator SwiftShader)
adb exec-out screencap -p > emulator-1.png
echo "Screenshot 1: $(du -h emulator-1.png | cut -f1)"
if check_not_black emulator-1.png; then
  SHOT_OK=1
else
  echo "::warning::Render emulator hitam (SwiftShader Vulkan) — normal untuk emulator tanpa GPU; bukan kegagalan game"
fi

# 6) Interaksi sentuh di tengah layar aktif (rotasi-aware) lalu screenshot 2
adb exec-out screencap -p > /tmp/probe.png
DIM=$(file /tmp/probe.png | sed -E 's/.*PNG image data, ([0-9]+) x ([0-9]+).*/\1 \2/')
FW=$(echo "$DIM" | cut -d' ' -f1)
FH=$(echo "$DIM" | cut -d' ' -f2)
echo "Resolusi layar aktif: ${FW}x${FH} -> tap ($((FW/2)), $((FH/2)))"
adb shell input tap "$((FW/2))" "$((FH/2))" || true
sleep 15
adb exec-out screencap -p > emulator-2.png
echo "Screenshot 2: $(du -h emulator-2.png | cut -f1)"
if [ "$SHOT_OK" = "1" ] && ! check_not_black emulator-2.png; then
  echo "::warning::Screenshot 2 hitam setelah sentuh"
fi

# 7) Pastikan proses masih hidup setelah interaksi
PID2=$(alive)
if [ -z "$PID2" ]; then
  echo "::error::Proses game mati setelah interaksi sentuh"
  dump_diag
  exit 1
fi

# Penanda: screenshot layak dilampirkan ke release (ada konten visual)
if [ "$SHOT_OK" = "1" ]; then
  touch screenshot_ok.flag
fi

echo "EMULATOR_SMOKE_PASS"
