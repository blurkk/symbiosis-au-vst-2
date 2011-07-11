#!/bin/bash

# If google code upload python fails install python v2.6 (with http://www.macports.org/ : sudo port install python26).

version=1_3b
todayLong=$(date +%Y-%m-%d)
todayShort=$(date +%Y%m%d)
filename=Symbiosis_v$version'_'$todayShort.zip

rm -r -f temp
svn export https://symbiosis-au-vst.googlecode.com/svn/trunk temp
ditto -ck --rsrc temp $filename
./googlecode_upload.py -s "Entire trunk from repository $todayLong" -p "symbiosis-au-vst" -u malstrom72 -l Featured $filename
rm $filename
rm -r -f temp
