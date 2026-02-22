BITS 64
DEFAULT REL

global score_init
global score_update
global score_get
global score_render
global draw_number_at
global draw_text_gameover
global draw_text_restart
global draw_game_over
global sky_render            ; Dégradé de ciel SIMD

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

draw_text_gameover:
    push r14
    push r15
    mov dword [rel text_color], 0x00FFFFFF 
    mov r14d, 275 
    mov r15d, 150 
    mov rax, 2 
    call draw_letter_raw
    add r14d, 25
    mov rax, 0 
    call draw_letter_raw
    add r14d, 25
    mov rax, 3 
    call draw_letter_raw
    add r14d, 25
    mov rax, 1 
    call draw_letter_raw
    mov r14d, 400 
    mov rax, 4 
    call draw_letter_raw
    add r14d, 25
    mov rax, 8 
    call draw_letter_raw
    add r14d, 25
    mov rax, 1 
    call draw_letter_raw
    add r14d, 25
    mov rax, 5 
    call draw_letter_raw
    add r14d, 25
    mov rax, 9 
    call draw_letter_raw
    pop r15
    pop r14
    ret

draw_text_restart:
    push r14
    push r15
    mov dword [rel text_color], 0x00FFFFFF
    mov r14d, 312 
    mov r15d, 315 
    mov rax, 5 
    call draw_letter_raw
    add r14d, 25
    mov rax, 1 
    call draw_letter_raw
    add r14d, 25
    mov rax, 6 
    call draw_letter_raw
    add r14d, 25
    mov rax, 7 
    call draw_letter_raw
    add r14d, 25
    mov rax, 0 
    call draw_letter_raw
    add r14d, 25
    mov rax, 5 
    call draw_letter_raw
    add r14d, 25
    mov rax, 7 
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
    mov r14d, r8d  
    mov r15d, r9d  
    mov dword [rel text_color], 0x00FFD700 
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

; --- FONCTION MANQUANTE AJOUTÉE ICI ---
draw_game_over:
    push rbx
    push r12
    push r13
    
    lea rsi, [rel backbuffer]
    
    ; 1. Fond sombre
    mov r12d, 100       
.y_rect:
    mov r13d, 150       
.x_rect:
    mov eax, r12d
    imul eax, SCREEN_W
    add eax, r13d
    mov dword [rsi + rax*4], 0x00333333 
    inc r13d
    cmp r13d, 650
    jl .x_rect
    inc r12d
    cmp r12d, 500
    jl .y_rect
    
    ; 2. Texte GAME OVER
    call draw_text_gameover
    
    ; 3. Centrage score
    mov eax, [rel current_score]
    mov r10d, 1     
    mov ebx, 10
    test eax, eax
    jz .calc_pos
    mov r11d, eax   
    xor r10d, r10d  
.count:
    xor edx, edx
    mov eax, r11d
    div ebx
    mov r11d, eax
    inc r10d
    test r11d, r11d
    jnz .count
.calc_pos:
    mov eax, r10d
    imul eax, 15    
    shr eax, 1      
    mov r8d, 400    
    sub r8d, eax    
    mov ecx, [rel current_score]
    mov r9d, 230    
    call draw_number_at
    
    ; 4. Restart
    call draw_text_restart

    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; sky_render — Dégradé vertical de ciel adaptatif (remplace clear_backbuffer)
; Couleur top/bottom calculée depuis camera_y
; Utilise SSE2 pour remplir 4 pixels par store
; ============================================================
; Formule couleur :
;   altitude = clamp(abs(camera_y) / 200, 0, 255)
;   Top    : R = 0,             G = alt/3,      B = 50 + alt*0.6
;   Bottom : R = 20 + alt/4,    G = 40 + alt/2, B = 80 + alt*0.5
;   Chaque ligne interpole linéairement entre top et bottom
; ============================================================
sky_render:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    push rsi
    push rdi

    lea rdi, [rel backbuffer]

    ; Calculer altitude = clamp(abs(camera_y) / 200, 0, 255)
    mov eax, [rel camera_y]
    neg eax
    cmp eax, 0
    jge .sky_pos
    xor eax, eax
.sky_pos:
    xor edx, edx
    mov ecx, 200
    div ecx                     ; eax = abs(camera_y) / 200
    cmp eax, 255
    jle .sky_clamped
    mov eax, 255
.sky_clamped:
    mov ebp, eax                ; ebp = altitude (0..255)

    ; --- Calculer couleur top (BGR32) ---
    ; R_top = 0
    xor r12d, r12d
    ; G_top = altitude / 3
    mov eax, ebp
    xor edx, edx
    mov ecx, 3
    div ecx
    mov r13d, eax               ; G_top
    ; B_top = clamp(50 + altitude * 3 / 5, 0, 255)
    mov eax, ebp
    imul eax, 3
    xor edx, edx
    mov ecx, 5
    div ecx
    add eax, 50
    cmp eax, 255
    jle .bt_ok
    mov eax, 255
