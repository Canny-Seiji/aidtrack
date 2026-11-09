; ============================================================
; AidTrack - Milestone 4: supply inventory
; NASM 32-bit x86 Linux.
;
; Working options: 1 Register, 2 Add stock, 5 Inventory, 8 Exit.
; Other options remain placeholders. Nothing is saved to files.
; One beneficiary record; two independent stock counters.
; ============================================================

BITS 32

; Linux services, line endings, and application limits.
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
%define MAX_ADD   9999
%define MAX_STOCK 999999

; Prepare output arguments and call the shared procedure.
; %1 = address; %2 = length or a memory operand holding it.
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

    ; Main-menu messages.
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

    ; Beneficiary-registration messages.
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

    ; NEW: inventory prompts and labels.
    supply_menu db LF, 'ADD SUPPLY STOCK', LF
                db '1. Water containers', LF
                db '2. Relief packages', LF
                db 'Supply type [1-2]: '
    supply_menu_len equ $ - supply_menu

    bad_supply db 'Invalid supply type. Enter 1 or 2.', LF
    bad_supply_len equ $ - bad_supply

    quantity_prompt db 'Quantity to add [1-9999]: '
    quantity_prompt_len equ $ - quantity_prompt

    bad_quantity db 'Invalid quantity. Enter a whole number from 1 to 9999.', LF
    bad_quantity_len equ $ - bad_quantity

    stock_limit db 'Stock limit is 999999 per supply. Enter a smaller quantity.', LF
    stock_limit_len equ $ - stock_limit

    stock_added db 'Stock added successfully.', LF
    stock_added_len equ $ - stock_added

    inventory_title db LF, 'CURRENT INVENTORY', LF
    inventory_title_len equ $ - inventory_title

    water_label db 'Water containers: '
    water_label_len equ $ - water_label

    relief_label db 'Relief packages: '
    relief_label_len equ $ - relief_label

section .bss
    ; Shared input scratch space.
    input_byte resb 1
    choice_buffer resb 3
    line_overflow resb 1

    ; One beneficiary record; preserve the ID as text.
    id_buffer resb ID_MAX + 2
    name_buffer resb NAME_MAX + 2
    id_len resd 1
    name_len resd 1

    ; NEW: integer stock counters, initially zero on Linux.
    water_stock resd 1
    relief_stock resd 1

    ; Quantity input and temporary decimal-output storage.
    quantity_buffer resb 12
    number_buffer resb 10

section .text
    global _start

; ------------------------------------------------------------
; MAIN MENU
; read_choice returns 1..8, 0 invalid, or -1 EOF/read error.
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
    cmp eax, 2
    je .add_stock
    cmp eax, 5
    je .inventory

    PRINT pending, pending_len
    jmp .menu

.register:
    call register_beneficiary
    test eax, eax
    js .input_end
    jmp .menu

.add_stock:
    call add_supply_stock
    test eax, eax
    js .input_end
    jmp .menu

.inventory:
    call display_inventory
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
; Collect and display one ID/name pair.
; Returns EAX=0 on completion, -1 on EOF/read error.
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

    ; Validate digits without converting the ID to an integer.
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
; NEW: ADD_SUPPLY_STOCK
; Select a counter, validate the quantity, then update it.
; Returns EAX=0 on success, -1 on EOF/read error.
; Changes EAX/EBX/ECX/EDX/EDI and flags.
; ------------------------------------------------------------
add_supply_stock:
.choose:
    PRINT supply_menu, supply_menu_len
    call read_choice

    test eax, eax
    js .ended
    cmp eax, 1
    je .water
    cmp eax, 2
    jne .bad_supply

    mov edi, relief_stock
    jmp .quantity

.water:
    mov edi, water_stock

