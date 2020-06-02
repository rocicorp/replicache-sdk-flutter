ORIG=`pwd`
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT=$DIR/../
PACKAGE_VERSION=`git describe --tags`
REPM_VERSION='7dc06be02dc06caf8f91b26ad06c7f9f4d9bfb1b'

echo "Building Flutter SDK..."

cd $ROOT
set -x

rm -rf build
mkdir build
cd build

# Copy the local repo into the output dir
mkdir replicache-sdk-flutter
ls ../ | grep -v build | grep -v sample | grep -v tool | grep -v gh-dl-release | grep -v doc | xargs -I{} cp -R ../{} replicache-sdk-flutter/{}

# Build repm
git clone https://github.com/rocicorp/replicache-client
cd replicache-client
git reset --hard $REPM_VERSION
./build.sh
cd ..
# There might be symlinks already there
rm replicache-sdk-flutter/ios/Repm.framework
rm replicache-sdk-flutter/android/repm.aar
cp -R replicache-client/build/Repm.framework replicache-sdk-flutter/ios/
cp replicache-client/build/repm.aar replicache-sdk-flutter/android/

# Stamp the version number
sed -i "" "s/version: 0.0.0+dev/version: $PACKAGE_VERSION/" replicache-sdk-flutter/pubspec.yaml

zip -r replicache-sdk-flutter.zip replicache-sdk-flutter

cd $ORIG
