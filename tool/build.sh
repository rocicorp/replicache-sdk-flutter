ORIG=`pwd`
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT=$DIR/../
PACKAGE_VERSION=`git describe --tags`
REPM_VERSION='c27ae0da73045a7149c29ddfffc5c875b1b5db4f'

echo "Building Flutter SDK..."

cd $ROOT
set -x

rm -rf build
mkdir build
cd build

# Copy the local repo into the output dir
mkdir replicache-flutter-sdk
ls ../ | grep -v build | grep -v sample | grep -v tool | grep -v gh-dl-release | grep -v doc | xargs -I{} cp -R ../{} replicache-flutter-sdk/{}

# Build repm
git clone https://github.com/rocicorp/replicache-client
cd replicache-client
git reset --hard $REPM_VERSION
./build.sh
cd ..
# There might be symlinks already there
rm replicache-flutter-sdk/ios/Repm.framework
rm replicache-flutter-sdk/android/repm.aar
cp -R replicache-client/build/Repm.framework replicache-flutter-sdk/ios/
cp replicache-client/build/repm.aar replicache-flutter-sdk/android/

# Stamp the version number
sed -i "" "s/version: 0.0.0+dev/version: $PACKAGE_VERSION/" replicache-flutter-sdk/pubspec.yaml

cd $ORIG
