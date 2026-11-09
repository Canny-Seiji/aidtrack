; ============================================================
; AidTrack - complete classroom transaction system
; NASM 32-bit x86 Linux, direct int 0x80 calls, no C library.
; Build: nasm -f elf32 main.asm -o main.o
;        ld -m elf_i386 main.o -o aidtrack
;
; Storage: one append-only, checksummed binary event journal.
; Validate -> append -> fsync -> update RAM. Replay on startup.
; One journal represents ONE distribution cycle. Each beneficiary
; may receive water once and a relief package allocation once.
; No medical/political eligibility decisions are automated.
; ============================================================
BITS 32
%define SYS_EXIT   1
%define SYS_READ   3
%define SYS_WRITE  4
%define SYS_OPEN   5
%define SYS_CLOSE  6
%define SYS_LSEEK  19
%define SYS_FSYNC  118
%define SYS_FLOCK  143
%define STDIN     0
%define STDOUT    1
%define STDERR    2
%define EINTR     -4
%define OPEN_FLAGS 1090       ; O_RDWR(2)|O_CREAT(64)|O_APPEND(1024)
%define FILE_MODE 384         ; 0600: owner read/write
%define LOCK_FLAGS 6          ; LOCK_EX(2)|LOCK_NB(4)
%define LF        10
%define CR        13
%define MAX_PEOPLE 100
%define MAX_EVENTS 5000
%define MAX_QTY   9999
%define MAX_STOCK 999999
%define MAGIC     0x41494431

; Journal record: 96 bytes. All unused fields/padding are zero.
%define R_TYPE 4
%define R_QTY  8
%define R_ID   12             ; 16 bytes, including zero terminator
%define R_NAME 28             ; 64 bytes, including zero terminator
%define R_SUM  92
%define R_SIZE 96

; In-memory beneficiary: ID[16], name[64], two claim flags.
%define P_SIZE 88
%define P_WATER 80
%define P_RELIEF 84

; Text macro: prepares the address and calls shared executable code.
%macro PRINT 1
    mov ecx, %1
    call puts
%endmacro


; Error text is red, then restore normal terminal color.
%macro ERROR 1
    mov ecx, %1
    call print_error
%endmacro

; Informational notes/warnings are yellow; actual errors remain red.
%macro WARN 1
    mov ecx, %1
    mov edx, color_yellow
    call print_colored
