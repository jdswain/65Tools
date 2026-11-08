#!/bin/sh
# The ENC424J600 under em16 -fpga -net udp:...: test/eth.s, a boot ROM,
# drives it as a driver would, and a peer here, on the UDP ports em16's
# -net udp joins it to, is the other end of the cable. The peer checks the
# frames the ROM sends and answers them; the ROM's "eth: " lines must be
# the ones below.
cd "$(dirname "$0")"
AS=../../bin/as; EM=${EM:-../../bin/em16}
work=$(mktemp -d); trap 'kill $peer 2> /dev/null; rm -rf "$work"' EXIT
"$AS" -o "$work/eth.bin" eth.s > /dev/null || exit 1
ports=$(python3 -c "
import socket
s = [socket.socket(socket.AF_INET, socket.SOCK_DGRAM) for _ in range(2)]
for x in s: x.bind(('127.0.0.1', 0))
print(*[x.getsockname()[1] for x in s])")
set -- $ports; mine=$1; theirs=$2
python3 - "$theirs" "$mine" "$work/ready" > "$work/peer" 2>&1 <<'END' &
import socket, sys, zlib
me, em = int(sys.argv[1]), int(sys.argv[2])
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('127.0.0.1', me)); s.settimeout(20); open(sys.argv[3], 'w').close()
mac = bytes.fromhex('020000123456'); peer = bytes.fromhex('0200000000aa')
def frame(da, text): return da + peer + b'\x88\xb5' + text + b'\0'
def check(f, n):
    want = b'\xff' * 6 + mac + b'\x88\xb5' + b'hello from em16\0'
    want += bytes(60 - len(want))
    print('frame %d %s' % (n, 'ok' if f == want else 'bad ' + f.hex()))
f, _ = s.recvfrom(2000); check(f, 1)
for da, t in ((mac, b'one'), (bytes.fromhex('020000000099'), b'two'), (b'\xff' * 6, b'three')):
    s.sendto(frame(da, t), ('127.0.0.1', em))
f, _ = s.recvfrom(2000); check(f, 2)
for da, t in ((bytes.fromhex('01000000012c'), b'four'), (bytes.fromhex('01005e000001'), b'five')):
    s.sendto(frame(da, t), ('127.0.0.1', em))
END
peer=$!
n=0; while [ ! -e "$work/ready" ] && [ $n -lt 100 ]; do sleep 0.05; n=$((n + 1)); done
perl -e 'alarm 30; exec @ARGV' "$EM" -fpga -bootrom "$work/eth.bin" -net udp:$mine:$theirs -mac 02:00:00:12:34:56 \
  < /dev/null 2> "$work/err" | tr -d '\r' | grep -a '^eth: ' > "$work/out"
wait $peer
cat "$work/peer" "$work/out"
cat > "$work/want" <<'END'
frame 1 ok
frame 2 ok
eth: id 22 mac 020000123456
eth: estat 5500 phstat3 0058
eth: tx 0040 0000
eth: pkts D502 08
eth: rx 4048 0040 C0001000: one
eth: rx 4090 0040 C0020000: three
eth: pkts 5500 00
eth: rx 40D8 0040 C0010200: four
eth: pkts 5500
eth: dma A953 copy 89ABCD
eth: dma2 40 0102030405060708
eth: done
END
cat "$work/peer" "$work/out" | cmp -s - "$work/want" || { echo "eth: FAIL"; diff "$work/want" - <<X
$(cat "$work/peer" "$work/out")
X
cat "$work/err"; exit 1; }
echo "eth: ok"
