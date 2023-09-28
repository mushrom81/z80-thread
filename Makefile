build: thread.sna thread.tap

run: thread.sna thread.tap
	zesaurx --tape thread.tap

thread.sna: thread.asm
	sjasmplus --lst thread.asm

thread.tap: thread.asm
	sjasmplus --lst thread.asm
