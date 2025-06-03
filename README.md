# Compression and Upload Tool for ibridges

A tool for compressing large datasets and uploading them to iRODS using ibridges.

## Functions

- Compresses files into 7z archives using zstd (and other algorithms possible) compression
- Configurable split size for large archives
- Generates and verifies SHA256 checksums
- Uploads to iRODS with automatic checksum verification
- Off-peak hour uploads to reduce server pressure
- UNC paths and long file paths supported
- **Handles .tar files (source output from PSI machine) and other files separately** (Note: This means .tar files in the **root directory** will be compressed to a separated folder /source, and all the other files will be compressed to /exported. If you are using this script for purposes other than PSI structured files, you will get an empty /source folder and all the files under /exported with original folder directory remained)
- (Constructing) Email after compression finished


## Prerequisites

- Windows operating system
- 7-Zip with zstd support (7-Zip-Zstandard)
- Python 3.x
- ibridges

## Installation

1. Install 7-Zip-Zstandard:
   - Download from: https://github.com/mcmilk/7-Zip-zstd/releases
   - Install to default location or update the `ZIP` path in `compressor.bat`

2. Install ibridges: with `pip install ibridges`

3. Configure ibridges: Create or download an iRODS environment file (irods_env.json), you can either Place it in a known location and update the `IBRIDGES_CONFIG` path in `compressor.bat`

## Configuration

Edit the CONFIGURATION section in `compressor.bat`:

```batch
set "FOLDER=your_input_folder"
set "OUTPUT_DIR=your_output_directory"
set "REMOTE_PATH=/your/irods/path"
set "SPLIT=8192m"
set "IBRIDGES_CONFIG=path_to_your_irods_env.json"
```

## Usage

1. Download and place both `compressor.bat` and `ibridges_uploader.py` at same folder.

2. Run `compressor.bat` (double clicking or use command line)

3. You can also use `ibridges_uploader.py` separately to upload something by:
    ```bash
    python ibridges_uploader.py /path/to/upload/dir /remote/full/path 1 /path/to/env.json
    ```
    Where the fourth argument (number) means whether to wait for off-peak hours (true/false). Off-peak hours are defined as 20:00-06:00.

Example:

## Troubleshooting for ibridges Issues

If ibridges fails, try these steps:

1. Update ibridges:
   ```bash
   pip install --upgrade ibridges
   ```

2. Check ibridges connection:
   ```bash
   ibridges path/to/init your_irods_env.json
   ```

3. Check ibridges version: run 
    ```bash
    ibridges ls /path/to/folder
    ```
    to see if it accepts this input and returns sha256 checksums.


## iRODS Configuration Environment File (irods_env.json) Example:

```json
{
    "irods_host": "irods.example.com",
    "irods_port": 1247,
    "irods_user_name": "your_username",
    "irods_zone_name": "your_zone",
    "irods_authentication_scheme": "native",
    "irods_encryption_algorithm": "AES-256-CBC",
    "irods_encryption_key_size": 32,
    "irods_encryption_num_hash_rounds": 16,
    "irods_encryption_salt_size": 8
}
```


## Resources

- [ibridges Documentation](https://ibridges.readthedocs.io/en/latest/)
- [7-Zip-Zstandard](https://github.com/mcmilk/7-Zip-zstd)
