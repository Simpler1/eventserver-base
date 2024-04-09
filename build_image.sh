#!/usr/bin/env bash

docker system prune -a --volumes

ver=68;
docker build --no-cache --progress=plain --tag zm_eventserver:$ver . 2>&1 | tee build_$ver.log
