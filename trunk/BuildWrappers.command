#!/bin/bash

cd ${0%/*}
xcodebuild -configuration Development -target Symbiosis clean
xcodebuild -configuration Beta -target Symbiosis clean
xcodebuild -configuration Deployment -target Symbiosis clean
xcodebuild -configuration Development -target Symbiosis build
xcodebuild -configuration Beta -target Symbiosis build
xcodebuild -configuration Deployment -target Symbiosis build
cp ./Symbiosis.r ./build/Development/Symbiosis.component/Contents/Resources
cp ./Symbiosis.r ./build/Beta/Symbiosis.component/Contents/Resources
cp ./Symbiosis.r ./build/Deployment/Symbiosis.component/Contents/Resources
ditto -ck --rsrc build PreBuiltWrappers.zip
