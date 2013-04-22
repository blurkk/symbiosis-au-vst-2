#!/bin/bash

cd ${0%/*}/documentation
if [ -x ./PikaCmd ]
then
	chmod +x ./PikaCmd
else
	cd PikaCmdSource
	./BuildPikaCmd.sh
	cd ..
	mv PikaCmdSource/PikaCmd .
fi
./PikaCmd
if [[ -a $(which doxygen) ]]; then
	# I had problems getting doxygen to parse my .mm properly, but when renamed to .cpp it worked (and no, EXTENSION_MAPPING didn't help)
	mv ../Symbiosis.mm ../Symbiosis.cpp
	doxygen
	mv ../Symbiosis.cpp ../Symbiosis.mm
fi
