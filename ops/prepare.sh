#!/bin/sh
set -eu
bundle exec ruby /opt/hefesto/preflight.rb
bundle exec rails db:chatwoot_prepare
bundle exec ruby /opt/hefesto/preflight.rb --ready
