; ============================================================
; AidTrack: Barangay Relief and Water Distribution System
; Milestone 2: menu input, validation, repetition, and exit.
; Platform: NASM 32-bit x86 Linux.
; ============================================================

BITS 32

; ------------------------------------------------------------
; CONSTANTS: readable names for Linux services and input bytes.
; ------------------------------------------------------------
%define SYS_EXIT  1
%define SYS_READ  3
%define SYS_WRITE 4
%define STDIN     0
%define STDOUT    1
%define LF        10
%define CR        13
%define EINTR     -4

; ------------------------------------------------------------
; PRINT MACRO
; %1 = text address; %2 = byte length.
; Prepares arguments and calls the shared output procedure.
; ------------------------------------------------------------
%macro PRINT 2
    mov ecx, %1
    mov edx, %2
    call write_stdout
%endmacro

section .data
    ; Project banner. Explicit lengths mean no null terminators
    ; are needed for these displayed strings.
    banner db '+------------------------------------------+', LF
           db '|                 AidTrack                 |', LF
           db '|      Barangay Emergency Resources        |', LF
           db '+------------------------------------------+', LF
    banner_len equ $ - banner

    ; Planned features. Only Exit is implemented at this stage.
    menu db '1. Register beneficiary', LF
         db '2. Add supply stock', LF
         db '3. Distribute water', LF
         db '4. Distribute relief package', LF
         db '5. View inventory', LF
         db '6. View transaction history', LF
         db '7. Generate distribution report', LF
         db '8. Exit', LF, LF
    menu_len equ $ - menu

    ; Menu prompts and response messages.
    prompt db 'Enter your choice [1-8]: '
    prompt_len equ $ - prompt

    invalid db 'Invalid choice. Enter exactly one digit from 1 to 8.', LF, LF
    invalid_len equ $ - invalid

    pending db 'Option accepted. This feature will be added in a later milestone.', LF, LF
    pending_len equ $ - pending

    goodbye db 'Thank you for using AidTrack.', LF
    goodbye_len equ $ - goodbye

    input_ended db LF, 'Input ended or could not be read. Program stopped.', LF
    input_ended_len equ $ - input_ended

section .bss
    ; Temporary storage for keyboard input.
    ; Two stored bytes accommodate a digit plus optional CR.
    input_byte resb 1
    choice_buffer resb 2

section .text
    global _start

; ------------------------------------------------------------
; MAIN FLOW
; Display the banner once, then repeatedly show the menu.
; read_choice returns:
;   EAX = 1..8 : valid numeric choice
;   EAX = 0    : invalid input
;   EAX = -1   : input ended or read failed
; ------------------------------------------------------------
_start:
    PRINT banner, banner_len

.menu:
    PRINT menu, menu_len
    PRINT prompt, prompt_len
    call read_choice

    test eax, eax
    js .input_end
    jz .invalid

    cmp eax, 8
    je .exit

    ; Options 1..7 will be implemented incrementally.
    PRINT pending, pending_len
    jmp .menu

.invalid:
    PRINT invalid, invalid_len
    jmp .menu

.input_end:
    PRINT input_ended, input_ended_len
    mov ebx, 1
    call exit_program

.exit:
    PRINT goodbye, goodbye_len
    xor ebx, ebx
    call exit_program

; ------------------------------------------------------------
; READ_CHOICE: read and validate one complete response.
; Preserves EBX, ECX, EDX, and ESI; changes EAX and flags.
;
; Consumes the entire line, even if it contains excess text.
; This prevents leftover characters from reaching the next prompt.
; Accepts LF and CRLF line endings.
; ------------------------------------------------------------
read_choice:
    push ebx
    push ecx
    push edx
    push esi

    xor esi, esi              ; character count, capped at 3

.read:
    mov eax, SYS_READ
    mov ebx, STDIN
    mov ecx, input_byte
    mov edx, 1
    int 0x80

    cmp eax, EINTR
    je .read                  ; retry an interrupted read

    cmp eax, 1
    jne .ended

    mov al, [input_byte]
    cmp al, LF
    je .validate

    ; Store only the first two characters.
    cmp esi, 2
    jae .count
    mov [choice_buffer + esi], al

.count:
    ; A count of 3 means the answer is already too long.
    ; Continue consuming characters without storing them.
    cmp esi, 3
    jae .read
    inc esi
    jmp .read

.validate:
    ; Two characters are valid only for digit + CR.
    cmp esi, 2
    jne .digit

    cmp byte [choice_buffer + 1], CR
    jne .invalid
    dec esi

.digit:
    cmp esi, 1
    jne .invalid

    ; Convert ASCII '1'..'8' into numeric choices 1..8.
    movzx eax, byte [choice_buffer]
    sub eax, '1'              ; valid characters become 0..7
    cmp eax, 7
    ja .invalid               ; unsigned check rejects other bytes
    inc eax
    jmp .return

.invalid:
    xor eax, eax
    jmp .return

.ended:
    mov eax, -1

.return:
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ------------------------------------------------------------
; WRITE_STDOUT: display a block of text.
; Input: ECX = text address; EDX = byte count.
; Output: EAX = bytes written or negative Linux error result.
; Changes EAX and EBX.
; Handling failed/partial writes is deferred to a later milestone.
; ------------------------------------------------------------
write_stdout:
    mov eax, SYS_WRITE
    mov ebx, STDOUT
    int 0x80
    ret

; ------------------------------------------------------------
; EXIT_PROGRAM: terminate the process; never returns.
; Input: EBX = status (0 success, 1 unexpected input end/error).
; ------------------------------------------------------------
exit_program:
    mov eax, SYS_EXIT
    int 0x80

; Tell the linker that this program does not need an executable stack.
section .note.GNU-stack noalloc noexec nowrite progbits