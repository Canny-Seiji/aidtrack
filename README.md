# AidTrack

## Barangay Relief and Water Distribution System

AidTrack is a complete, offline classroom transaction system written in
**32-bit x86 NASM for Linux**. It records beneficiaries, supply intake and
water/relief releases. It uses terminal input/output, an ASCII/ANSI menu,
procedures, a printing macro, `%define` directives, and file reading/writing.

Use fictional data for demonstrations. This is not a production government
system, identity-verification service, eligibility engine, or medical tool.

## Problem and solution

Manual distribution records can lead to missing entries, incorrect stock
counts and repeated claims. AidTrack keeps an auditable transaction journal,
checks available stock before a release, and records which beneficiaries
have already received each supply. Its scope is one barangay and one
distribution cycle per journal.

## Files and build

Place `main.asm` and this `README.md` in your `aidtrack` repository. The
Makefile from the earlier milestones still works: its input remains
`main.asm` and its output remains `aidtrack`.

Run inside **Linux**, such as a GitHub Codespace or Ubuntu under WSL.
Windows PowerShell cannot directly run this Linux ELF/int-0x80 program.
Your Linux host must support execution of 32-bit x86 programs.

```bash
# Install only if these tools are missing.
sudo apt-get update
sudo apt-get install -y nasm binutils make

# Build and execute.
nasm -f elf32 main.asm -o main.o
ld -m elf_i386 main.o -o aidtrack
./aidtrack
```

Alternatively, use `make run` with your existing Makefile. Always run the
program from the same working directory to use the same journal.

Add these entries to your repository's `.gitignore`:

```gitignore
*.o
/aidtrack
/aidtrack.dat
```

Do not commit real beneficiary information or the journal to public GitHub.

## Main menu and implemented features

| Option | Behavior |
|---|---|
| 1. Register beneficiary | Adds a new, unique ID and full name; does not overwrite an existing person. |
| 2. Add supply stock | Adds water containers or relief packages after numeric/capacity validation. |
| 3. Distribute water | Checks ID, prior water claim and available water, then records the release. |
| 4. Distribute relief packages | Performs the same checks for relief stock and its separate claim flag. |
| 5. View inventory | Displays the remaining quantities of both supplies. |
| 6. Read transaction history | Seeks to the start of the file and reads saved transactions as a readable list. |
| 7. Generate report | Displays cumulative beneficiary/transaction counts, received/distributed quantities and remaining stock. |
| 8. Exit | Closes the journal, releases its lock, and exits with status 0. |

All successful changes are saved automatically. A separate Save command
is not necessary. Rejected operations are not written as successful transactions.

## Program flow: single-paragraph summary

The program begins at `_start` by opening or creating `aidtrack.dat` without
erasing previous records, acquiring an exclusive advisory lock, and reading
the journal to rebuild beneficiaries, stock and claim flags. It then displays
the colored ASCII menu and validates the selected operation. Registration
collects a text ID and full name, stock intake collects a supply type and
quantity, and distribution collects an ID and quantity for water or relief.
Each proposed change is checked by `validate_event`; a valid event is appended
to the file and synchronized with `fsync` before `apply_event` updates memory.
The program then displays a transaction confirmation and current inventory.
History reads the actual journal, while the cumulative report summarizes
the reconstructed counters. `%define` directives name constants, the `PRINT`
macro prepares a text address, and procedures called using `CALL` organize
input, validation, calculations, printing and storage, returning through
`RET` when appropriate. Control returns to the menu after each operation
until Exit closes the file and terminates through the Linux exit system call.

## Business rules and limits

- ID: 1–15 digits stored as text; `0001` is different from `1`.
- Full name: 1–63 printable ASCII characters, including spaces; not only spaces.
  Names with Unicode characters such as ñ are not supported in this version.
- Beneficiary capacity: 100 unique IDs.
- Amount: a positive whole number from 1 to 9,999; signs, decimals and spaces
  within numeric input are rejected. Leading numeric zeros are accepted.
- Each supply stock: 0–999,999 units.
- Each selection releases a quantity of containers/packages, not individual
  contents within a relief package.
- One water allocation and one relief allocation per beneficiary per journal.
  The quantity must be correct before confirming it; a second allocation is
  rejected even if the first allocation was small.
- Journal capacity: 5,000 successful transactions, including registration
  and stock intake. This also keeps cumulative 32-bit counters bounded.
- There are no edit, delete, reversal, administrator-login or cycle-reset
  operations. These are outside this version's scope.
- Reports are **cumulative**, not daily: timestamps are not collected.

## How a transaction is committed

1. Clear a temporary event and collect the required input.
2. Validate its fields, identity, claim status and stock/capacity.
3. If invalid, display the reason and leave saved state unchanged.
4. If valid, calculate its checksum and append the 96-byte event.
5. Call `fsync` and check the result.
6. Update the in-memory state using `apply_event`.
7. Display the saved transaction number and remaining inventory.

This ordering prevents a normal file-write failure from being reported as a
successful in-memory transaction. It is **not a full database atomicity
guarantee**. A failure or crash can leave an incomplete final record, or a
complete record whose durability was uncertain at the time of failure. Never
blindly retry a stock addition after an I/O error; inspect/replay the journal.

## File handling and format

The journal is `aidtrack.dat` in the current working directory. It is a
binary file, not a text document; do not edit it in a text editor. Menu option
6 translates the records into readable transaction history.

