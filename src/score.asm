BITS 64
DEFAULT REL

global score_init
global score_update
global score_get
global score_render
global draw_number_at
global draw_text_gameover
global draw_text_restart

extern player_y
extern backbuffer
extern camera_y

%define SCREEN_W 800
%define SCREEN_H 600

section .data
digits_bitmap:
    db 1,1,1, 1,0,1, 1,0,1, 1,0,1, 1,1,1 ; 0
    db 0,1,0, 0,1,0, 0,1,0, 0,1,0, 0,1,0 ; 1
    db 1,1,1, 0,0,1, 1,1,1, 1,0,0, 1,1,1 ; 2
    db 1,1,1, 0,0,1, 1,1,1, 0,0,1, 1,1,1 ; 3
    db 1,0,1, 1,0,1, 1,1,1, 0,0,1, 0,0,1 ; 4
    db 1,1,1, 1,0,0, 1,1,1, 0,0,1, 1,1,1 ; 5
    db 1,1,1, 1,0,0, 1,1,1, 1,0,1, 1,1,1 ; 6
    db 1,1,1, 0,0,1, 0,0,1, 0,0,1, 0,0,1 ; 7
    db 1,1,1, 1,0,1, 1,1,1, 1,0,1, 1,1,1 ; 8
    db 1,1,1, 1,0,1, 1,1,1, 0,0,1, 1,1,1 ; 9

letters_bitmap:
    db 0,1,0, 1,0,1, 1,1,1, 1,0,1, 1,0,1 ; A (0)
    db 1,1,1, 1,0,0, 1,1,1, 1,0,0, 1,1,1 ; E (1)
    db 1,1,1, 1,0,0, 1,0,1, 1,0,1, 1,1,1 ; G (2)
    db 1,0,1, 1,1,1, 1,0,1, 1,0,1, 1,0,1 ; M (3)
    db 1,1,1, 1,0,1, 1,0,1, 1,0,1, 1,1,1 ; O (4)
    db 1,1,1, 1,0,1, 1,1,0, 1,0,1, 1,0,1 ; R (5)
    db 1,1,1, 1,0,0, 1,1,1, 0,0,1, 1,1,1 ; S (6)
    db 1,1,1, 0,1,0, 0,1,0, 0,1,0, 0,1,0 ; T (7)
    db 1,0,1, 1,0,1, 1,0,1, 1,0,1, 0,1,0 ; V (8)
    db 0,1,0, 0,1,0, 0,1,0, 0,0,0, 0,1,0 ; ! (9)

section .bss
global current_score
current_score resd 1
highest_y resd 1
start_y   resd 1
text_color resd 1

section .text

score_init:
    mov dword [rel current_score], 0
    mov dword [rel highest_y], 520 
    mov dword [rel start_y], 520
    ret

score_update:
    mov eax, [rel player_y]
    add eax, [rel camera_y]
    
    mov edx, [rel highest_y]
    cmp eax, edx
    jge .done
    
    mov [rel highest_y], eax
    
    mov ecx, [rel start_y]
    sub ecx, eax
    
    xor edx, edx
    mov eax, ecx
    mov ecx, 2
    div ecx
    
    mov [rel current_score], eax
.done:
    ret

score_get:
    mov eax, [rel current_score]
    ret

; ==================================================
; Affiche "GAME OVER" (CENTRÉ)
; ==================================================
draw_text_gameover:
    push r14
    push r15
    mov dword [rel text_color], 0x00FFFFFF 
    
    ; Largeur totale ~250px. Centre 400. Début = 275.
    mov r14d, 275 ; X corrigé (était 280)
    mov r15d, 150 ; Y
    
    ; "GAME"
    mov rax, 2 ; G
    call draw_letter_raw
    add r14d, 25
    mov rax, 0 ; A
    call draw_letter_raw
    add r14d, 25
    mov rax, 3 ; M
    call draw_letter_raw
    add r14d, 25
    mov rax, 1 ; E
    call draw_letter_raw
    
    ; "OVER!" commence à 400 pile (400 - 125/2 + 62.5... non, 400 tout court)
    ; Fin de GAME = 275 + 100 = 375.
    ; Espace 25px -> 400.
    mov r14d, 400 ; X Espace
    
    mov rax, 4 ; O
    call draw_letter_raw
    add r14d, 25
    mov rax, 8 ; V
    call draw_letter_raw
    add r14d, 25
    mov rax, 1 ; E
    call draw_letter_raw
    add r14d, 25
    mov rax, 5 ; R
    call draw_letter_raw
    add r14d, 25
    mov rax, 9 ; !
    call draw_letter_raw
    
    pop r15
    pop r14
    ret