.quantity:
    ; EDI holds the ADDRESS of the selected stock counter.
    PRINT quantity_prompt, quantity_prompt_len
    mov ecx, quantity_buffer
    mov edx, 11
    call read_line

    cmp eax, -2
    je .ended
    test eax, eax
    js .bad_quantity

    call parse_quantity
    test eax, eax
    jz .bad_quantity

    ; Calculate the proposed new stock before storing it.
    ; Bounded operands keep this addition within 32-bit range.
    add eax, [edi]
    cmp eax, MAX_STOCK
    ja .limit

    mov [edi], eax            ; commit only after all checks pass

    PRINT stock_added, stock_added_len
    call display_inventory

    xor eax, eax
    ret

.bad_supply:
    PRINT bad_supply, bad_supply_len
    jmp .choose

.bad_quantity:
    PRINT bad_quantity, bad_quantity_len
    jmp .quantity

.limit:
    PRINT stock_limit, stock_limit_len
    jmp .quantity

.ended:
    mov eax, -1
    ret

; ------------------------------------------------------------
; NEW: DISPLAY_INVENTORY
; Read and display both counters. Preserves all registers.
; ------------------------------------------------------------
display_inventory:
    pushad

    PRINT inventory_title, inventory_title_len
    PRINT water_label, water_label_len
    mov eax, [water_stock]
    call print_uint
    PRINT newline, newline_len

    PRINT relief_label, relief_label_len
    mov eax, [relief_stock]
    call print_uint
    PRINT newline, newline_len
    PRINT newline, newline_len

    popad
    ret

; ------------------------------------------------------------
; NEW: PARSE_QUANTITY
; Convert quantity_buffer from ASCII digits to an integer.
; Returns EAX=1..MAX_ADD, or 0 for invalid/zero input.
; Changes EAX/ECX/EDX and flags; leaves EDI unchanged.
; Checking the limit after every digit prevents numeric overflow.
; ------------------------------------------------------------
parse_quantity:
    xor eax, eax
    xor ecx, ecx

.digit:
    movzx edx, byte [quantity_buffer + ecx]
    test edx, edx
    jz .done

    sub edx, '0'
    cmp edx, 9
    ja .invalid

    imul eax, eax, 10
    add eax, edx
    cmp eax, MAX_ADD
    ja .invalid

    inc ecx
    jmp .digit

.invalid:
    xor eax, eax

.done:
    ret

; ------------------------------------------------------------
; NEW: PRINT_UINT
; Input: EAX=unsigned integer. Preserves all registers.
; Divide repeatedly by 10; each remainder supplies one digit.
; Build digits right to left, then display the completed number.
; ------------------------------------------------------------
print_uint:
    pushad

    mov edi, number_buffer + 10
    mov ebx, 10
    xor ecx, ecx

.digit:
    xor edx, edx
    div ebx
    add dl, '0'
    dec edi
    mov [edi], dl
    inc ecx

    test eax, eax
    jnz .digit

    mov edx, ecx
    mov ecx, edi
    call write_stdout

    popad
    ret

; ------------------------------------------------------------
; READ_CHOICE
; Reuse read_line and convert one menu digit.
; Returns 1..8, 0 invalid, or -1 EOF/read error.
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
; READ_LINE
; Input: ECX=buffer, EDX=max stored bytes; reserve EDX+1 bytes.
; Output: EAX=length, -1 invalid line, -2 EOF/read error.
; Preserves all other registers; flags are not preserved.
;
; Consumes the complete line, removes LF/trailing CR, adds zero.
; Rejects overflow, blank-only input, and nonprintable ASCII.
; ------------------------------------------------------------
read_line:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp

    mov esi, ecx
    mov edi, edx
    xor ebp, ebp
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

    xor ecx, ecx
    xor edx, edx

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

; Shared output: ECX=text address, EDX=byte length.
; Changes EAX/EBX. Failed/partial write handling remains deferred.
write_stdout:
    mov eax, SYS_WRITE
    mov ebx, STDOUT
    int 0x80
    ret

; EBX supplies the exit status; this procedure never returns.
exit_program:
    mov eax, SYS_EXIT
    int 0x80

section .note.GNU-stack noalloc noexec nowrite progbits