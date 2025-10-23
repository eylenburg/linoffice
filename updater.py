import zipfile
import io
import os
import shutil
from pathlib import Path
import re
import sys
import http.client
import json
import urllib.parse

# Configuration
REPO_OWNER = "eylenburg"
REPO_NAME = "linoffice"
CURRENT_VERSION = "2.2.2" 
GITHUB_API_URL = f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/releases"
PRESERVE_FILES = {"config/compose.yaml", "config/linoffice.conf", "config/oem/registry/regional_settings.reg"}
GITHUB_TOKEN = None  # Can replace with GitHub Personal Access Token if hitting API limits

def get_latest_release():
    """Fetch the latest non-draft, non-prerelease release from GitHub."""
    try:
        conn = http.client.HTTPSConnection("api.github.com")
        headers = {
            "User-Agent": "LinofficeUpdateScript",
            "Accept": "application/vnd.github.v3+json"
        }
        if GITHUB_TOKEN:
            headers["Authorization"] = f"token {GITHUB_TOKEN}"

        path = f"/repos/{REPO_OWNER}/{REPO_NAME}/releases"
        conn.request("GET", path, headers=headers)
        response = conn.getresponse()
        
        if response.status != 200:
            print(f"Error fetching releases: {response.status} {response.reason}")
            return None
        
        releases = json.loads(response.read().decode())
        for release in releases:
            if not release.get("prerelease") and not release.get("draft"):
                return release
        return None
    except Exception as e:
        print(f"Error fetching releases: {e}")
        return None

def version_tuple(v):
    return tuple(map(int, (v.split("."))))

def compare_versions(current_version, latest_version):
    """Compare two version strings."""
    return version_tuple(latest_version) > version_tuple(current_version)

def major_version(v):
    try:
        return int(v.split(".")[0])
    except Exception:
        return -1

def download_and_update(asset_url, current_dir):
    """Download and extract the new release, preserving specified files."""
    try:
        parsed_url = urllib.parse.urlparse(asset_url)
        conn = http.client.HTTPSConnection(parsed_url.netloc)
        headers = {
            "User-Agent": "PythonUpdateScript"
        }
        if GITHUB_TOKEN:
            headers["Authorization"] = f"token {GITHUB_TOKEN}"
        conn.request("GET", parsed_url.path, headers=headers)
        response = conn.getresponse()

        # Handle redirects (e.g., GitHub -> AWS)
        if response.status in (301, 302, 303, 307, 308):
            redirect_url = response.getheader("Location")
            if not redirect_url:
                print("Redirect without Location header")
                return False
            print(f"Redirected to: {redirect_url}")
            return download_and_update(redirect_url, current_dir)

        if response.status != 200:
            print(f"Error downloading asset: {response.status} {response.reason}")
            return False

        zip_file = zipfile.ZipFile(io.BytesIO(response.read()))

        # Get the top-level folder name in the zip (e.g., 'linoffice-1.0.7/')
        top_level_folder = next((name for name in zip_file.namelist() if '/' in name), None)
        if not top_level_folder:
            print("Error: Could not determine top-level folder in zip.")
            return False
        prefix = top_level_folder.split('/')[0] + '/'

        # Prefer extracting contents of 'src/' if present; otherwise use archive root
        has_src = any(name.startswith(prefix + 'src/') for name in zip_file.namelist())
        content_prefix = prefix + 'src/' if has_src else prefix

        # Count updated files
        updated_count = 0

        # Extract files, skipping directory entries and using selected content prefix
        for file_info in zip_file.infolist():
            if file_info.is_dir():
                continue
            # Only process files within the selected content prefix
            if not file_info.filename.startswith(content_prefix):
                continue
            relative_path = file_info.filename[len(content_prefix):]
            if not relative_path:
                continue
            target_path = Path(current_dir) / relative_path

            if relative_path in PRESERVE_FILES:
                print(f"Preserving {relative_path}")
                continue

            target_path.parent.mkdir(parents=True, exist_ok=True)
            with zip_file.open(file_info) as source, open(target_path, "wb") as target:
                shutil.copyfileobj(source, target)
            updated_count += 1

        zip_file.close()
        print(f"Update completed successfully. Updated {updated_count} files.")
        return True
    except Exception as e:
        print(f"Error during update: {e}")
        return False

def main():
    """Main function to check for updates and apply them."""
    print("Checking for updates...")
    release_data = get_latest_release()
    if not release_data:
        print("Failed to fetch release information.")
        return

    latest_version = release_data.get("tag_name", "").lstrip("v")
    if not re.match(r"\d+\.\d+\.\d+", latest_version):
        print("Invalid version format in latest release.")
        return

    if not compare_versions(CURRENT_VERSION, latest_version):
        print(f"No update needed. Current version: {CURRENT_VERSION}, Latest: {latest_version}")
        return

    print(f"New version available: {latest_version} (Current: {CURRENT_VERSION})")

    # If major version changes, prompt with release notes link and explicit warning
    if major_version(CURRENT_VERSION) != major_version(latest_version):
        release_notes_url = f"https://github.com/{REPO_OWNER}/{REPO_NAME}/releases/tag/v{latest_version}"
        print("WARNING: This update changes the major version and may include breaking changes.")
        print("You may have to intervene manually if updating from the current version.")
        print(f"Please review the release notes: {release_notes_url}")
        confirm_major = input("Do you still want to update? (y/n): ").strip().lower()
        if confirm_major != 'y':
            print("Update cancelled.")
            return
    else:
        confirm = input("Do you want to download and install the update? (y/n): ").strip().lower()
        if confirm != 'y':
            print("Update cancelled.")
            return

    # Construct the GitHub tag-based zip URL
    asset_url = f"https://github.com/{REPO_OWNER}/{REPO_NAME}/archive/refs/tags/v{latest_version}.zip"
    print(f"Using download URL: {asset_url}")

    current_dir = Path(sys.argv[0]).parent
    if download_and_update(asset_url, current_dir):
        print("Please restart the application to use the new version.")
    else:
        print("Update failed.")

if __name__ == "__main__":
    main()