; ==================================================
; Affiche "RESTART" (CENTRÉ)
; ==================================================
draw_text_restart:
    push r14
    push r15
    mov dword [rel text_color], 0x00FFFFFF
    
    ; Largeur 175px. Centre 400. Début = 312.
    mov r14d, 312 ; X corrigé (était 315)
    mov r15d, 315 ; Y
    
    mov rax, 5 ; R
    call draw_letter_raw
    add r14d, 25
    mov rax, 1 ; E
    call draw_letter_raw
    add r14d, 25
    mov rax, 6 ; S
    call draw_letter_raw
    add r14d, 25
    mov rax, 7 ; T
    call draw_letter_raw
    add r14d, 25
    mov rax, 0 ; A
    call draw_letter_raw
    add r14d, 25
    mov rax, 5 ; R
    call draw_letter_raw
    add r14d, 25
    mov rax, 7 ; T
    call draw_letter_raw

    pop r15
    pop r14
    ret

draw_letter_raw:
    push rcx
    push rdx
    
    imul eax, 15
    lea rsi, [rel letters_bitmap]
    add rsi, rax
    
    xor ecx, ecx 
.line:
    xor edx, edx
.col:
    lodsb 
    cmp al, 0
    je .skip
    
    push r8
    push r9
    
    mov r8d, r14d
    lea eax, [edx*4] 
    add eax, edx     
    add r8d, eax
    
    mov r9d, r15d
    lea eax, [ecx*4] 
    add eax, ecx     
    add r9d, eax
    
    call draw_fat_pixel_large
    pop r9
    pop r8
.skip:
    inc edx
    cmp edx, 3
    jl .col
    inc ecx
    cmp ecx, 5
    jl .line
    pop rdx
    pop rcx
    ret

draw_number_at:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40

    mov r14d, r8d  ; X
    mov r15d, r9d  ; Y
    
    mov dword [rel text_color], 0x00FFD700 ; OR

    mov eax, ecx
    mov rbx, 10
    xor ecx, ecx

    test eax, eax
    jnz .div_loop
    push 0
    inc ecx
    jmp .draw_stack_loop

.div_loop:
    xor edx, edx
    div rbx
    push rdx
    inc ecx
    test eax, eax
    jnz .div_loop

.draw_stack_loop:
    pop rax
    call draw_single_digit
    add r14d, 15
    dec ecx
    jnz .draw_stack_loop

    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

draw_single_digit:
    push rcx
    push rdx
    imul eax, 15
    lea rsi, [rel digits_bitmap]
    add rsi, rax
    xor ecx, ecx 
.l:
    xor edx, edx
.c:
    lodsb 
    cmp al, 0
    je .s
    push r8
    push r9
    mov r8d, r14d
    lea eax, [edx*4]
    add r8d, eax
    mov r9d, r15d
    lea eax, [ecx*4]
    add r9d, eax
    call draw_fat_pixel
    pop r9
    pop r8
.s:
    inc edx
    cmp edx, 3
    jl .c
    inc ecx
    cmp ecx, 5
    jl .l
    pop rdx
    pop rcx
    ret

draw_fat_pixel:
    push rdi
    push rax
    lea rdi, [rel backbuffer]
    mov r10d, 0
.dy:
    mov r11d, 0
.dx:
    mov eax, r9d
    add eax, r10d
    imul eax, SCREEN_W
    add eax, r8d
    add eax, r11d
    cmp eax, 0
    jl .sk
    cmp eax, SCREEN_W*SCREEN_H
    jge .sk
    
    mov dword [rdi + rax*4], 0x00000000
.sk:
    inc r11d
    cmp r11d, 4
    jl .dx
    inc r10d
    cmp r10d, 4
    jl .dy
    pop rax
    pop rdi
    ret

draw_fat_pixel_large:
    push rdi
    push rax
    lea rdi, [rel backbuffer]
    mov r10d, 0
.dy:
    mov r11d, 0
.dx:
    mov eax, r9d
    add eax, r10d
    imul eax, SCREEN_W
    add eax, r8d
    add eax, r11d
    cmp eax, 0
    jl .sk2
    cmp eax, SCREEN_W*SCREEN_H
    jge .sk2
    
    mov ebx, [rel text_color]
    mov dword [rdi + rax*4], ebx
.sk2:
    inc r11d
    cmp r11d, 5
    jl .dx
    inc r10d
    cmp r10d, 5
    jl .dy
    pop rax
    pop rdi
    ret

score_render:
    mov ecx, [rel current_score]
    mov r8d, 10
    mov r9d, 10
    call draw_number_at
    ret