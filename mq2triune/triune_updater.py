#!/usr/bin/env python3
"""
TriuneAutocombat — GitHub Release Updater Script
Cross-platform updater for Windows and Linux located inside mq2triune/.
Pulls the latest release package from GitHub Releases and updates core script files,
preserving user configuration (triune_loadout.lua) and custom INI files.
"""

import os
import sys
import json
import urllib.request
import urllib.error
import zipfile
import tempfile
import shutil
import re
import argparse
from pathlib import Path

# Repository Details
GITHUB_REPO = "gennro/TriuneAutocombat"
API_URL = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"
ASSET_NAME = "TriuneAutocombat-Update.zip"

# ANSI Colors
COLOR_GREEN = "\033[92m"
COLOR_YELLOW = "\033[93m"
COLOR_RED = "\033[91m"
COLOR_CYAN = "\033[96m"
COLOR_RESET = "\033[0m"

def log(msg, level="info"):
    prefix = ""
    if level == "info":
        prefix = f"{COLOR_CYAN}[INFO]{COLOR_RESET} "
    elif level == "success":
        prefix = f"{COLOR_GREEN}[SUCCESS]{COLOR_RESET} "
    elif level == "warn":
        prefix = f"{COLOR_YELLOW}[WARN]{COLOR_RESET} "
    elif level == "error":
        prefix = f"{COLOR_RED}[ERROR]{COLOR_RESET} "
    print(f"{prefix}{msg}")

def get_base_directories(given_dir):
    """
    Resolve mq2triune_dir and repo_root given a target directory.
    """
    target = Path(given_dir).resolve()
    if target.name == "mq2triune":
        mq2triune_dir = target
        repo_root = target.parent
    elif (target / "mq2triune").is_dir():
        repo_root = target
        mq2triune_dir = target / "mq2triune"
    else:
        # Fallback to given target directory for both
        mq2triune_dir = target
        repo_root = target

    return mq2triune_dir, repo_root

