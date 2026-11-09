; ============================================================
; AidTrack - Milestone 3: beneficiary registration
; NASM 32-bit x86 Linux.
;
; Option 1: register/replace ONE beneficiary in memory.
; Option 8: exit.
; Options 2..7: placeholders.
; No files are saved yet. Use fictional beneficiary information.
; ============================================================

BITS 32

; Constants for Linux services, line endings, and field limits.
%define SYS_EXIT  1
%define SYS_READ  3
%define SYS_WRITE 4
%define STDIN     0
%define STDOUT    1
%define LF        10
%define CR        13
%define EINTR     -4
%define ID_MAX    15
%define NAME_MAX  63

; PRINT: prepare the address and length for the output procedure.
; %1 = text address; %2 = length or a memory operand holding it.
%macro PRINT 2
    mov ecx, %1
    mov edx, %2
    call write_stdout
%endmacro

section .data
    banner db '+------------------------------------------+', LF
           db '|                 AidTrack                 |', LF
           db '|      Barangay Emergency Resources        |', LF
           db '+------------------------------------------+', LF
    banner_len equ $ - banner

    menu db '1. Register beneficiary', LF
         db '2. Add supply stock', LF
         db '3. Distribute water', LF
         db '4. Distribute relief package', LF
         db '5. View inventory', LF
         db '6. View transaction history', LF
         db '7. Generate distribution report', LF
         db '8. Exit', LF, LF
    menu_len equ $ - menu

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

    ; Registration prompts and feedback.
    registration db LF, 'REGISTER BENEFICIARY', LF
                 db 'One record only: registering again replaces it.', LF
    registration_len equ $ - registration

    id_prompt db 'Beneficiary ID (1-15 digits): '
    id_prompt_len equ $ - id_prompt

    name_prompt db 'Full name (1-63 characters): '
    name_prompt_len equ $ - name_prompt

    bad_id db 'Invalid ID. Enter 1-15 digits only.', LF
    bad_id_len equ $ - bad_id

    bad_name db 'Invalid name. Enter 1-63 printable ASCII characters, not only spaces.', LF
    bad_name_len equ $ - bad_name

    registered db LF, 'Beneficiary registered in memory.', LF
    registered_len equ $ - registered

    id_label db 'Beneficiary ID: '
    id_label_len equ $ - id_label

    name_label db 'Full name: '
    name_label_len equ $ - name_label

    newline db LF
    newline_len equ $ - newline

section .bss
    ; Shared scratch storage used while reading a complete line.
    input_byte resb 1
    choice_buffer resb 3
    line_overflow resb 1

    ; Beneficiary record.
    ; Extra bytes allow an optional CR and a terminating zero.
    ; ID remains TEXT so that 000123 stays 000123.
    id_buffer resb ID_MAX + 2
    name_buffer resb NAME_MAX + 2
    id_len resd 1
    name_len resd 1

section .text
    global _start

; ------------------------------------------------------------
; MAIN MENU
; read_choice returns 1..8, 0 for invalid, or -1 for EOF/error.
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

    cmp eax, 1
    je .register

    PRINT pending, pending_len
    jmp .menu

.register:
    call register_beneficiary
    test eax, eax
    js .input_end
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
; REGISTER_BENEFICIARY
; Collect and validate two fields, then display confirmation.
; Returns EAX=0 on completion, -1 if input ends/fails.
; Changes EAX/EBX/ECX/EDX/ESI and flags.
; ------------------------------------------------------------
register_beneficiary:
    PRINT registration, registration_len

.id:
    PRINT id_prompt, id_prompt_len
    mov ecx, id_buffer
    mov edx, ID_MAX + 1
    call read_line

    cmp eax, -2
    je .ended
    cmp eax, 1
    jl .bad_id
    cmp eax, ID_MAX
    ja .bad_id

    mov [id_len], eax

    ; Validate individual digits without converting the ID.
    mov esi, id_buffer
    mov ecx, eax

.check_id:
    mov al, [esi]
    sub al, '0'
    cmp al, 9
    ja .bad_id

    inc esi
    loop .check_id

