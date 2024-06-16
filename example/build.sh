#!/bin/bash
cd "$(dirname "$0")"

set -e

roc check main.roc

roc main.roc content/ www/

simple-http-server www/
