# GitHub Latest
Downloads the latest release tarball from a GitHub repo

## Usage
```bash
github_latest.sh [<options>] <Github repo URL>
```
## Options
* `-h` Show help and exit
* `-s` Simmulate
* `-d` Download file to given dir; downloads to current dir if ommited
* `-z` Get ZIP instead of tarball
* `-t` Use topmost (usually latest) tag instead of release
* `-n` Print out the latest release tag name and exit
* `-N` Print out the latest release tarball or zip file name and exit
* `-j` Print out JSON about the latest release and exit
* `-p` Get asset with filename matching regex instead of tarball
* `-P` Get asset with entire filename matching regex instead of tarball
