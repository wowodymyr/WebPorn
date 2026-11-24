#!/bin/bash
# Load a page with video in WPTest, start the first <video> muted and log its state
# every few seconds (tests/media/sites/probe.js); prints the log and libVLC stats.
#   tests/media/sites/run.sh <url> [seconds=40]
set -uo pipefail
WP=$(cd "$(dirname "$0")/../../.." && pwd)
D=/var/mobile/Media/webporn
scp -q "$WP/tests/media/sites/probe.js" iphone:$D/probe.js
ssh iphone "echo '$1' > $D/url.txt; echo 6 > $D/capture-delay.txt; echo 4 > $D/capture-repeat.txt; chown mobile $D/*; rm -f $D/results.txt $D/result.txt; killall WPTest 2>/dev/null; sleep 1; uiopen wptest: ; sleep ${2:-40}; cat $D/results.txt; grep -a 'stats' $D/wpmedia-events.log | sed -n '\$p'; killall -0 WPTest 2>/dev/null && echo alive || echo DEAD; rm -f $D/capture-repeat.txt"
scp -q iphone:$D/screenshot.png "$WP/build/media-site.png" 2>/dev/null
