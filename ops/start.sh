#!/bin/sh
set -eu
bundle exec ruby /opt/hefesto/preflight.rb --ready
rm -f /app/tmp/pids/server.pid
exec "$@"