def get_installed_version(mq2triune_dir):
    """Find local version string from lua/triune.lua"""
    possible_paths = [
        mq2triune_dir / "lua" / "triune.lua",
        mq2triune_dir / "triune.lua",
    ]
    
    for path in possible_paths:
        if path.exists():
            try:
                with open(path, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()
                    match = re.search(r"local\s+VERSION\s*=\s*['\"]([^'\"]+)['\"]", content)
                    if match:
                        return match.group(1), path
            except Exception as e:
                log(f"Error reading local version from {path}: {e}", "warn")
                
    return "0.0", None

def clean_version_tag(tag):
    """Clean tag like 'v1.3' to '1.3' for comparison"""
    if tag.startswith("v") or tag.startswith("V"):
        return tag[1:].strip()
    return tag.strip()

def fetch_latest_release_info():
    """Fetch latest release metadata from GitHub API"""
    req = urllib.request.Request(
        API_URL,
        headers={"User-Agent": "TriuneAutocombat-Updater"}
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            if response.status == 200:
                data = json.loads(response.read().decode("utf-8"))
                return data
    except urllib.error.HTTPError as e:
        log(f"GitHub API request failed with HTTP {e.code}: {e.reason}", "error")
    except urllib.error.URLError as e:
        log(f"Network error connecting to GitHub: {e.reason}", "error")
    except Exception as e:
        log(f"Unexpected error querying GitHub release: {e}", "error")
    return None

def download_file(url, dest_path):
    """Download a file from URL to local destination path"""
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "TriuneAutocombat-Updater"}
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response, open(dest_path, "wb") as out_file:
            shutil.copyfileobj(response, out_file)
        return True
    except Exception as e:
        log(f"Failed to download asset from {url}: {e}", "error")
        return False

def extract_and_apply_update(zip_path, mq2triune_dir, repo_root, dry_run=False):
    """Extract zip archive and update core repo files while preserving user configs"""
    log("Opening downloaded release archive...", "info")
    
    with zipfile.ZipFile(zip_path, "r") as zip_ref:
        file_list = zip_ref.namelist()
        log(f"Archive contains {len(file_list)} entries.", "info")
        
        updated_files = 0
        preserved_files = 0

        with tempfile.TemporaryDirectory() as extract_temp:
            zip_ref.extractall(extract_temp)
            temp_root = Path(extract_temp)

            for root, _, files in os.walk(temp_root):
                for file in files:
                    src_file = Path(root) / file
                    rel_path = src_file.relative_to(temp_root)
                    
                    # Prevent overwriting user loadouts / custom configs
                    if file.lower() in ["triune_loadout.lua", "macroquest.ini", "login.db"]:
                        log(f"Skipping user configuration file: {rel_path}", "warn")
                        preserved_files += 1
                        continue

                    # Map destination path
                    parts = rel_path.parts
                    if parts[0] == "mq2triune":
                        sub_rel = Path(*parts[1:])
                        dest_file = mq2triune_dir / sub_rel
                    elif rel_path.name in ["README.md", "CHANGELOG.md"]:
                        dest_file = repo_root / rel_path
                    else:
                        dest_file = repo_root / rel_path

                    if dry_run:
                        log(f"[DRY-RUN] Would update: {dest_file}", "info")
                    else:
                        dest_file.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(src_file, dest_file)
                        log(f"Updated: {dest_file}", "success")
                    updated_files += 1

        return updated_files, preserved_files

def main():
    script_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="TriuneAutocombat GitHub Release Updater")
    parser.add_argument("--check", action="store_true", help="Check for updates without downloading")
    parser.add_argument("--force", action="store_true", help="Force update even if already on latest version")
    parser.add_argument("--dir", type=str, default=str(script_dir), help="Target mq2triune or root directory")
    parser.add_argument("--dry-run", action="store_true", help="Perform a dry run without modifying files")
    args = parser.parse_args()

    mq2triune_dir, repo_root = get_base_directories(args.dir)
    log(f"MQ2Triune Directory: {mq2triune_dir}", "info")
    log(f"Repository Root Directory: {repo_root}", "info")

    installed_version, version_file = get_installed_version(mq2triune_dir)
    if version_file:
        log(f"Currently Installed Version: {installed_version} (detected in {version_file.name})", "info")
    else:
        log(f"Could not locate triune.lua version string in {mq2triune_dir}. Treating as 0.0", "warn")

    log("Checking GitHub Releases for latest update...", "info")
    release_data = fetch_latest_release_info()
    if not release_data:
        log("Could not retrieve release information from GitHub.", "error")
        sys.exit(1)

    tag_name = release_data.get("tag_name", "0.0")
    remote_version = clean_version_tag(tag_name)
    release_name = release_data.get("name", tag_name)
    body = release_data.get("body", "No release notes provided.")

    log(f"Latest GitHub Release: {remote_version} ({release_name})", "info")

    download_url = None
    assets = release_data.get("assets", [])
    for asset in assets:
        if asset.get("name") == ASSET_NAME or asset.get("name").endswith(".zip"):
            download_url = asset.get("browser_download_url")
            break

    if not download_url:
        download_url = release_data.get("zipball_url")
        log("Release zip asset not found directly; falling back to release zipball.", "warn")

    if not download_url:
        log("No valid download URL found in release data.", "error")
        sys.exit(1)

    is_newer = remote_version != clean_version_tag(installed_version)
    if not is_newer and not args.force:
        log(f"You are already running the latest version ({installed_version}).", "success")
        if not args.check:
            log("Use --force to re-download and apply the update anyway.", "info")
        sys.exit(0)

    if is_newer:
        log(f"Update Available! Installed: {installed_version} -> Latest: {remote_version}", "warn")
    
    if args.check:
        log(f"Release Notes:\n{body}", "info")
        sys.exit(0)

    log(f"Downloading release archive from {download_url}...", "info")

    with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as tmp_file:
        tmp_zip_path = tmp_file.name

    try:
        success = download_file(download_url, tmp_zip_path)
        if not success:
            log("Failed to download release archive.", "error")
            sys.exit(1)

        log("Download complete. Applying update...", "info")
        updated_count, preserved_count = extract_and_apply_update(
            tmp_zip_path, mq2triune_dir, repo_root, dry_run=args.dry_run
        )

        if args.dry_run:
            log(f"[DRY-RUN] Completed. {updated_count} files would be updated, {preserved_count} user files preserved.", "success")
        else:
            log(f"Update completed successfully! {updated_count} files updated, {preserved_count} user files preserved.", "success")
            log(f"TriuneAutocombat updated to version {remote_version}.", "success")

    finally:
        if os.path.exists(tmp_zip_path):
            os.remove(tmp_zip_path)

if __name__ == "__main__":
    main()
