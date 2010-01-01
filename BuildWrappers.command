#!/bin/bash

cd ${0%/*}
xcodebuild -configuration Development clean
xcodebuild -configuration Beta clean
xcodebuild -configuration Deployment clean
xcodebuild -configuration Development build
xcodebuild -configuration Beta build
xcodebuild -configuration Deployment build
ditto -ck --rsrc build PreBuiltWrappers.zip
