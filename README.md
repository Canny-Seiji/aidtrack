# AidTrack

**Barangay Relief and Water Distribution System**

Repository name: `aidtrack`. The executable is also named `aidtrack`.

A single-operator, offline classroom prototype for one barangay's
emergency-resource records, written in 32-bit NASM for Linux.
Use fictional beneficiaries during development and demonstration.

## Milestone 1: startup and menu display

The program displays an ASCII banner, previews eight planned operations,
and exits with status 0. The options are not selectable yet.
No inventory, personal data or transaction files are created at this stage.

Implemented concepts: NASM directives, initialized data, byte lengths,
register arguments, a printing macro, CALL/RET procedures and Linux output/exit.
Input validation, branches, transactions, inventory and file read/write
will be introduced incrementally rather than hidden in a completed program.

## Build and run in a Linux Codespace

Prerequisites: NASM and GNU binutils; make is optional.
The host must support running 32-bit x86 Linux executables.

```bash
nasm -f elf32 main.asm -o main.o
ld -m elf_i386 main.o -o aidtrack
./aidtrack
echo $?
```

Alternatively, run `make run`. The last command above should show `0`.
If NASM is missing, install it in your Codespace with
`sudo apt-get update` followed by `sudo apt-get install -y nasm binutils make`.

## Execution flow

Linux enters `_start`. Each PRINT macro invocation sets ECX/EDX and calls
`write_stdout`. That procedure requests Linux write with `int 0x80` and
returns with RET. Finally, `exit_program` requests Linux exit and never returns.

## Check before moving on

- Does the complete menu appear with a straight border?
- Does the shell prompt return immediately? That is expected for this milestone.
- Does `echo $?` show 0 immediately after execution?
- Can you explain why ECX holds an address, and EDX holds a length?

## Next feature

Read a menu choice, validate it, loop for another choice, and implement option 8.
There is deliberately no file handling yet. File persistence will accompany
the first stored records and transactions in later milestones.

## Verification note

Native NASM compilation was unavailable in the authoring environment.
Run the build and checks above in your Codespace.