%endmacro
⠀⠀⠀⠀⠀⠀⠀
section .data
    menu db 27,'[1;36m',LF
         db '       _    ___ ____ _____ ____      _    ____ _  __',LF
         db '      / \  |_ _|  _ \_   _|  _ \    / \  / ___| |/ /',LF
         db '     / _ \  | || | | || | | |_) |  / _ \| |   | | /',LF
         db '    / ___ \ | || |_| || | |  _ <  / ___ \ |___|   \',LF
         db '   /_/   \_\___|____/ |_| |_| \_\/_/   \_\____|_|\_\',LF

         db '+----------------------------------------------------+',LF
         db '|                      AidTrack                      |',LF
         db '|        Relief and Water Distribution System        |',LF
         db '+----------------------------------------------------+',LF
         db '| 1. Register beneficiary                            |',LF
         db '| 2. Add supply stock                                |',LF
         db '| 3. Distribute water                                |',LF
         db '| 4. Distribute relief packages                      |',LF
         db '| 5. View inventory                                  |',LF
         db '| 6. View beneficiaries                              |',LF
         db '| 7. Read transaction history from file              |',LF
         db '| 8. Generate cumulative report                      |',LF
         db '| 0. Exit                                            |',LF
         db '+----------------------------------------------------+',LF
         db 27,'[0m',0
    choice_prompt db 'Enter choice [0-8]: ',0
    id_prompt db 'Beneficiary ID [1-15 digits]: ',0
    name_prompt db 'Full name [1-63 characters]: ',0
    qty_prompt db 'Quantity [1-9999]: ',0
    supply_prompt db LF,'1. Water containers',LF,'2. Relief packages',LF
                  db 'Supply type [1-2]: ',0
    water_title db LF,'DISTRIBUTE WATER',LF,0
    relief_title db LF,'DISTRIBUTE RELIEF PACKAGES',LF,0
    bad_id db 'Invalid ID. Use 1-15 digits; leading zeros are preserved.',LF,0
    bad_name db 'Invalid name. Use 1-63 printable ASCII characters, not only spaces.',LF,0
    bad_number db 'Invalid number. Enter a whole number within the prompt range.',LF,0
    ok db 'SAVED - Transaction #',0
    nl db LF,0
    sep db ' | ',0
    dash db '-',0
    id_label db 'Beneficiary ID: ',0
    qty_label db 'Quantity: ',0
    inventory_title db '|                 CURRENT INVENTORY                 |',LF,0
    water_label db 'Water containers: ',0
    relief_label db 'Relief packages: ',0
    history_title db LF,'TRANSACTION HISTORY (read from aidtrack.dat)',LF,0
    report_title db '|                 CUMULATIVE REPORT                 |',LF,0
    report_rule db '+------------------------------------+--------------+',LF,0
    people_label db 'Registered beneficiaries: ',0
    events_label db 'Saved transactions: ',0
    water_in_label db 'Total water received: ',0
    relief_in_label db 'Total relief received: ',0
    water_out_label db 'Total water distributed: ',0
    relief_out_label db 'Total relief distributed: ',0
    empty_history db 'No transactions recorded yet.',LF,0
    bye db 'Thank you for using AidTrack.',LF,0
    input_end db LF,'Input ended or failed. Previous saved transactions remain intact.',LF,0
    file_error db 'File I/O failed. Stopping; do not retry a transaction blindly.',LF
                  db 'Restart to replay saved records. Preserve the journal for inspection.',LF,0
    corrupt_error db 'Invalid or incomplete journal. Startup stopped without editing the file.',LF
                     db 'Preserve aidtrack.dat and restore a known-good backup.',LF,0
    lock_error db 'Cannot lock journal. Another AidTrack process may already be running.',LF,0
    filename db 'aidtrack.dat',0
    e_invalid db 'Rejected: invalid transaction fields.',LF,0
    e_duplicate db 'Rejected: beneficiary ID already exists.',LF,0
    e_capacity db 'Rejected: beneficiary or stock capacity exceeded.',LF,0
    e_unknown db 'Rejected: beneficiary ID is not registered.',LF,0
    e_claimed db 'Rejected: this beneficiary already received this supply in this cycle.',LF,0
    e_stock db 'Rejected: insufficient stock. Inventory unchanged.',LF,0
    e_logfull db 'Rejected: maximum journal size reached.',LF,0
    a_register db 'REGISTER BENEFICIARY',0
    a_water_in db 'ADD WATER',0
    a_relief_in db 'ADD RELIEF',0
    a_water_out db 'DISTRIBUTE WATER',0
    a_relief_out db 'DISTRIBUTE RELIEF',0
    align 4
    action_names dd a_register,a_water_in,a_relief_in,a_water_out,a_relief_out
    error_names dd e_invalid,e_duplicate,e_capacity,e_unknown,e_claimed,e_stock,e_logfull
    ; Index 0 is handled by Exit before dereferencing the table.
    menu_actions dd 0,register_person,add_stock,menu_water,menu_relief
                 dd show_inventory,show_beneficiaries,show_history,show_report
    journal_fd dd -1

    ; Presentation helpers. ANSI bytes never enter width calculations.
    color_red db 27,'[1;31m',0
    color_green db 27,'[1;32m',0
    color_yellow db 27,'[1;33m',0
    color_cyan db 27,'[1;36m',0
    color_white db 27,'[37m',0
    color_reset db 27,'[0m',0
    row_begin db '| ',0
    row_end db ' |',LF,0
    plus db '+',0
    pad_spaces times 128 db ' '
    pad_dashes times 128 db '-'
    h_no db 'No.',0
    h_action db 'Action',0
    h_id db 'Beneficiary ID',0
    h_qty db 'Quantity',0
    h_name db 'Name',0
    h_water db 'Water claim',0
    h_relief db 'Relief claim',0
    claimed db 'Claimed',0
    unclaimed db 'Not claimed',0
    beneficiaries_title db LF,'REGISTERED BENEFICIARIES',LF,0
    no_people db 'No beneficiaries registered yet.',LF,0
    align 4
    history_headers dd h_no,h_action,h_id,h_qty,h_name
    people_headers dd h_id,h_name,h_water,h_relief
    report_rows dd people_label,people_count,color_cyan
                dd events_label,event_count,color_cyan
                dd water_in_label,received,color_cyan
                dd relief_in_label,received+4,color_cyan
                dd water_out_label,distributed,color_cyan
                dd relief_out_label,distributed+4,color_cyan
                dd water_label,stock,color_green
                dd relief_label,stock+4,color_green

