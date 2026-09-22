#!/bin/bash

function usage() {
cat <<EOF
Downloads the latest release tarball from a GitHub repo

Usage: $(basename "$0") [-h] [-n|-N|-j] [-z | -p <pattern> | -P <pattern>] [-t] [-d <dir>] [-s] <Github repo URL>

  -h Show help and exit
  -n Print out the latest release tag name and exit
  -N Print out the latest release tarball or zip file name and exit
  -j Print out JSON about the latest release and exit
  -z Get ZIP instead of tarball
  -p Get asset with filename matching regex instead of tarball
  -P Get asset with entire filename matching regex instead of tarball
  -t Use topmost (usually latest) tag instead of release
  -d Download file to given dir, to current dir if ommited
  -s Simmulate

EOF
}

function brag_and_exit() {
    echo -e "Error: ${1:-Something went wrong}\n" >&2
    usage >&2
    exit 1
}

for APP in jq curl; do
    if ! command -v "$APP" &> /dev/null; then
        brag_and_exit "'$APP' is not installed"
    fi
done

while getopts ":p:P:d:szthnNj" opt; do
    case ${opt} in
        p ) ASSET_RE="$OPTARG";;
        P ) ASSET_RE="^${OPTARG}$";;
        d ) OUT_DIR="$OPTARG";;
        s ) SIMMULATE='echo -n';;
        z ) BALL_TYPE='zip';;
        t ) USE_TAG=1;;
        n ) NAME_ONLY=1;;
        N ) FILE_NAME_ONLY=1;;
        j ) FILE_NAME_ONLY=1
            JSON_OUT=1
            ;;
        h ) usage
            exit 0
            ;;
    esac
done
shift $((OPTIND -1))

OUT_DIR="${OUT_DIR:-"$(pwd)"}"
if [ -e "$OUT_DIR" -a -d "$OUT_DIR" -a -w "$OUT_DIR" ]; then
    OUT_DIR="$(sed -E 's%/+$%%' <<<"$OUT_DIR")"
else
    brag_and_exit "Strange output dir '$OUT_DIR'"
fi

if [ -z "$1" ]; then
    brag_and_exit "Missing GitHub repo URL"
fi

API_BASE="$(
    sed -E '
        s/\.git$//;
        s%^.*[/@]github\.com[/:]([^/]{1,})/([^/]{1,}).*$%https://api.github.com/repos/\1/\2%;
    ' <<<"$1"
)"

if ! egrep -q '^https://api\.github\.com/' <<<"$API_BASE" &>/dev/null; then
    brag_and_exit "Strange GitHub repo URL '$1'"
fi

if [ -n "$USE_TAG" -a -n "$ASSET_RE" ]; then
    brag_and_exit "Tags do not provide assets"
fi

if [ -n "$BALL_TYPE" -a -n "$ASSET_RE" ]; then
    brag_and_exit "Can download either a ZIP (-z) or an asset (-p|-P)"
fi

if [ -n "$NAME_ONLY" -a -n "$FILE_NAME_ONLY" ]; then
    brag_and_exit "It's either a tag name (-n) or a file name (-N)"
fi

if [ -n "$NAME_ONLY" -o -n "$FILE_NAME_ONLY" ] && [ -n "$SIMMULATE" ]; then
    brag_and_exit "Nothing much to simmulate when not asking to download"
fi

if [ -n "$USE_TAG" ]; then
    API_URL="$API_BASE/tags"
    TAGS_JSON="$(curl -s "$API_URL")"
    if [ $(jq 'length' <<<"$TAGS_JSON") -eq 0 ]; then
        brag_and_exit "Repo has no tags"
    fi
    ONE_JSON="$(jq '.[0]' <<<"$TAGS_JSON")"
    TAG_NAME="$(jq -r '.name' <<<"$ONE_JSON")"
else
    API_URL="$API_BASE/releases/latest"
    ONE_JSON=$(curl -s "$API_URL")
    STATUS="$(jq -r '.status' <<<"$ONE_JSON")"
    if [ "$STATUS" != null ] && [ $STATUS -ge 400 ]; then
        brag_and_exit "Repo has no releases"
    fi
    TAG_NAME="$(jq -r '.tag_name' <<<"$ONE_JSON")"
fi

if [ -n "$NAME_ONLY" ]; then
    echo "$TAG_NAME"
    exit 0
fi

if [ -n "$ASSET_RE" ]; then
    ASSET_URLS=$(
        jq "[
            .assets[] 
            | select(.name | test(\"$ASSET_RE\")) 
            | .browser_download_url
        ]" \
        <<<"$ONE_JSON"
    )
    NUM_URLS=$(jq 'length' <<<"$ASSET_URLS")
    if [ $NUM_URLS -eq 0 ]; then
        brag_and_exit "Release has no matching assets"
    elif [ $NUM_URLS -gt 1 ]; then
        _cook_err_msg() {
            echo -e "Release has $NUM_URLS matching assets\n"
            local lines=5
            local remaining=$(( $NUM_URLS - $lines ))
            [ $remaining -eq 1 ] && lines=$(( $lines + 1 ))
            jq -r '.[]' <<<"$ASSET_URLS" \
                | sed 's%.*/%%' \
                | head -n $lines
            if [ $remaining -gt 1 ]; then
                echo "… and $remaining more"
            fi
        }
        brag_and_exit "$(_cook_err_msg)"
    fi
    FINAL_URL=$(jq -r '.[0]' <<<"$ASSET_URLS")
else
    FINAL_URL="$(
        jq -r ".${BALL_TYPE:-tar}ball_url" \
        <<<"$ONE_JSON"
    )"
fi

if [ -n "$FILE_NAME_ONLY" ]; then
    FILE_NAME="$(
        curl -sL \
            -X HEAD \
            -w '%{header_json}\n' \
            "$FINAL_URL" \
        | jq -r '
            first(
                ."content-disposition"[]? 
                | select(test("^attachment;\\s*filename="; "i")) 
                | capture("filename=(?<f>[^\";]+)") 
                | .f 
            )
        '
    )"
    if [ $? -eq 0 -a -n "$FILE_NAME" ]; then
        if [ -n "$JSON_OUT" ]; then
            jq <<<"{\"tag\":\"${TAG_NAME}\",\"file\":\"${FILE_NAME}\",\"path\":\"${OUT_DIR}/${FILE_NAME}\"}"
        else
            echo "$FILE_NAME"
        fi
    else
        brag_and_exit "No file name"
    fi
else
    echo -e "Tag: $TAG_NAME\nSource URL: $FINAL_URL\nDestination dir: $OUT_DIR"
    $SIMMULATE curl \
        -LJO \
        --create-dirs \
        --output-dir "$OUT_DIR" \
        -w "${OUT_DIR}/%{filename_effective}" \
        "$FINAL_URL"

    if [ $? -eq 0 ]; then
        echo '' >&2
    else
        brag_and_exit "Download failed"
    fi
fi
