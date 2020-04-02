ORIG=`pwd`
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT=$DIR/../
PACKAGE_VERSION=`git describe --tags`

echo "Building Flutter SDK..."

cd $ROOT
set -x

# Copy the local repo into the output dir
rm -rf build
mkdir build
cd build
mkdir replicache-flutter-sdk
ls ../ | grep -v build | grep -v sample | grep -v tool | grep -v gh-dl-release | grep -v doc | xargs -I{} cp -R ../{} replicache-flutter-sdk/{}

# Stamp the version number
sed -i "" "s/version: 0.0.0+dev/version: $PACKAGE_VERSION/" replicache-flutter-sdk/pubspec.yaml