section .bss
    input_buffer resb 128
    input_byte resb 1
    input_overflow resb 1
    number_buffer resb 11
    history_number resb 11
    history_quantity resb 11
    cell_buffer resb 128
    fields resd 5
    widths resd 5
    columns resd 1
    box_color resd 1
    align 4
    event resb R_SIZE
    people resb P_SIZE * MAX_PEOPLE
    people_count resd 1
    event_count resd 1
    stock resd 2               
    received resd 2
    distributed resd 2

section .text
global _start

_start:
    cld
    call open_journal
    call replay_journal
.menu:
    PRINT menu
    mov ecx, choice_prompt
    mov eax, 8
    xor edx, edx              
    call ask_range
    test eax, eax
    jz .exit
    mov eax, [menu_actions + eax*4]
    call eax
    jmp .menu
.exit:
    PRINT color_green
    PRINT bye
    PRINT color_reset
    call close_journal
    xor ebx, ebx
    jmp exit_program

; Tail-call adapters share the same distribution implementation.
menu_water:
    mov eax, 4
    jmp distribute_supply
menu_relief:
    mov eax, 5
    jmp distribute_supply

; Create an empty, zero-padded transaction ready for input.
clear_event:
    pushad
    mov edi, event
    xor eax, eax
    mov ecx, R_SIZE / 4
    rep stosd
    mov dword [event], MAGIC
    popad
    ret

; Register a new person; duplicates never overwrite an existing record.
register_person:
    call clear_event
    mov dword [event + R_TYPE], 1
    call ask_id
.name:
    PRINT name_prompt
    call read_line
    cmp eax, -2
    je input_finished
    mov ecx, input_buffer
    call valid_name
    test eax, eax
    jz .bad_name
    mov esi, input_buffer
    mov edi, event + R_NAME
    call copy_z
    call commit_event
    ret
.bad_name:
    ERROR bad_name
    jmp .name

; Read a text ID into the current event; keep leading zeros.
ask_id:
.retry:
    PRINT id_prompt
    call read_line
    cmp eax, -2
    je input_finished
    mov ecx, input_buffer
    call valid_id
    test eax, eax
    jz .bad
    mov esi, input_buffer
    mov edi, event + R_ID
    call copy_z
    ret
.bad:
    ERROR bad_id
    jmp .retry

; Supply choice maps to event type 2=water intake, 3=relief intake.
add_stock:
    call clear_event
    mov ecx, supply_prompt
    mov eax, 2
    call ask_number
    inc eax
    mov [event + R_TYPE], eax
    mov ecx, qty_prompt
    mov eax, MAX_QTY
    call ask_number
    mov [event + R_QTY], eax
    call commit_event
    ret

; Both distribution types share the SAME procedure and validation.
; Input EAX=4 for water, 5 for relief.
distribute_supply:
    call clear_event
    mov [event + R_TYPE], eax
    cmp eax, 4
    jne .relief
    PRINT water_title
    jmp .input
.relief:
    PRINT relief_title
.input:
    call ask_id
    mov ecx, qty_prompt
    mov eax, MAX_QTY
    call ask_number
    mov [event + R_QTY], eax
    call commit_event
    ret

; Transaction boundary: VALIDATE -> APPEND -> FSYNC -> APPLY.
; If durable writing fails, stop instead of pretending success.
commit_event:
    call validate_event
    test eax, eax
    jnz .rejected
    call checksum
    mov [event + R_SUM], eax
    mov ebx, [journal_fd]
    mov ecx, event
    mov edx, R_SIZE
    call write_all