.bt_ok:
    mov r14d, eax               ; B_top

    ; top_color = B_top<<16 | G_top<<8 | R_top
    mov eax, r14d
    shl eax, 16
    mov ecx, r13d
    shl ecx, 8
    or eax, ecx
    or eax, r12d
    mov r12d, eax               ; r12d = top_color

    ; --- Calculer couleur bottom (BGR32) ---
    ; R_bot = 20 + altitude / 4
    mov eax, ebp
    shr eax, 2
    add eax, 20
    cmp eax, 255
    jle .rb_ok
    mov eax, 255
.rb_ok:
    mov r13d, eax               ; R_bot

    ; G_bot = 40 + altitude / 2
    mov eax, ebp
    shr eax, 1
    add eax, 40
    cmp eax, 255
    jle .gb_ok
    mov eax, 255
.gb_ok:
    mov r14d, eax               ; G_bot

    ; B_bot = clamp(80 + altitude / 2, 0, 255)
    mov eax, ebp
    shr eax, 1
    add eax, 80
    cmp eax, 255
    jle .bb_ok
    mov eax, 255
.bb_ok:
    mov r15d, eax               ; B_bot

    ; bottom_color
    mov eax, r15d
    shl eax, 16
    mov ecx, r14d
    shl ecx, 8
    or eax, ecx
    or eax, r13d
    mov r13d, eax               ; r13d = bottom_color

    ; --- Extraire composantes pour interpolation ---
    ; top: r12d = packed, bottom: r13d = packed
    ; On interpole par ligne : color(y) = top + (bottom - top) * y / 600

    ; Extraire R, G, B top
    mov eax, r12d
    and eax, 0xFF
    mov ebp, eax                ; R_top (on réutilise ebp)

    mov eax, r12d
    shr eax, 8
    and eax, 0xFF
    mov esi, eax                ; G_top (dans esi)

    mov eax, r12d
    shr eax, 16
    and eax, 0xFF
    mov ebx, eax                ; B_top (dans ebx)

    ; Extraire R, G, B bottom et calculer deltas * 256
    ; delta_R = (R_bot - R_top)
    mov eax, r13d
    and eax, 0xFF
    sub eax, ebp
    ; delta_R * 256 pour précision fixe
    shl eax, 8
    push rax                    ; [rsp] = delta_R << 8

    mov eax, r13d
    shr eax, 8
    and eax, 0xFF
    sub eax, esi
    shl eax, 8
    push rax                    ; [rsp] = delta_G << 8, [rsp+8] = delta_R << 8

    mov eax, r13d
    shr eax, 16
    and eax, 0xFF
    sub eax, ebx
    shl eax, 8
    push rax                    ; [rsp] = delta_B << 8

    ; Maintenant itérer sur les 600 lignes
    xor r14d, r14d              ; r14d = ligne courante (0..599)

.sky_line:
    cmp r14d, SCREEN_H
    jge .sky_done

    ; R = R_top + delta_R * y / 600
    ; En fixed point: R = R_top + (delta_R<<8) * y / 600 >> 8
    mov eax, [rsp + 16]         ; delta_R << 8
    imul eax, r14d
    cdq
    mov ecx, SCREEN_H
    idiv ecx
    sar eax, 8
    add eax, ebp                ; + R_top
    ; Clamp
    cmp eax, 0
    jge .sr_pos
    xor eax, eax
.sr_pos:
    cmp eax, 255
    jle .sr_ok
    mov eax, 255
.sr_ok:
    mov r15d, eax               ; R final

    ; G
    mov eax, [rsp + 8]          ; delta_G << 8
    imul eax, r14d
    cdq
    mov ecx, SCREEN_H
    idiv ecx
    sar eax, 8
    add eax, esi                ; + G_top
    cmp eax, 0
    jge .sg_pos
    xor eax, eax
.sg_pos:
    cmp eax, 255
    jle .sg_ok
    mov eax, 255
.sg_ok:
    shl eax, 8
    or r15d, eax                ; |= G << 8

    ; B
    mov eax, [rsp]              ; delta_B << 8
    imul eax, r14d
    cdq
    mov ecx, SCREEN_H
    idiv ecx
    sar eax, 8
    add eax, ebx                ; + B_top
    cmp eax, 0
    jge .sb_pos
    xor eax, eax
.sb_pos:
    cmp eax, 255
    jle .sb_ok
    mov eax, 255
.sb_ok:
    shl eax, 16
    or r15d, eax                ; |= B << 16

    ; --- SSE2 : remplir 800 pixels de cette ligne (4 pixels par store) ---
    ; Broadcast r15d dans xmm0
    movd xmm0, r15d
    pshufd xmm0, xmm0, 0       ; [color, color, color, color]

    ; Calculer adresse de début de ligne
    mov eax, r14d
    imul eax, SCREEN_W
    lea rcx, [rdi + rax*4]     ; rcx = &backbuffer[y * 800]

    ; 800 pixels / 4 = 200 itérations SSE2
    mov edx, 200
.sky_fill:
    movdqu [rcx], xmm0
    add rcx, 16
    dec edx
    jnz .sky_fill

    inc r14d
    jmp .sky_line

.sky_done:
    add rsp, 24                 ; libérer les 3 push delta
    pop rdi
    pop rsi
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret