#!/bin/bash

cd "${0%/*}"
/Developer/Tools/Rez -d SystemSevenOrLater=1 -useDF -script Roman -o Symbiosis.rsrc Symbiosis.r
