#!/bin/sh
# The Mini816's SCC channel B on a socket (em16 -mini816 -sccb tcp:PORT):
# test/mini816b.s echoes what a client sends there at 9600 baud. The
# client must get its text back, no sooner than 9600 baud allows (10 bits
# a character), and the ROM must then print "mini816b: done".
cd "$(dirname "$0")"
AS=../../bin/as; EM=../../bin/em16
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
"$AS" -o "$work/b.bin" mini816b.s > /dev/null || exit 1
port=$((20000 + $$ % 20000))
"$EM" -mini816 -rom "$work/b.bin" -sccb tcp:$port < /dev/null > "$work/out" 2> "$work/err" &
pid=$!
python3 -I - "$port" > "$work/client" <<'PY'
import socket, sys, time
port = int(sys.argv[1]); text = b"hello, Mini816."
for i in range(50):
    try: s = socket.create_connection(("127.0.0.1", port), timeout=5); break
    except OSError: time.sleep(0.1)
t0 = time.time(); s.sendall(text); got = b""
while not got.endswith(b"."):
    d = s.recv(64)
    if not d: break
    got += d
dt = time.time() - t0
print(got.decode(errors="replace"), "slow" if dt >= len(text) * 10 / 9600 else "fast")
PY
i=0
while [ $i -lt 50 ] && kill -0 $pid 2> /dev/null; do sleep 0.1; i=$((i + 1)); done
kill $pid 2> /dev/null
out=$(tr -d '\r' < "$work/out" | grep -a '^mini816b: ')
client=$(cat "$work/client")
echo "$out"
[ "$out" = "mini816b: done" ] && [ "$client" = "hello, Mini816. slow" ] && exit 0
echo "client '$client'"; cat "$work/err"
exit 1
