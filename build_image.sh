#!/usr/bin/env bash

ver=49;
docker build --no-cache --progress=plain --tag zm_eventserver:$ver . 2>&1 | tee build_$ver.log
