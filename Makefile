# Command lines below begin with real tab characters.
.PHONY: all run clean

all: aidtrack

aidtrack: main.o
	ld -m elf_i386 main.o -o aidtrack

main.o: main.asm
	nasm -f elf32 main.asm -o main.o

run: aidtrack
	./aidtrack

clean:
	rm -f main.o aidtrack
