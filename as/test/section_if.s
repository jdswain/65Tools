; A SECTION directive inside an IF block. What follows it in the block is
; skipped or assembled in the new section as the condition says. The
; directive itself is not conditional: the text after it belongs to the
; section it names, also after the block.
	section "a"
	org := $1000
m = 1
	data.b $a1
if m == 2 {
	section "b"
	org := $2000
	data.b $ee
	data.w not_defined_anywhere
}
	section "a"
	data.b $a2		; a was left inside the block above
if m == 1 {
	section "b"
	org := $3000
	data.b $b1
	{
		section "a"
		data.b $a3
	}
	data.b $a4
} else {
	data.b $ee
}
	data.b $a5
	section "b"
	data.b $b2