.sync:
    mov eax, SYS_FSYNC
    mov ebx, [journal_fd]
    int 0x80
    cmp eax, EINTR
    je .sync
    test eax, eax
    js io_failed
    call apply_event
    PRINT color_green
    PRINT ok
    mov eax, [event_count]
    call print_uint
    PRINT nl
    PRINT color_reset
    cmp dword [event + R_TYPE], 4
    jb .inventory
    PRINT id_label
    PRINT event + R_ID
    PRINT nl
    PRINT qty_label
    mov eax, [event + R_QTY]
    call print_uint
    PRINT nl
.inventory:
    call show_inventory
    ret
.rejected:
    dec eax
    mov ecx, [error_names + eax*4]
    call print_error
    ret

; Validate without changing any state.
; Returns EAX=0 valid, otherwise error index 1..7.
validate_event:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    cmp dword [event_count], MAX_EVENTS
    jae .logfull
    mov ebx, [event + R_TYPE]
    cmp ebx, 1
    jb .invalid
    cmp ebx, 5
    ja .invalid
    cmp ebx, 1
    je .registration
    mov edx, [event + R_QTY]
    cmp edx, 1
    jb .invalid
    cmp edx, MAX_QTY
    ja .invalid
    cmp ebx, 3
    jbe .intake

    ; A distribution requires an existing person and an unused claim.
    mov ecx, event + R_ID
    call valid_id
    test eax, eax
    jz .invalid
    call find_person
    test eax, eax
    jz .unknown
    sub ebx, 4
    cmp dword [eax + P_WATER + ebx*4], 0
    jne .claimed
    cmp edx, [stock + ebx*4]
    ja .insufficient
    jmp .valid

.intake:
    cmp byte [event + R_ID], 0
    jne .invalid
    cmp byte [event + R_NAME], 0
    jne .invalid
    sub ebx, 2
    mov eax, [stock + ebx*4]
    add eax, edx
    cmp eax, MAX_STOCK
    ja .capacity
    jmp .valid

.registration:
    cmp dword [event + R_QTY], 0
    jne .invalid
    mov ecx, event + R_ID
    call valid_id
    test eax, eax
    jz .invalid
    call find_person
    test eax, eax
    jnz .duplicate
    mov ecx, event + R_NAME
    call valid_name
    test eax, eax
    jz .invalid
    cmp dword [people_count], MAX_PEOPLE
    jae .capacity
.valid:
    xor eax, eax
    jmp .done
.invalid:
    mov eax, 1
    jmp .done
.duplicate:
    mov eax, 2
    jmp .done
.capacity:
    mov eax, 3
    jmp .done
.unknown:
    mov eax, 4
    jmp .done
.claimed:
    mov eax, 5
    jmp .done
.insufficient:
    mov eax, 6
    jmp .done
.logfull:
    mov eax, 7
.done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; Apply only a validated event (after successful fsync or replay).
apply_event:
    pushad
    mov ebx, [event + R_TYPE]
    mov edx, [event + R_QTY]
    cmp ebx, 1
    je .register
    cmp ebx, 3
    jbe .intake
    mov ecx, event + R_ID
    call find_person
    sub ebx, 4
    mov dword [eax + P_WATER + ebx*4], 1
    sub [stock + ebx*4], edx
    add [distributed + ebx*4], edx
    jmp .done
.intake:
    sub ebx, 2
    add [stock + ebx*4], edx
    add [received + ebx*4], edx
    jmp .done
.register:
    mov eax, [people_count]
    imul eax, P_SIZE
    lea edi, [people + eax]
    mov esi, event + R_ID
    mov ecx, 80               
    rep movsb
    inc dword [people_count]
.done:
    inc dword [event_count]
    popad
    ret

; Find an exact, zero-terminated ID. ECX=input address.
; Returns EAX=person address or 0; preserves all other registers.
find_person:
    push ebx
    push ecx
    push edx
    push esi
    mov esi, ecx
    mov ebx, [people_count]
    mov eax, people
.next:
    test ebx, ebx
    jz .missing
    xor edx, edx
.compare:
    mov cl, [esi + edx]
    cmp cl, [eax + edx]
    jne .advance
    test cl, cl
    jz .done
    inc edx
    jmp .compare
