#!/bin/bash
ulimit -n 65535
cd /var/local/kworker
./kworker --config=./c 