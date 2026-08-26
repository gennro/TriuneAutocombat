#!/usr/bin/env python3
"""
Triune AutoCombat Release Updater Script (Python 3)
Standalone cross-platform updater using Python 3 standard library.
"""

import sys
import os
import json
import urllib.request
import zipfile
import shutil
import argparse
import tempfile

REPO = "gennro/TriuneAutocombat"
API_URL = f"https://api.github.com/repos/{REPO}/releases/latest"

def check_updates():
    req = urllib.request.Request(API_URL, headers={"User-Agent": "TriuneUpdater"})
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            tag = data.get("tag_name", "Unknown")
            body = data.get("body", "No release notes.")
            print(f"Latest GitHub Release: {tag}")
            print("\nRelease Notes:\n" + body)
            return tag
    except Exception as e:
        print(f"Error checking updates: {e}", file=sys.stderr)
        sys.exit(1)

def perform_update(target_dir=None):
    if not target_dir:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        target_dir = os.path.abspath(os.path.join(script_dir, ".."))

    print(f"[INFO] Target installation directory: {target_dir}")
    tag = check_updates()
    
    download_url = f"https://github.com/{REPO}/archive/refs/tags/{tag}.zip"
    print(f"[INFO] Downloading release package from {download_url}...")

    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as tmp_file:
            tmp_path = tmp_file.name

        req = urllib.request.Request(download_url, headers={"User-Agent": "TriuneUpdater"})
        with urllib.request.urlopen(req) as resp, open(tmp_path, "wb") as f:
            shutil.copyfileobj(resp, f)

        print("[INFO] Extracting archive...")
        with zipfile.ZipFile(tmp_path, "r") as zip_ref:
            namelist = zip_ref.namelist()
            if not namelist:
                raise ValueError("Downloaded ZIP file is empty.")
            
            root_prefix = namelist[0].split('/')[0] + '/'
            for member in zip_ref.infolist():
                if member.filename.startswith(root_prefix) and member.filename != root_prefix:
                    rel_path = member.filename[len(root_prefix):]
                    dest_path = os.path.join(target_dir, rel_path)
                    if member.is_dir():
                        os.makedirs(dest_path, exist_ok=True)
                    else:
                        os.makedirs(os.path.dirname(dest_path), exist_ok=True)
                        with zip_ref.open(member) as src, open(dest_path, "wb") as dst:
                            shutil.copyfileobj(src, dst)

        print(f"[SUCCESS] Release {tag} updated to version and completed successfully!")
    except Exception as e:
        print(f"Error executing update: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass

def main():
    parser = argparse.ArgumentParser(description="Triune AutoCombat Release Updater")
    parser.add_argument("--check", action="store_true", help="Check for latest release on GitHub")
    parser.add_argument("--force", action="store_true", help="Force update installation")
    parser.add_argument("--dir", type=str, help="Target installation directory")
    args = parser.parse_args()

    if args.check:
        check_updates()
    else:
        perform_update(args.dir)

if __name__ == "__main__":
    main()
