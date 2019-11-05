#!/usr/bin/env bash
#
# gh-dl-release! It works!
# 
# This script downloads an asset from latest or specific Github release of a
# private repo. Feel free to extract more of the variables into command line
# parameters.
#
# PREREQUISITES
#
# curl, wget, jq
#
# USAGE
#
# Set all the variables inside the script, make sure you chmod +x it, then
# to download specific version to my_app.tar.gz:
#
#     gh-dl-release 2.1.1 my_app.tar.gz
#
# to download latest version:
#
#     gh-dl-release latest latest.tar.gz
#
# If your version/tag doesn't match, the script will exit with error.

TOKEN="95f57a9004653b3266b5f3717d192b8499d7330a"
REPO=$1
VERSION=$2
FILE=$3
GITHUB="https://api.github.com"

alias errcho='>&2 echo'

function gh_curl() {
  curl -H "Authorization: token $TOKEN" \
       -H "Accept: application/vnd.github.v3.raw" \
       $@
}

parser=". | map(select(.tag_name == \"$VERSION\"))[0].assets | map(select(.name == \"$FILE\"))[0].id"
asset_id=`gh_curl -s $GITHUB/repos/$REPO/releases | jq "$parser"`

if [ "$asset_id" = "null" ]; then
  errcho "ERROR: version not found $VERSION"
  exit 1
fi;

OUTDIR="gh-dl-release/$REPO/$VERSION"
mkdir -p $OUTDIR
cd $OUTDIR

if test -e "$FILE"
then ZFLAG="-z $FILE"
else ZFLAG=
fi

echo "Downloading $FILE..."
set -x
curl -L -o $FILE $ZFLAG -H 'Accept:application/octet-stream' \
  https://$TOKEN:@api.github.com/repos/$REPO/releases/assets/$asset_id
