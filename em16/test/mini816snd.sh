#!/bin/sh
# The Mini816's speaker under em16 -mini816 -wav: test/mini816snd.s plays
# three tones (timer 1 on PB7, PB7 toggled, the shift register on CB2);
# in the WAV file each must be there for 250 ms at its pitch to 0.2%,
# silence (a held level) around them, and CB2's only with -soundcb2.
cd "$(dirname "$0")"
AS=../../bin/as; EM=../../bin/em16
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
"$AS" -o "$work/snd.bin" mini816snd.s > /dev/null || exit 1
ok=0
for cb2 in -soundcb2 ""; do
  out=$(perl -e 'alarm 30; exec @ARGV' "$EM" -mini816 -turbo -rom "$work/snd.bin" -wav "$work/s.wav" $cb2 < /dev/null 2> /dev/null |
        tr -d '\r' | grep -a '^mini816snd: ')
  [ "$out" = "mini816snd: done" ] || { echo "mini816snd: the ROM: '$out'"; ok=1; continue; }
  python3 -I - "$work/s.wav" "$cb2" <<'END' || ok=1
import sys, wave, array
w = wave.open(sys.argv[1])
rate = w.getframerate()
s = array.array('h', w.readframes(w.getnframes()))
want = [('A', 7372800 / (2 * 3686)), ('B', 7372800 / (2 * (20 + 5 * 1470)))]
if sys.argv[2]:
    want.append(('C', 7372800 / (8 * 2 * (228 + 2))))
win = rate // 100                                   # 10 ms
active = [sum(v * v for v in s[i:i + win]) / win > 1000 ** 2 for i in range(0, len(s) - win + 1, win)]
tones, start = [], None
for i, a in enumerate(active + [False]):
    if a and start is None: start = i
    if not a and start is not None: tones.append((start * win, i * win)); start = None
bad = []
if len(tones) != len(want):
    bad.append(f'{len(tones)} tones, not {len(want)}')
for (name, f), (a, b) in zip(want, tones):
    ms = (b - a) * 1000 / rate
    x = [i + s[i] / (s[i] - s[i + 1]) for i in range(a + win * 2, b - win * 2) if s[i] > 0 >= s[i + 1]]
    got = (len(x) - 1) * rate / (x[-1] - x[0]) if len(x) > 1 else 0
    if not 240 <= ms <= 280: bad.append(f'{name} lasts {ms:.0f} ms')
    if abs(got - f) > f * 0.002: bad.append(f'{name} at {got:.2f} Hz, not {f:.2f}')
quiet = max(abs(v) for v in s[:win * 4])
if quiet > 50: bad.append(f'{quiet} before the first')
for (_, b), (c, _) in zip(tones, tones[1:]):
    quiet = max(abs(v) for v in s[b + win * 3:c])
    if quiet > 50: bad.append(f'{quiet} between tones')
secs = len(s) / rate
if not 1.0 <= secs <= 1.2: bad.append(f'{secs:.2f} s long')
if bad:
    print('mini816snd' + (' ' + sys.argv[2] if sys.argv[2] else '') + ': ' + '; '.join(bad)); sys.exit(1)
END
done
[ $ok = 0 ] && echo "mini816snd: ok (PB7 by timer 1 and by the CPU, CB2 with -soundcb2)"
exit $ok