.advance:
    add eax, P_SIZE
    dec ebx
    jmp .next
.missing:
    xor eax, eax
.done:
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ID validation: exactly 1..15 digits, no integer conversion.
; ECX=string; EAX=boolean; preserves other registers.
valid_id:
    push edx
    xor edx, edx
.next:
    mov al, [ecx + edx]
    test al, al
    jz .end
    cmp edx, 15
    jae .bad
    sub al, '0'
    cmp al, 9
    ja .bad
    inc edx
    jmp .next
.end:
    xor eax, eax
    test edx, edx
    setnz al
    pop edx
    ret
.bad:
    xor eax, eax
    pop edx
    ret

; Name validation: 1..63 printable ASCII characters, not just spaces.
valid_name:
    push edx
    push ebx
    xor edx, edx
    xor ebx, ebx
.next:
    mov al, [ecx + edx]
    test al, al
    jz .end
    cmp edx, 63
    jae .bad
    cmp al, 32
    jb .bad
    cmp al, 126
    ja .bad
    cmp al, ' '
    je .space
    inc ebx
.space:
    inc edx
    jmp .next
.end:
    xor eax, eax
    test ebx, ebx
    setnz al
    jmp .done
.bad:
    xor eax, eax
.done:
    pop ebx
    pop edx
    ret

; Copy text including its terminating zero. Caller validates capacity.
copy_z:
    lodsb
    stosb
    test al, al
    jnz copy_z
    ret

; Open the journal without truncation; hold an exclusive nonblocking lock.
open_journal:
.open:
    mov eax, SYS_OPEN
    mov ebx, filename
    mov ecx, OPEN_FLAGS
    mov edx, FILE_MODE
    int 0x80
    cmp eax, EINTR
    je .open
    test eax, eax
    js io_failed
    mov [journal_fd], eax
.lock:
    mov eax, SYS_FLOCK
    mov ebx, [journal_fd]
    mov ecx, LOCK_FLAGS
    int 0x80
    cmp eax, EINTR
    je .lock
    test eax, eax
    jns .done
    mov ecx, lock_error
    jmp fatal
.done:
    ret

; Reconstruct beneficiaries, claims and stock from validated records.
replay_journal:
.next:
    call read_event
    test eax, eax
    jz .done
    call validate_event
    test eax, eax
    jnz corrupt
    call apply_event
    jmp .next
.done:
    ret

; Read exactly one 96-byte event. Return 1=record, 0=clean EOF.
; Short reads are accumulated; partial EOF or a bad checksum is fatal.
read_event:
    push ebx
    push ecx
    push edx
    push esi
    xor esi, esi
.read:
    mov eax, SYS_READ
    mov ebx, [journal_fd]
    lea ecx, [event + esi]
    mov edx, R_SIZE
    sub edx, esi
    int 0x80
    cmp eax, EINTR
    je .read
    test eax, eax
    js io_failed
    jz .eof
    add esi, eax
    cmp esi, R_SIZE
    jb .read
    cmp dword [event], MAGIC
    jne corrupt
    call checksum
    cmp eax, [event + R_SUM]
    jne corrupt
    mov eax, 1
    jmp .done
.eof:
    test esi, esi
    jnz corrupt
    xor eax, eax
.done:
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

checksum:
    push ecx
    push esi
    xor eax, eax
    mov esi, event
    mov ecx, R_SUM / 4
.next:
    add eax, [esi]
    add esi, 4
    loop .next
    pop esi
    pop ecx
    ret

; Reusable table renderer: measure actual visible strings, then pad.
; fields[] = row string pointers; widths[] = maximum per column.
; Column widths include headers, so even empty tables stay readable.
set_history_headers:
    mov esi, history_headers
    mov ecx, 5
    jmp set_headers

; Both table headers share the same pointer-copy procedure.
set_people_headers:
    mov esi, people_headers
    mov ecx, 4
set_headers:
    mov edi, fields
    rep movsd
    ret

reset_widths:
    pushad
    mov edi, widths
    xor eax, eax
    mov ecx, 5
    rep stosd
    call measure_row
    popad
    ret
zlen:
    xor edx, edx
