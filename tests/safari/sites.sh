#!/bin/bash
# Open each URL in MobileSafari (legacy WebKit + swapped engine) and report whether
# Safari survived, how many resources finished (WebPornSafari's log) and a VNC
# screenshot: build/safari/sites/<host>.png
#   tests/safari/sites.sh [url...]
set -uo pipefail
WP=$(cd "$(dirname "$0")/../.." && pwd)
HOST=iphone
OUT=$WP/build/safari/sites
mkdir -p "$OUT"
URLS=("$@")
[ ${#URLS[@]} -gt 0 ] || URLS=(https://news.ycombinator.com/ https://github.com/WebKit/WebKit
    https://developer.mozilla.org/en-US/ https://www.google.com/search?q=webkit https://www.bbc.com/news
    https://en.m.wikipedia.org/wiki/WebKit https://www.reddit.com/ https://www.youtube.com/
    https://twitter.com/ https://www.apple.com/)
crashes() { ssh $HOST "ls /var/mobile/Library/Logs/CrashReporter/" | grep -c '^MobileSafari_'; }
for url in "${URLS[@]}"; do
    name=$(echo "$url" | sed -E 's|https?://||; s|[/?=&]+|_|g; s|_$||')
    before=$(crashes)
    finished=$(ssh $HOST "killall MobileSafari 2>/dev/null; sleep 1; uiopen '$url'; sleep ${WAIT:-25}; grep -c didFinishLoading /var/mobile/Media/webporn/safari.log")
    alive=$(ssh $HOST "launchctl list | grep -q UIKitApplication:com.apple.mobilesafari && echo alive || echo dead")
    after=$(crashes)
    "$WP/tests/vnc.sh" capture "$OUT/$name.png" 2>/dev/null && shot=$name.png || shot=-
    crash=-; [ "$after" -gt "$before" ] && crash=CRASH
    printf '%-45s | %4s loads | %s | %s | %s\n' "$url" "$finished" "$alive" "$crash" "$shot"
done
