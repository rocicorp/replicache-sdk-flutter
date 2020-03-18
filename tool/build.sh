ORIG=`pwd`
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT=$DIR/../
REPM_REPO='rocicorp/replicant-client'
REPM_VERSION='v4.0.0'
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
mkdir replicache-flutter-sdk
ls ../ | grep -v build | grep -v sample | grep -v tool | grep -v gh-dl-release | grep -v doc | xargs -I{} cp -R ../{} replicache-flutter-sdk/{}

# Stamp the version number
sed -i "" "s/version: 0.0.0+dev/version: $PACKAGE_VERSION/" replicache-flutter-sdk/pubspec.yaml

# Remove the binary symlinks, which are now broken
rm replicache-flutter-sdk/android/repm.aar
rm -rf replicache-flutter-sdk/ios/Repm.framework

# Copy in repm
cp ../gh-dl-release/$REPM_REPO/$REPM_VERSION/repm.aar replicache-flutter-sdk/android/
cd replicache-flutter-sdk/ios/
tar -xvf ../../../gh-dl-release/$REPM_REPO/$REPM_VERSION/Repm.framework.tar.gz

# Tar everything up
cd -
tar -czvf replicache-flutter-sdk.tar.gz replicache-flutter-sdk
cd $ORIG

# Add symlinks to make dev builds work
ln -sF `realpath build/replicache-flutter-sdk/android/repm.aar` android
ln -sF `realpath build/replicache-flutter-sdk/ios/Repm.framework` ios
