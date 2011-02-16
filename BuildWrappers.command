#!/bin/bash

cd ${0%/*}
xcodebuild -configuration Development clean
xcodebuild -configuration Beta clean
xcodebuild -configuration Deployment clean
xcodebuild -configuration Development build
xcodebuild -configuration Beta build
xcodebuild -configuration Deployment build
cp ./Symbiosis.r ./build/Development/Symbiosis.component/Contents/Resources
cp ./Symbiosis.r ./build/Beta/Symbiosis.component/Contents/Resources
cp ./Symbiosis.r ./build/Deployment/Symbiosis.component/Contents/Resources
ditto -ck --rsrc build PreBuiltWrappers.zip
