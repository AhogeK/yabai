#!/bin/bash

rm /tmp/yabai-sa-debug.log

make deploy

sleep 5

yabai --stop-service

sleep 3

sudo yabai --uninstall-sa

sleep 3

sudo yabai --load-sa

sleep 5

killall Dock

echo "wait 10s to start service"

sleep 10

yabai --start-service

echo "wait 5s to create"

sleep 5

yabai -m space --create

sleep 10

echo "log show --predicate 'process == "Dock" AND message CONTAINS "yabai"' --last 2m --info"
log show --predicate 'process == "Dock" AND message CONTAINS "yabai"' --last 2m --info
