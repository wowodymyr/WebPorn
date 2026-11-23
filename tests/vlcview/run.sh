#!/bin/bash
# Play a URL in VLCView for N seconds and print libvlc's stats (+ VNC screenshot).
#   tests/vlcview/run.sh <url> [seconds=15] ["x y w h"]
WP=$(cd "$(dirname "$0")/../.." && pwd)
D=/var/mobile/Media/webporn
ssh iphone "echo '$1' > $D/vlc-url.txt; echo '${2:-15}' > $D/vlc-seconds.txt; echo '${3:-}' > $D/vlc-frame.txt; rm -f $D/vlc-result.txt; killall VLCView 2>/dev/null; sleep 1; uiopen vlcview: ; sleep \$((${2:-15} - 3))"
"$WP/tests/vnc.sh" capture "$WP/build/vlcview/screen.png" 2>/dev/null
ssh iphone "sleep 5; cat $D/vlc-result.txt"
