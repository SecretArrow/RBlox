#!/usr/bin/env python3
"""CI Auto-Fix RBlox.

Dipanggil oleh workflow .github/workflows/autofix.yml setelah workflow
"Build Android APK" selesai dengan status FAILURE (atau via manual dispatch).

Alur:
  (a) Tentukan ID run yang gagal:
      - utama: baca GITHUB_EVENT_PATH (payload workflow_run) -> workflow_run.id
      - fallback: `gh run list --workflow "Build Android APK" --status failure ...`
  (b) Ambil log gagal: `gh run view <id> --log-failed` -> /tmp/failed.log
      (guard: bila kosong/gagal, coba `--log` penuh; tetap gagal -> lanjut saja)
  (c) Ekstrak baris error penting (regex Parse Error|SCRIPT ERROR|ERROR|error:, max 60 baris)
  (d) Jalankan `gdformat` pada semua **/*.gd (error diabaikan)
  (e) Jalankan `python tools/sync_locales.py` (sinkron key locale)
  (f) Bila `git status --porcelain` berubah DAN commit terakhir TIDAK diawali
      "[autofix]" -> config user, commit "[autofix] perbaikan otomatis CI
      (format+locale)", push ke origin main.
  (g) Bila tidak ada perubahan ATAU commit terakhir sudah "[autofix]" ->
      JANGAN push (anti-loop); buat/komentari issue "CI merah - perlu
      perbaikan manual" berisi ekstrak error + link run (dedupe by judul).

Catatan:
  - Semua subprocess dibungkus try/except dan selalu print status.
  - Exit code 0 selalu, kecuali error fatal kritis di luar langkah di atas,
    agar workflow auto-fix sendiri tidak merah.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
FAILED_LOG = Path("/tmp/failed.log")
ISSUE_TITLE = "CI merah - perlu perbaikan manual"
COMMIT_MESSAGE = "[autofix] perbaikan otomatis CI (format+locale)"
COMMIT_PREFIX = "[autofix]"
MAX_ERROR_LINES = 60
ERROR_RE = re.compile(r"Parse Error|SCRIPT ERROR|ERROR|error:")


def sh(cmd: list[str]) -> tuple[int, str]:
    """Jalankan subprocess di REPO_ROOT; kembalikan (returncode, output gabungan)."""
    try:
        p = subprocess.run(cmd, cwd=str(REPO_ROOT), capture_output=True, text=True)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except Exception as exc:  # binary hilang, OOM, dsb.
        return 1, f"EXC: {exc}"


# ---------------------------------------------------------------- (a) run id
def get_failed_run_id() -> str | None:
    ev_path = os.environ.get("GITHUB_EVENT_PATH", "")
    if ev_path and Path(ev_path).exists():
        try:
            data = json.loads(Path(ev_path).read_text(encoding="utf-8"))
            rid = (data.get("workflow_run") or {}).get("id")
            if rid:
                print(f"[autofix] run gagal (event payload): {rid}")
                return str(rid)
        except Exception as exc:
            print(f"[autofix] WARN baca GITHUB_EVENT_PATH gagal: {exc}")
    rc, out = sh([
        "gh", "run", "list", "--workflow", "Build Android APK",
        "--status", "failure", "--limit", "1",
        "--json", "databaseId", "-q", ".[0].databaseId",
    ])
    rid = out.strip().splitlines()[-1].strip() if out.strip() else ""
    if rc == 0 and rid:
        print(f"[autofix] run gagal (fallback gh CLI): {rid}")
        return rid
    print("[autofix] tidak ditemukan run gagal")
    return None


# ------------------------------------------------------------- (b) ambil log
def fetch_failed_log(run_id: str) -> bool:
    rc, out = sh(["gh", "run", "view", run_id, "--log-failed"])
    if rc == 0 and out.strip():
        FAILED_LOG.write_text(out, encoding="utf-8")
        print(f"[autofix] log gagal tersimpan: {FAILED_LOG} ({len(out)} char)")
        return True
    # guard: --log-failed kadang kosong -> coba log penuh
    rc, out = sh(["gh", "run", "view", run_id, "--log"])
    if rc == 0 and out.strip():
        FAILED_LOG.write_text(out, encoding="utf-8")
        print(f"[autofix] log penuh (fallback) tersimpan: {FAILED_LOG}")
        return True
    print(f"[autofix] WARN gagal ambil log run {run_id} (diabaikan)")
    return False


# --------------------------------------------------------- (c) ekstrak error
def extract_errors() -> str:
    if not FAILED_LOG.exists():
        return "(log gagal tidak tersedia)"
    try:
        text = FAILED_LOG.read_text(encoding="utf-8", errors="replace")
    except Exception as exc:
        return f"(gagal baca log: {exc})"
    hits: list[str] = []
    for line in text.splitlines():
        if ERROR_RE.search(line):
            hits.append(line.strip()[:300])
            if len(hits) >= MAX_ERROR_LINES:
                break
    return "\n".join(hits) if hits else "(tidak ada baris yang cocok pola error)"


# ------------------------------------------------------- (d) gdformat *.gd
def run_gdformat() -> None:
    files = sorted(
        str(p) for p in REPO_ROOT.rglob("*.gd")
        if ".godot" not in p.parts and "android" not in p.parts
    )
    if not files:
        print("[autofix] gdformat: tidak ada file .gd")
        return
    try:
        p = subprocess.run(["gdformat"] + files, cwd=str(REPO_ROOT),
                           capture_output=True, text=True)
        print(f"[autofix] gdformat: rc={p.returncode} file={len(files)}")
        if p.stdout.strip():
            print(p.stdout.strip()[-1500:])
    except Exception as exc:
        print(f"[autofix] gdformat gagal (diabaikan): {exc}")


# ------------------------------------------------- (e) sync_locales.py
def run_sync_locales() -> None:
    try:
        p = subprocess.run([sys.executable, "tools/sync_locales.py"],
                           cwd=str(REPO_ROOT), capture_output=True, text=True)
        print(f"[autofix] sync_locales: rc={p.returncode}")
        if p.stdout.strip():
            print(p.stdout.strip())
    except Exception as exc:
        print(f"[autofix] sync_locales gagal (diabaikan): {exc}")


# ------------------------------------------------ (f) commit & push anti-loop
def last_commit_subject() -> str:
    rc, out = sh(["git", "log", "-1", "--pretty=%s"])
    return out.strip() if rc == 0 else ""


def commit_and_push() -> bool:
    rc, status = sh(["git", "status", "--porcelain"])
    changed = [ln for ln in status.splitlines() if ln.strip()]
    if rc != 0 or not changed:
        print("[autofix] tidak ada perubahan -> tidak commit/push")
        return False
    print(f"[autofix] {len(changed)} file berubah: {changed[:10]}")
    if last_commit_subject().startswith(COMMIT_PREFIX):
        print("[autofix] commit terakhir sudah [autofix] -> JANGAN push (anti-loop)")
        return False
    sh(["git", "config", "user.name", "rblox-autofix-bot"])
    sh(["git", "config", "user.email", "actions@github.com"])
    sh(["git", "add", "-A"])
    rc, out = sh(["git", "commit", "-m", COMMIT_MESSAGE])
    if rc != 0:
        print(f"[autofix] commit gagal (diabaikan): {out.strip()[:300]}")
        return False
    rc, out = sh(["git", "push", "origin", "main"])
    if rc != 0:
        print(f"[autofix] push gagal (diabaikan): {out.strip()[:300]}")
        return False
    print("[autofix] commit & push ke main sukses; build ulang dipicu otomatis")
    return True


# ------------------------------------------------- (g) issue otomatis dedupe
def run_link(run_id: str | None) -> str:
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    if repo and run_id:
        return f"https://github.com/{repo}/actions/runs/{run_id}"
    return "(link run tidak tersedia)"


def ensure_issue(run_id: str | None, error_text: str) -> None:
    body = (
        "Workflow **Build Android APK** gagal dan auto-fix tidak menghasilkan "
        "perubahan yang bisa dipush (atau sedang aktif guard anti-loop).\n\n"
        f"Run: {run_link(run_id)}\n\n"
        "Ekstrak error:\n\n```text\n"
        f"{error_text[:4000]}\n```\n\n"
        "_Issue dibuat otomatis oleh `tools/ci_autofix.py`._"
    )
    existing: int | None = None
    rc, out = sh(["gh", "issue", "list", "--state", "open", "--json", "number,title"])
    if rc == 0:
        try:
            for item in json.loads(out or "[]"):
                if item.get("title") == ISSUE_TITLE:
                    existing = int(item.get("number"))
                    break
        except Exception as exc:
            print(f"[autofix] WARN parse daftar issue: {exc}")
    if existing is not None:
        rc, _ = sh(["gh", "issue", "comment", str(existing), "--body", body])
        print(f"[autofix] update issue #{existing}: rc={rc}")
    else:
        rc, out = sh(["gh", "issue", "create", "--title", ISSUE_TITLE, "--body", body])
        print(f"[autofix] buat issue baru: rc={rc} {out.strip()[:200]}")


# ------------------------------------------------------------------- main
def main() -> int:
    print("=== RBlox CI Auto-Fix ===")
    run_id = get_failed_run_id()
    if run_id and fetch_failed_log(run_id):
        error_text = extract_errors()
        n = error_text.count("\n") + 1
        print(f"[autofix] ekstrak {n} baris error")
    else:
        error_text = "(log gagal tidak tersedia)"
        print("[autofix] lanjut tanpa log gagal (format + locale tetap dijalankan)")
    run_gdformat()
    run_sync_locales()
    if commit_and_push():
        print("[autofix] selesai: perbaikan dipush, issue tidak perlu dibuat")
    else:
        if run_id:
            try:
                ensure_issue(run_id, error_text)
            except Exception as exc:
                print(f"[autofix] gagal buat/komentari issue (diabaikan): {exc}")
        else:
            print("[autofix] tanpa run gagal -> skip issue")
    print("=== CI Auto-Fix selesai (exit 0) ===")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # hanya error fatal kritis yang exit != 0
        print(f"[autofix] FATAL: {exc}", file=sys.stderr)
        sys.exit(1)
