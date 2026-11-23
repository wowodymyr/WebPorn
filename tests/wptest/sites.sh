#!/bin/bash
# Load each URL in WPTest (swapped engine) and report title / load error / crash.
#   tests/wptest/sites.sh [url...]      (default: a fixed list of modern sites)
# Screenshots: build/wptest/sites/<host>.png
set -uo pipefail
WP=$(cd "$(dirname "$0")/../.." && pwd)
HOST=iphone
OUT=$WP/build/wptest/sites
mkdir -p "$OUT"
URLS=("$@")
[ ${#URLS[@]} -gt 0 ] || URLS=(https://news.ycombinator.com/ https://github.com/WebKit/WebKit
    https://developer.mozilla.org/en-US/ https://www.google.com/search?q=webkit https://www.bbc.com/news
    https://en.m.wikipedia.org/wiki/WebKit https://www.reddit.com/ https://www.youtube.com/
    https://twitter.com/ https://www.apple.com/)
D=/var/mobile/Media/webporn
crashes() { ssh $HOST "ls /var/mobile/Library/Logs/CrashReporter/" | grep -c '^WPTest_'; }
for url in "${URLS[@]}"; do
    name=$(echo "$url" | sed -E 's|https?://||; s|[/?=&]+|_|g; s|_$||')
    before=$(crashes)
    ssh $HOST "echo '$url' > $D/url.txt; chown mobile $D/url.txt; rm -f $D/result.txt $D/error.txt $D/screenshot.png; killall WPTest 2>/dev/null; sleep 1; uiopen wptest: ; sleep ${WAIT:-30}"
    title=$(ssh $HOST "sed -n 2p $D/result.txt 2>/dev/null")
    error=$(ssh $HOST "cat $D/error.txt 2>/dev/null" | grep -o 'Code=-*[0-9]* "[^"]*"' | head -1)
    alive=$(ssh $HOST "killall -0 WPTest 2>/dev/null && echo alive || echo dead")
    after=$(crashes)
    scp -q "$HOST:$D/screenshot.png" "$OUT/$name.png" 2>/dev/null && shot=$name.png || shot=-
    crash=-; [ "$after" -gt "$before" ] && crash=CRASH
    printf '%-45s | %-40.40s | %s | %s | %s %s\n' "$url" "${title:-$error}" "$alive" "$crash" "$shot"
done