.next:
    cmp byte [ecx + edx], 0
    je .done
    inc edx
    jmp .next
.done:
    ret

measure_row:
    pushad
    xor ebp, ebp
.next:
    mov ecx, [fields + ebp*4]
    call zlen
    cmp edx, [widths + ebp*4]
    jbe .advance
    mov [widths + ebp*4], edx
.advance:
    inc ebp
    cmp ebp, [columns]
    jb .next
    popad
    ret

print_spaces:
    pushad
    mov ecx, pad_spaces
    mov ebx, STDOUT
    call write_all
    popad
    ret

table_border:
    pushad
    PRINT plus
    xor ebp, ebp
.next:
    mov edx, [widths + ebp*4]
    add edx, 2
    mov ecx, pad_dashes
    mov ebx, STDOUT
    call write_all
    PRINT plus
    inc ebp
    cmp ebp, [columns]
    jb .next
    PRINT nl
    popad
    ret

table_row:
    pushad
    PRINT row_begin
    xor ebp, ebp
.next:
    mov ecx, [fields + ebp*4]
    call zlen
    mov edi, [widths + ebp*4]
    sub edi, edx
    call print_cell
    mov edx, edi
    call print_spaces
    inc ebp
    cmp ebp, [columns]
    jae .done
    PRINT sep
    jmp .next
.done:
    PRINT row_end
    popad
    ret

table_header:
    PRINT color_cyan
    call table_border
    call table_row
    jmp table_border

; Preserve literal pipe characters in saved names, but show them as
; slashes inside cells so only table separators use vertical bars.
print_cell:
    pushad
    mov esi, ecx
    mov edi, cell_buffer
.next:
    lodsb
    cmp al, '|'
    jne .store
    mov al, '/'
.store:
    stosb
    test al, al
    jnz .next
    mov ecx, cell_buffer
    call puts
    popad
    ret

table_footer:
    call table_border
    PRINT color_reset
    ret

; Build the five strings for a history row; EAX=sequence number.
history_fields:
    pushad
    call format_uint
    mov esi, ecx
    mov edi, history_number
    call copy_z
    mov eax, [event + R_QTY]
    call format_uint
    mov esi, ecx
    mov edi, history_quantity
    call copy_z
    mov dword [fields], history_number
    mov eax, [event + R_TYPE]
    cmp eax, 1
    jb corrupt
    cmp eax, 5
    ja corrupt
    dec eax
    mov eax, [action_names + eax*4]
    mov [fields + 4], eax
    mov dword [fields + 8], dash
    cmp byte [event + R_ID], 0
    je .quantity
    mov dword [fields + 8], event + R_ID
.quantity:
    mov dword [fields + 12], history_quantity
    mov dword [fields + 16], dash
    cmp dword [event + R_TYPE], 1
    jne .done
    mov dword [fields + 16], event + R_NAME
.done:
    popad
    ret

rewind_journal:
.retry:
    mov eax, SYS_LSEEK
    mov ebx, [journal_fd]
    xor ecx, ecx
    xor edx, edx
    int 0x80
    cmp eax, EINTR
    je .retry
    test eax, eax
    js io_failed
    ret

; Two passes over the actual file: determine widths, then display.
; No records are altered; append writes still go to EOF.
show_history:
    PRINT history_title
    mov dword [columns], 5
    call set_history_headers
    call reset_widths
    call rewind_journal
    xor edi, edi
.measure:
    call read_event
    test eax, eax
    jz .display
    inc edi
    mov eax, edi
    call history_fields
    call measure_row
    jmp .measure
.display:
    call set_history_headers
    call table_header
    call rewind_journal
    xor edi, edi
.next:
    call read_event
    test eax, eax
    jz .done
    inc edi
    mov eax, edi
    call history_fields
    call table_row
    jmp .next
.done:
    call table_footer
    test edi, edi
    jnz .return
    WARN empty_history
.return:
    ret

; Option 6 lists all restored/registered people and claim status.
; Input ESI=person address; leaves that pointer unchanged.
person_fields:
    pushad
    mov [fields], esi
    lea eax, [esi + 16]
    mov [fields + 4], eax
    mov dword [fields + 8], unclaimed
    mov dword [fields + 12], unclaimed
    cmp dword [esi + P_WATER], 0
    je .relief
    mov dword [fields + 8], claimed
