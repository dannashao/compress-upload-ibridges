import os
import time
import base64
import subprocess
import sys
import re
from datetime import datetime

def run_cmd(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return result.returncode, result.stdout.strip(), result.stderr.strip()

def check_ibridges_connection(config_path):
    print("Checking ibridges connection...")
    config_path = config_path.replace('\\\\', '/').replace('\\', '/')
    code, out, err = run_cmd(f"ibridges init \"{config_path}\"")
    if code != 0:
        print(f"Error: Failed to initialize ibridges connection: {err}")
        return False
    print("ibridges connection successful.")
    return True

def create_collection(remote_path, collection):
    print(f"Checking if collection '{collection}' exists in ibridges...")
    # Check if collection exists
    code, out, err = run_cmd(f"ibridges ls \"irods:{remote_path}/{collection}\"")
    if code == 0:
        print(f"Collection '{collection}' already exists.")
        return True
        
    print(f"Creating collection '{collection}' in ibridges...")
    code, out, err = run_cmd(f"ibridges mkcoll \"irods:{remote_path}/{collection}\"")
    if code != 0:
        print(f"Error: Failed to create collection: {err}")
        return False
    print(f"Collection '{collection}' created successfully.")
    return True

def wait_until_off_peak():
    while True:
        now = datetime.now()
        current_hour = now.hour
        is_off_peak = current_hour >= 20 or current_hour < 6
        
        if is_off_peak:
            print(f"[{now.strftime('%H:%M:%S')}] Off-peak hours detected, proceeding with upload...")
            return
            
        if current_hour < 20:
            hours_until_off_peak = 20 - current_hour
        else:
            hours_until_off_peak = 24 - current_hour + 6
            
        minutes_until_off_peak = hours_until_off_peak * 60 - now.minute
        print(f"[{now.strftime('%H:%M:%S')}] Current time is {current_hour:02d}:{now.minute:02d}. "
              f"Waiting {hours_until_off_peak} hours ({minutes_until_off_peak} minutes until off-peak hours (20:00-06:00)...")
        
        time.sleep(300)

def parse_sha256_file(sha256_file):
    checksums = {}
    with open(sha256_file, 'r') as f:
        content = f.read()

    pattern = r"SHA256 hash of (.+?):\s*([a-fA-F0-9]{64})"
    for match in re.findall(pattern, content):
        filename, hex_hash = match
        base64_hash = base64.b64encode(bytes.fromhex(hex_hash)).decode('utf-8')
        checksums[os.path.basename(filename)] = f"sha2:{base64_hash}"
    return checksums

def upload_files(output_dir, archive_base, checksums, remote_path):
    archive_files = sorted([
        f for f in os.listdir(output_dir)
        if f.startswith(archive_base + ".") and re.match(r".*\.\d{3}$", f)
    ])
    archive_name = os.path.basename(os.path.dirname(output_dir.rstrip("/\\")))
    collection = f"{archive_name}/{archive_base}"
    
    print("\n=== Uploading Files ===")
    uploaded_files = []
    for filename in archive_files:
        full_path = os.path.join(output_dir, filename)
        success = False
        for attempt in range(1, 4):
            print(f"\nUploading {filename} (Attempt {attempt}/3)...")
            code, out, err = run_cmd(f"ibridges upload \"{full_path}\" \"irods:{remote_path}/{collection}\"")
            if code == 0:
                print(f"{filename} uploaded successfully.")
                uploaded_files.append(filename)
                success = True
                break
            else:
                print(f"Upload failed: {err}")
                time.sleep(5)
        if not success:
            print(f"Failed to upload {filename} after 3 attempts.")
            return False
    
    print("\n=== Verifying Checksums ===")
    code, stdout, stderr = run_cmd(f"ibridges ls \"irods:{remote_path}/{collection}\"")
    if code != 0:
        print(f"Error listing collection: {stderr}")
        return False
        
    for filename in uploaded_files:
        print(f"\nVerifying {filename}...")
        remote_checksum = checksums.get(filename)
        if not remote_checksum:
            print(f"Checksum for {filename} not found in .sha256 file.")
            return False
            
        # Get the checksum directly from the uploaded file
        collection_path = f"{remote_path}/{collection}".replace("//", "/")
        code, stdout, stderr = run_cmd(f"ibridges ls -l \"irods:{collection_path}\"")
        if code == 0:
            # Split the output into lines and find the matching file
            for line in stdout.split('\n'):
                if filename in line:
                    # Extract checksum from the line
                    match = re.search(r'sha2:([a-zA-Z0-9+/=]+)', line)
                    if match:
                        uploaded_checksum = f"sha2:{match.group(1)}"
                        if uploaded_checksum == remote_checksum:
                            print(f"{filename} verified successfully.")
                            break
                        else:
                            print(f"Checksum mismatch for {filename}.")
                            print(f"Expected: {remote_checksum}")
                            print(f"Got: {uploaded_checksum}")
                            return False
            else:
                print(f"Could not find file {filename} in ls output.")
                return False
        else:
            print(f"Could not get file info for {filename}.")
            print(f"Error: {stderr}")
            return False
    
    return True

def main():
    if len(sys.argv) != 6:
        print("Usage: ibridges_uploader.py <output_dir> <archive_base> <remote_path> <wait_off_peak> <ibridges_config>")
        print("Example: ibridges_uploader.py ./output source /nluu6p/home/research-me-test true D:/Danna/irods_env.json")
        sys.exit(1)

    output_dir = os.path.normpath(sys.argv[1])
    archive_base = sys.argv[2]
    remote_path = sys.argv[3].rstrip("/")  # Remove trailing slash if present
    wait_off_peak = sys.argv[4].lower() == "true"
    ibridges_config = sys.argv[5]

    sha256_file = os.path.join(output_dir, f"{archive_base}.sha256")
    if not os.path.isfile(sha256_file):
        print(f"SHA256 file not found: {sha256_file}")
        sys.exit(1)

    if not check_ibridges_connection(ibridges_config):
        print("\nFailed to establish ibridges connection. Please check your configuration.")
        sys.exit(1)

    archive_name = os.path.basename(os.path.dirname(output_dir.rstrip("/\\")))
    collection = f"{archive_name}/{archive_base}"
    if not create_collection(remote_path, collection):
        print("\nFailed to create collection. Please check your permissions and path.")
        sys.exit(1)

    if wait_off_peak:
        print(f"[{datetime.now().strftime('%H:%M:%S')}] Upload will start at off-peak hours (after 20:00)...")
        wait_until_off_peak()
    else:
        print(f"[{datetime.now().strftime('%H:%M:%S')}] Starting upload immediately...")

    print("Parsing checksum file...")
    checksums = parse_sha256_file(sha256_file)

    print("Uploading and verifying archive splits...")
    success = upload_files(output_dir, archive_base, checksums, remote_path)

    if success:
        print("\nUpload and verification completed successfully.")
        sys.exit(0)
    else:
        print("\nSome files failed to upload. Please check the log and retry.")
        sys.exit(1)

if __name__ == "__main__":
    main()
