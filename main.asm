; ============================================================
; AidTrack: Barangay Relief and Water Distribution System
; Milestone 1: display the menu and terminate successfully.
; Environment: NASM, 32-bit x86 Linux, int 0x80 system calls.
;
; Not implemented yet: input, transactions, inventory and files.
; The menu is a preview, not a working selection screen yet.
; ============================================================

BITS 32

; FEATURE 1A: named constants.
; %define substitutes names before assembly. It allocates no RAM.
%define SYS_EXIT  1
%define SYS_WRITE 4
%define STDOUT    1
%define LF        10

; FEATURE 1B: reusable output macro.
; %1 = address of text, %2 = its byte length.
; This expands at each use; write_stdout executes at runtime.
%macro PRINT 2
    mov ecx, %1
    mov edx, %2
    call write_stdout
%endmacro

section .data
    ; FEATURE 1C: initialized text and ASCII border.
    ; Explicit lengths are used, so no trailing zero is required.
    banner db '+------------------------------------------+', LF
           db '|                 AidTrack                 |', LF
           db '|      Barangay Emergency Resources        |', LF
           db '+------------------------------------------+', LF
    banner_len equ $ - banner

    ; Planned operations. Input and selection come next.
    menu db '1. Register beneficiary', LF
         db '2. Add supply stock', LF
         db '3. Distribute water', LF
         db '4. Distribute relief package', LF
         db '5. View inventory', LF
         db '6. View transaction history', LF
         db '7. Generate distribution report', LF
         db '8. Exit', LF, LF
    menu_len equ $ - menu

    stage_note db 'Milestone 1: menu preview only. Program finished.', LF
    stage_note_len equ $ - stage_note

section .text
    global _start

; FEATURE 1D: entry point and high-level sequence.
; Linux starts execution here. Print three blocks, then exit.
_start:
    PRINT banner, banner_len
    PRINT menu, menu_len
    PRINT stage_note, stage_note_len
    call exit_program

; FEATURE 1E: shared printing procedure.
; Input: ECX = text address; EDX = byte count.
; Output: EAX = bytes written, or a negative Linux error result.
; Changes: EAX and EBX. ECX/EDX are not changed by this procedure.
; Linux write(1, text, length) sends bytes to standard output.
; Later milestones will add handling for failed/partial writes.
write_stdout:
    mov eax, SYS_WRITE
    mov ebx, STDOUT
    int 0x80
    ret

; FEATURE 1F: graceful termination.
; EAX selects exit; EBX is status 0 (success).
; Unlike write_stdout, this procedure never returns to its caller.
exit_program:
    mov eax, SYS_EXIT
    xor ebx, ebx
    int 0x80

; Mark the stack non-executable in the linked Linux executable.
section .note.GNU-stack noalloc noexec nowrite progbits