.relief:
    cmp dword [esi + P_RELIEF], 0
    je .done
    mov dword [fields + 12], claimed
.done:
    popad
    ret

show_beneficiaries:
    PRINT beneficiaries_title
    mov dword [columns], 4
    call set_people_headers
    call reset_widths
    mov esi, people
    mov ebp, [people_count]
.measure:
    test ebp, ebp
    jz .display
    call person_fields
    call measure_row
    add esi, P_SIZE
    dec ebp
    jmp .measure
.display:
    call set_people_headers
    call table_header
    mov esi, people
    mov ebp, [people_count]
.next:
    test ebp, ebp
    jz .done
    call person_fields
    call table_row
    add esi, P_SIZE
    dec ebp
    jmp .next
.done:
    call table_footer
    cmp dword [people_count], 0
    jne .return
    WARN no_people
.return:
    ret

; Inventory and report share one receipt-style box renderer.
show_inventory:
    pushad
    mov dword [box_color], color_cyan
    mov ecx, inventory_title
    mov esi, report_rows + 72
    mov ebp, 2
    call show_box
    popad
    ret

show_report:
    mov dword [box_color], color_white
    mov ecx, report_title
    mov esi, report_rows
    mov ebp, 8
    call show_box
    ret

; ECX=boxed title, ESI=row descriptors, EBP=row count.
; box_color selects cyan inventory or an entirely white report.
; Preserve registers so either caller can reuse its own loop state.
show_box:
    pushad
    mov edi, ecx
    PRINT nl
    mov ecx, [box_color]
    call puts
    PRINT report_rule
    mov ecx, edi
    call puts
    PRINT report_rule
.next:
    mov ecx, [esi]
    mov edi, [esi + 4]
    mov eax, [edi]
    mov ebx, [esi + 8]
    cmp dword [box_color], color_white
    jne .inventory_color
    mov ebx, color_white
    jmp .row
.inventory_color:
    cmp edi, stock
    je .stock
    cmp edi, stock + 4
    jne .row
.stock:
    test eax, eax
    jnz .row
    mov ebx, color_yellow     ; zero stock is a warning, not a failed operation
.row:
    call receipt_row
    add esi, 12
    dec ebp
    jnz .next
    PRINT report_rule
    PRINT color_reset
    popad
    ret

; ECX=label, EAX=value, EBX=color address. Preserves registers.
receipt_row:
    pushad
    mov ebp, eax
    mov esi, ecx
    mov edi, ebx
    PRINT row_begin
    mov ecx, esi
    call zlen
    mov esi, 34
    sub esi, edx
    call puts
    mov edx, esi
    call print_spaces
    PRINT sep
    mov eax, ebp
    call format_uint
    mov esi, ecx
    mov ebp, edx
    mov edx, 12
    sub edx, ebp
    call print_spaces
    mov ecx, edi
    call puts
    mov ecx, esi
    mov edx, ebp
    mov ebx, STDOUT
    call write_all
    mov ecx, [box_color]
    call puts
    PRINT row_end
    popad
    ret

; Positive-input adapter preserves the existing caller contract.
; EAX=maximum, ECX=prompt. Quantities/supply types cannot accept zero.
ask_number:
    push edx
    mov edx, 1
    call ask_range
    pop edx
    ret

; Returns EAX=value; preserves all other registers. Flags may change.
ask_range:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    mov ebx, edx             
    mov ebp, eax
    mov edi, ecx
.retry:
    mov ecx, edi
    call puts
    call read_line
    cmp eax, -2
    je input_finished
    cmp eax, 1
    jl .bad
    xor eax, eax
    xor esi, esi
.digit:
    movzx edx, byte [input_buffer + esi]
    test edx, edx
    jz .end
    sub edx, '0'
    cmp edx, 9
    ja .bad
    imul eax, eax, 10
    add eax, edx
    cmp eax, ebp
    ja .bad
    inc esi
    jmp .digit
.end:
    cmp eax, ebx
    jb .bad
    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret
.bad:
    ERROR bad_number
    jmp .retry

