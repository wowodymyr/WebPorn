#!/bin/bash
# Drive the iPhone over VNC (Veency): screenshots, taps, typing.
#   tests/vnc.sh capture out.png | tests/vnc.sh click X Y | tests/vnc.sh type TEXT | tests/vnc.sh <vncdo args...>
# vncdotool lives in build/vncpkgs (pip install --target build/vncpkgs vncdotool).
WP=$(cd "$(dirname "$0")/.." && pwd)
VNC=${VNC_HOST:-192.168.0.110::5900}
PASS=${VNC_PASSWORD:-123}
case "$1" in
    click) set -- move "$2" "$3" click 1 ;;
esac
PYTHONPATH=$WP/build/vncpkgs exec python3 "$WP/build/vncpkgs/bin/vncdo" -s "$VNC" -p "$PASS" "$@"
