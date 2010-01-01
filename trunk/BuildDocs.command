#!/bin/bash

cd ${0%/*}/documentation
if [ -x ./PikaCmd ]
then
	chmod +x ./PikaCmd
else
	echo Building PikaCmd
	g++ -x c++ -pipe -Wno-trigraphs -fno-rtti -O3 -Wreturn-type -Wunused-variable -DNDEBUG -fmessage-length=0 -funroll-loops -ffast-math -fstrict-aliasing -msse3 -fvisibility=hidden -fvisibility-inlines-hidden -fno-threadsafe-statics -mmacosx-version-min=10.4 -o ./PikaCmd PikaCmdAmalgam.cpp
fi
./PikaCmd
if [[ -a $(which doxygen) ]]; then doxygen; fi