.name:
    PRINT name_prompt, name_prompt_len
    mov ecx, name_buffer
    mov edx, NAME_MAX + 1
    call read_line

    cmp eax, -2
    je .ended
    cmp eax, 1
    jl .bad_name
    cmp eax, NAME_MAX
    ja .bad_name

    mov [name_len], eax

    ; Display the completed record using its actual byte lengths.
    PRINT registered, registered_len
    PRINT id_label, id_label_len
    PRINT id_buffer, [id_len]
    PRINT newline, newline_len

    PRINT name_label, name_label_len
    PRINT name_buffer, [name_len]
    PRINT newline, newline_len
    PRINT newline, newline_len

    xor eax, eax
    ret

.bad_id:
    PRINT bad_id, bad_id_len
    jmp .id

.bad_name:
    PRINT bad_name, bad_name_len
    jmp .name

.ended:
    mov eax, -1
    ret

; ------------------------------------------------------------
; READ_CHOICE
; Reuses the same line reader as beneficiary registration.
; Returns 1..8, 0 for invalid, or -1 for EOF/error.
; Changes EAX/ECX/EDX and flags.
; ------------------------------------------------------------
read_choice:
    mov ecx, choice_buffer
    mov edx, 2
    call read_line

    cmp eax, -2
    je .ended
    cmp eax, 1
    jne .invalid

    movzx eax, byte [choice_buffer]
    sub eax, '1'
    cmp eax, 7
    ja .invalid

    inc eax
    ret

.invalid:
    xor eax, eax
    ret

.ended:
    mov eax, -1
    ret

; ------------------------------------------------------------
; READ_LINE: shared input procedure.
; Input: ECX=buffer, EDX=maximum stored bytes.
; The caller must reserve EDX+1 bytes for the terminating zero.
;
; Output:
;   EAX >= 0 : valid line length
;   EAX = -1 : invalid line
;   EAX = -2 : EOF/read error
;
; Preserves all other registers; flags are not preserved.
; Reads the complete line, removes LF/trailing CR, and adds zero.
; Rejects oversized, blank-only, and nonprintable ASCII input.
; ------------------------------------------------------------
read_line:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp

    mov esi, ecx              ; destination address
    mov edi, edx              ; maximum stored bytes
    xor ebp, ebp              ; number of bytes stored
    mov byte [line_overflow], 0

.read:
    mov eax, SYS_READ
    mov ebx, STDIN
    mov ecx, input_byte
    mov edx, 1
    int 0x80

    cmp eax, EINTR
    je .read
    cmp eax, 1
    jne .ended

    mov al, [input_byte]
    cmp al, LF
    je .finish

    cmp ebp, edi
    jae .overflow

    mov [esi + ebp], al
    inc ebp
    jmp .read

.overflow:
    ; Keep consuming the line without writing past the buffer.
    mov byte [line_overflow], 1
    jmp .read

.finish:
    test ebp, ebp
    jz .invalid

    cmp byte [esi + ebp - 1], CR
    jne .validate
    dec ebp

.validate:
    cmp byte [line_overflow], 0
    jne .invalid

    xor ecx, ecx              ; character index
    xor edx, edx              ; non-space character count

.scan:
    cmp ecx, ebp
    jae .checked

    mov al, [esi + ecx]
    cmp al, 32
    jb .invalid
    cmp al, 126
    ja .invalid

    cmp al, ' '
    je .next
    inc edx

.next:
    inc ecx
    jmp .scan

.checked:
    test edx, edx
    jz .invalid

    mov eax, ebp
    jmp .return

.invalid:
    mov eax, -1
    jmp .return

.ended:
    mov eax, -2

.return:
    mov byte [esi + ebp], 0

    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ------------------------------------------------------------
; WRITE_STDOUT
; Input: ECX=text address, EDX=byte length.
; Changes EAX/EBX.
; Failed/partial write handling remains deferred.
; ------------------------------------------------------------
write_stdout:
    mov eax, SYS_WRITE
    mov ebx, STDOUT
    int 0x80
    ret

; EBX supplies the exit status. This procedure never returns.
exit_program:
    mov eax, SYS_EXIT
    int 0x80

section .note.GNU-stack noalloc noexec nowrite progbits