#!/usr/bin/env bash
if [ -d build ]
then
  rm -rf build
fi

mkdir -p build
touch stub
pub get
cp -R bin build/
rm -rf build/bin/packages
cp pubspec.yaml dslink.json build/
cd build
zip -r ../../../files/dslink-dart-macos.zip .
