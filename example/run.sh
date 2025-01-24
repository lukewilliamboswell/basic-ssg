#!/bin/bash
cd "$(dirname "$0")"

set -e

roc check main.roc

roc build --linker=legacy main.roc

./main content/ www/

simple-http-server --index --open --ip 127.0.0.1 www/
