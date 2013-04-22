#!/bin/bash

chmod +x ./PikaPrompt
if [ ! -d /usr/local ]; then
	sudo mkdir /usr/local
	sudo chown root:wheel /usr/local
	sudo chmod 755 /usr/local
fi
if [ ! -d /usr/local/bin ]; then
	sudo mkdir /usr/local/bin
	sudo chown root:wheel /usr/local/bin
	sudo chmod 755 /usr/local/bin
fi
sudo cp ./PikaCmd /usr/local/bin/
sudo cp ./PikaPrompt /usr/local/bin/
sudo cp systools.pika /usr/local/bin/