; Read a full LF/CRLF line. EAX=len, -1=invalid, -2=EOF/error.
; Preserves all other registers. Drains overlong input; no truncation.
read_line:
    push ebx
    push ecx
    push edx
    push esi
    xor esi, esi
    mov byte [input_overflow], 0
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
    cmp esi, 127
    jae .overflow
    mov [input_buffer + esi], al
    inc esi
    jmp .read
.overflow:
    mov byte [input_overflow], 1
    jmp .read
.finish:
    test esi, esi
    jz .bad
    cmp byte [input_buffer + esi - 1], CR
    jne .validate
    dec esi
.validate:
    cmp byte [input_overflow], 0
    jne .bad
    xor ecx, ecx
    xor edx, edx
.scan:
    cmp ecx, esi
    jae .checked
    mov al, [input_buffer + ecx]
    cmp al, 32
    jb .bad
    cmp al, 126
    ja .bad
    cmp al, ' '
    je .space
    inc edx
.space:
    inc ecx
    jmp .scan
.checked:
    test edx, edx
    jz .bad
    mov eax, esi
    jmp .done
.bad:
    mov eax, -1
    jmp .done
.ended:
    mov eax, -2
.done:
    mov byte [input_buffer + esi], 0
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; Print zero-terminated text. NUL is a marker, not part of output.
puts:
    pushad
    xor edx, edx
.length:
    cmp byte [ecx + edx], 0
    je .write
    inc edx
    jmp .length
.write:
    mov ebx, STDOUT
    call write_all
    popad
    ret

; Convert EAX to a NUL-terminated decimal string.
format_uint:
    push ebx
    push esi
    push edi
    mov edi, number_buffer + 10
    mov byte [edi], 0
    mov ebx, 10
    xor esi, esi
.digit:
    xor edx, edx
    div ebx
    add dl, '0'
    dec edi
    mov [edi], dl
    inc esi
    test eax, eax
    jnz .digit
    mov ecx, edi
    mov edx, esi
    pop edi
    pop esi
    pop ebx
    ret

print_uint:
    pushad
    call format_uint
    mov ebx, STDOUT
    call write_all
    popad
    ret

; Red error adapter; preserve EDX as well as other caller registers.
print_error:
    push edx
    mov edx, color_red
    call print_colored
    pop edx
    ret

; ECX=message, EDX=color. Shared by red errors and yellow warnings.
print_colored:
    pushad
    mov esi, ecx
    mov ecx, edx
    call puts
    mov ecx, esi
    call puts
    PRINT color_reset
    popad
    ret

write_all:
    pushad
.next:
    test edx, edx
    jz .done
    mov eax, SYS_WRITE
    int 0x80
    cmp eax, EINTR
    je .next
    test eax, eax
    jle io_failed
    add ecx, eax
    sub edx, eax
    jmp .next
.done:
    popad
    ret

close_journal:
    mov ebx, [journal_fd]
    cmp ebx, -1
    je .done
    mov dword [journal_fd], -1
    mov eax, SYS_CLOSE
    int 0x80
    test eax, eax
    js io_failed
.done:
    ret

input_finished:
    WARN input_end
    call close_journal
    mov ebx, 1
    jmp exit_program
corrupt:
    mov ecx, corrupt_error
    jmp fatal
io_failed:
    mov ecx, file_error

; Direct error output avoids recursive failure through puts.
fatal:
    mov esi, ecx
    mov eax, SYS_WRITE
    mov ebx, STDERR
    mov ecx, color_red
    mov edx, 7
    int 0x80
    mov ecx, esi
    xor edx, edx
.length:
    cmp byte [ecx + edx], 0
    je .write
    inc edx
    jmp .length
.write:
    mov eax, SYS_WRITE
    mov ebx, STDERR
    int 0x80
    mov eax, SYS_WRITE
    mov ebx, STDERR
    mov ecx, color_reset
    mov edx, 4
    int 0x80
    mov ebx, [journal_fd]
    cmp ebx, -1
    je .exit
    mov eax, SYS_CLOSE
    int 0x80
.exit:
    mov ebx, 1
exit_program:
    mov eax, SYS_EXIT
    int 0x80

section .note.GNU-stack noalloc noexec nowrite progbits