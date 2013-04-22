#!/bin/bash

XCODE_PATH=
if [ -e /Developer ]; then
        XCODE_PATH=/Developer/usr/bin/
fi

cd "${0%/*}"

${XCODE_PATH}xcodebuild -configuration Development -target Symbiosis clean
${XCODE_PATH}xcodebuild -configuration Beta -target Symbiosis clean
${XCODE_PATH}xcodebuild -configuration Deployment -target Symbiosis clean
${XCODE_PATH}xcodebuild -configuration Development -target Symbiosis build
${XCODE_PATH}xcodebuild -configuration Beta -target Symbiosis build
${XCODE_PATH}xcodebuild -configuration Deployment -target Symbiosis build
cp ./Symbiosis.r ./build/Development/Symbiosis.component/Contents/Resources
cp ./Symbiosis.r ./build/Beta/Symbiosis.component/Contents/Resources
cp ./Symbiosis.r ./build/Deployment/Symbiosis.component/Contents/Resources
ditto -ck --rsrc build PreBuiltWrappers.zip
