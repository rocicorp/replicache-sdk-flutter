ORIG=`pwd`
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT=$DIR/../
REPM_REPO='rocicorp/replicant-client'
REPM_VERSION='v0.0.12'
PACKAGE_VERSION=`git describe --tags`

echo "Building Flutter SDK..."

cd $ROOT
set -x

# Download repm release if necessary
./tool/gh-dl-release.sh $REPM_REPO $REPM_VERSION 'Repm.framework.tar.gz'
./tool/gh-dl-release.sh $REPM_REPO $REPM_VERSION 'repm.aar'

# Copy the local repo into the output dir
rm -rf build
mkdir build
cd build
mkdir replicant-flutter-sdk
ls ../ | grep -v build | grep -v sample | grep -v tool | grep -v gh-dl-release | xargs -I{} cp -R ../{} replicant-flutter-sdk/{}

# Stamp the version number
sed -i "" "s/version: 0.0.0+dev/version: $PACKAGE_VERSION/" replicant-flutter-sdk/pubspec.yaml

# Copy in repm
cp ../gh-dl-release/$REPM_REPO/$REPM_VERSION/repm.aar replicant-flutter-sdk/android/
cd replicant-flutter-sdk/ios/
tar -xvf ../../../gh-dl-release/$REPM_REPO/$REPM_VERSION/Repm.framework.tar.gz

# Tar everything up
cd -
tar -czvf replicant-flutter-sdk.tar.gz replicant-flutter-sdk
cd $ORIG
