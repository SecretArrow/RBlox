#!/usr/bin/env python3
"""Sinkronisasi locale: scan semua .gd untuk Locale.t("key"), lalu pastikan
key tersebut ada di data/locales/en.json dan id.json.
- Key baru di en.json -> diisi humanize(key) (default yang terbaca).
- Key baru di id.json -> diisi nilai en (fallback; diterjemahkan menyusul).
Dipakai lokal & oleh CI Auto-Fix."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCALES = ROOT / "data" / "locales"
PATTERN = re.compile(r'Locale\.t\(\s*"([a-z0-9_]+)"')


def scan_keys() -> set:
	keys = set()
	for gd in ROOT.rglob("*.gd"):
		if ".godot" in str(gd):
			continue
		try:
			text = gd.read_text(encoding="utf-8")
		except Exception:
			continue
		keys |= set(PATTERN.findall(text))
	return keys


def load(lang: str):
	p = LOCALES / f"{lang}.json"
	if p.exists():
		try:
			return json.loads(p.read_text(encoding="utf-8")), p
		except Exception as e:
			print(f"WARN: {p} tidak valid: {e}", file=sys.stderr)
	return {}, p


def humanize(key: str) -> str:
	return key.replace("_", " ").capitalize()


def main() -> int:
	keys = scan_keys()
	en, en_p = load("en")
	idn, id_p = load("id")
	added = 0
	for k in sorted(keys):
		if k not in en:
			en[k] = humanize(k)
			added += 1
	for k in sorted(keys):
		if k not in idn:
			idn[k] = en.get(k, humanize(k))
			added += 1
	en_p.write_text(json.dumps(en, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
	id_p.write_text(json.dumps(idn, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
	print(f"locale: total_key={len(keys)} ditambah={added}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