The program uses Linux i386 `open`, `read`, `write`, `lseek`, `fsync`, `flock`
and `close`. The file is opened read/write with create and append flags,
**without truncation**. A new file uses mode 0600 (owner read/write).

Each record has this fixed layout:

| Byte offset | Size | Contents                                                                                 |
|-------------|------|------------------------------------------------------------------------------------------|
| 0           | 4    | Format magic `0x41494431`                                                                |
| 4           | 4    | Type: 1 registration, 2 water intake, 3 relief intake, 4 water release, 5 relief release |
| 8           | 4    | Quantity; zero for registration                                                          |
| 12          | 16   | Zero-terminated, padded beneficiary ID; empty for intake                                 |
| 28          | 64   | Zero-terminated, padded name; used for registration                                      |
| 92          | 4    | Additive checksum over the preceding 23 doublewords                                      |

Integers use x86 little-endian representation. Record order provides the
transaction number; it is not stored as a separate field. The checksum is
not cryptographic and cannot prevent deliberate record manipulation.

On startup, full records are checked and replayed. An invalid record,
incomplete final record or impossible state transition stops startup
without modifying the journal. Preserve the file and restore a known-good
backup rather than automatically deleting/truncating it. The file lock is
advisory: it protects against other cooperating AidTrack processes, not
arbitrary editors or hostile software.

For a separate demonstration cycle, stop the program, make a backup and
use a separate working directory with no `aidtrack.dat`. Do not discard
real records merely to bypass claim checks.

## Required course concepts

| Concept                | Implementation                                                                         |
|------------------------|----------------------------------------------------------------------------------------|
| NASM 32-bit            | `BITS 32`, ELF32 build, `int 0x80`                                                     |
| Input/output           | `read_line`, `ask_number`, `puts`, `print_uint`                                        |
| Menu and ASCII art     | `menu`, `_start` comparisons and jumps                                                 |
| ANSI colors            | Escape byte 27 with `[1;36m` and `[0m`                                                 |
| Procedures             | Registration, stock, shared distribution, validation, replay, reports and file helpers |
| Macros                 | `%macro PRINT 1` prepares ECX and calls `puts`                                         |
| Define directives      | Named syscalls, limits, flags and record offsets                                       |
| Arithmetic             | Decimal parsing, stock addition/subtraction and decimal output via DIV                 |
| Memory/addresses       | `.data`, `.bss`, fixed-size records and indexed arrays                                 |
| File write             | `commit_event` appends the record and checks synchronization                           |
| File read              | Startup replay and option 6 history                                                    |
| Stack                  | PUSH/POP register preservation and CALL/RET                                            |
| Transaction validation | Duplicate ID/claim, stock availability and capacity checks                             |

## Important procedures and register contracts

- `read_line`: fixed `input_buffer`; returns length, -1 for invalid input,
  or -2 for EOF/read error. Preserves other registers.
- `ask_number`: ECX prompt, EAX maximum; returns a valid positive integer
  in EAX. It repeats malformed input and preserves other registers.
- `valid_id` / `valid_name`: ECX string address; return boolean in EAX.
- `find_person`: ECX ID; returns a record address or zero in EAX.
- `validate_event`: returns 0 for valid, or error 1–7, without updating state.
- `apply_event`: updates RAM from a validated saved/replayed event.
- `puts`: ECX NUL-terminated string; preserves registers.
- `print_uint`: EAX integer; preserves registers.
- `write_all`: EBX descriptor, ECX address, EDX size; retries interrupted
  writes and finishes short writes. Failure terminates instead of returning success.

## Demonstration and manual acceptance tests

Start in an empty demonstration directory and use fictional records.

1. View inventory: both supplies must be zero.
2. Register `0001`, `Juan Dela Cruz`.
3. Register `0002`, `Maria Santos`.
4. Add 25 water containers and 10 relief packages.
5. Distribute 5 water containers to `0001`: remaining water 20.
6. Distribute 2 relief packages to `0001`: remaining relief 8.
7. Read history: six saved transactions, in their original order.
8. Generate report: two beneficiaries; received water 25/relief 10;
   distributed water 5/relief 2; remaining water 20/relief 8.
9. Attempt another water allocation to `0001`: rejected, no stock change.
10. Attempt to register `0001` again: rejected, original record retained.
11. Request 21 water containers for `0002`: rejected, water stays 20.
12. Request exactly 20 water containers for `0002`: water reaches zero.
13. Exit and restart in the same directory: data and claim checks remain.
14. Try blank input, letters, negative quantities, fractions, enormous
    numbers and overlong text. Invalid values must not update inventory.
15. Start a second instance while the first is running: the second must fail
    to lock the journal instead of writing to it concurrently.

After a deliberate exit, `echo $?` should print `0`.

## Development steps

1. Established the Linux NASM project, constants, menu and printing macro.
2. Added complete-line input, validation and menu branching.
3. Implemented beneficiary IDs and names as text records.
4. Added integer stock counters and ASCII/integer conversions.
5. Added shared water/relief validation and arithmetic.
6. Replaced the one-record prototype with a bounded beneficiary table.
7. Designed a single journal that stores all successful state changes.
8. Added replay, checksums, locking and failure handling.
9. Implemented file-backed history and cumulative reports.
10. Ran behavioral/failure checks and documented limitations and native tests.