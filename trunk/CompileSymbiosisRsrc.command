#!/bin/bash

cd ${0%/*}
/Developer/Tools/Rez -o Symbiosis.rsrc -d SystemSevenOrLater=1 -useDF -script Roman -d ppc_YES -d i386_YES -arch ppc -arch i386 -isysroot /Developer/SDKs/MacOSX10.4u.sdk Symbiosis.r
