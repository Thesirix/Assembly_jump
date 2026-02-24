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
global sky_render            ; Dégradé de ciel SIMD avec smooth coloring

extern player_y
extern backbuffer
extern camera_y

; (wrap_smooth_log retiré : remplacé par formule linéaire directe dans sky_render)

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

; --- Constantes pour sky_render ---
; Couleur de départ : 0x0087CEEB = Sky Blue Windows
; En format GDI DIB (BGR32) : R=0x87=135, G=0xCE=206, B=0xEB=235
sky_start_R dd 135          ; R de départ (0x87)
sky_start_G dd 206          ; G de départ (0xCE)
sky_start_B dd 235          ; B de départ (0xEB)

; Couleur d'arrivée : nuit profonde
sky_end_R dd 0              ; R nuit
sky_end_G dd 0              ; G nuit
sky_end_B dd 50             ; B nuit (légère teinte bleue)

section .bss
global current_score
current_score resd 1
highest_y resd 1
start_y   resd 1
text_color resd 1

; (sky_alt_smooth retiré : plus utilisé)

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

draw_game_over:
    push rbx
    push r12
    push r13

    lea rsi, [rel backbuffer]

    ; Fond sombre
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

    call draw_text_gameover

    ; Score centré
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

    call draw_text_restart

    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; sky_render — Dégradé de ciel avec smooth coloring Mandelbrot
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
    sub rsp, 40                     ; shadow space (pas d'appel C ici, mais bonne pratique)

    lea rdi, [rel backbuffer]

    ; --- Altitude linéaire : ebp = clamp(abs(camera_y) / 60, 0, 255) ---
    mov eax, [rel camera_y]
    neg eax                         ; abs(camera_y)
    cmp eax, 0
    jge .sky_pos
    xor eax, eax
.sky_pos:
    xor edx, edx
    mov ecx, 60                     ; diviseur : transition lente
    div ecx                         ; eax = abs(camera_y) / 60
    cmp eax, 255
    jle .sky_alt_ok
    mov eax, 255
.sky_alt_ok:
    mov ebp, eax                    ; ebp = altitude [0,255]

    ; --- Calculer top_R = lerp(135, 0, ebp/255) ---
    ; R top
    mov eax, [rel sky_start_R]      ; eax = 135
    mov ecx, 255
    sub ecx, ebp                    ; ecx = 255 - alt_smooth
    imul eax, ecx                   ; eax = 135 * (255 - alt)
    xor edx, edx
    mov ecx, 255
    div ecx                         ; eax = top_R [0,135]
    mov r12d, eax                   ; r12d = top_R

    ; G top
    mov eax, [rel sky_start_G]      ; eax = 206
    mov ecx, 255
    sub ecx, ebp
    imul eax, ecx                   ; eax = 206 * (255 - alt)
    xor edx, edx
    mov ecx, 255
    div ecx                         ; eax = top_G [0,206]
    mov r13d, eax                   ; r13d = top_G

    ; B top = lerp(235, 50, alt/255) = 235 - (235-50)*alt/255 = 235 - 185*alt/255
    mov eax, 185                    ; 235 - 50 = 185
    imul eax, ebp                   ; eax = 185 * alt
    xor edx, edx
    mov ecx, 255
    div ecx                         ; eax = delta_B
    mov ecx, [rel sky_start_B]      ; ecx = 235
    sub ecx, eax                    ; ecx = 235 - delta = top_B
    cmp ecx, [rel sky_end_B]        ; ne pas descendre sous sky_end_B (50)
    jge .b_ok
    mov ecx, 50
.b_ok:
    mov r14d, ecx                   ; r14d = top_B

    ; --- Assembler top_color (0x00RRGGBB) ---
    mov eax, r12d                   ; R
    shl eax, 16
    mov ecx, r13d                   ; G
    shl ecx, 8
    or eax, ecx
    or eax, r14d                    ; B
    mov r12d, eax                   ; r12d = top_color RGB32

    ; --- Calculer bottom_color = top + (20, 15, 10) clampé ---
    ; R_bot = clamp(top_R + 20, 0, 255)
    mov eax, r12d
    shr eax, 16
    and eax, 0xFF                   ; extraire R de top_color
    add eax, 20
    cmp eax, 255
    jle .rb_ok
    mov eax, 255
.rb_ok:
    mov r13d, eax                   ; R_bot

    ; G_bot = clamp(top_G + 15, 0, 255)
    mov eax, r12d
    shr eax, 8
    and eax, 0xFF                   ; extraire G de top_color
    add eax, 15
    cmp eax, 255
    jle .gb_ok
    mov eax, 255
.gb_ok:
    mov r14d, eax                   ; G_bot

    ; B_bot = clamp(top_B + 10, 0, 255)
    mov eax, r12d
    and eax, 0xFF                   ; extraire B de top_color
    add eax, 10
    cmp eax, 255
    jle .bb_ok
    mov eax, 255
.bb_ok:
    mov r15d, eax                   ; B_bot

    ; Assembler bottom_color 0x00RRGGBB
    mov eax, r13d                   ; R_bot
    shl eax, 16
    mov ecx, r14d                   ; G_bot
    shl ecx, 8
    or eax, ecx
    or eax, r15d                    ; B_bot
    mov r13d, eax                   ; r13d = bottom_color

    ; --- Extraire composantes R,G,B de top et bottom pour interpolation ---
    ; top_R = (r12d>>16) & 0xFF → rbp
    mov eax, r12d
    shr eax, 16
    and eax, 0xFF
    mov ebp, eax                    ; rbp = top_R

    ; top_G = (r12d>>8) & 0xFF → rsi
    mov eax, r12d
    shr eax, 8
    and eax, 0xFF
    mov esi, eax                    ; esi = top_G

    ; top_B = r12d & 0xFF → rbx
    mov eax, r12d
    and eax, 0xFF
    mov ebx, eax                    ; ebx = top_B

    ; ============================================================
    ; Optimisation sky_render : accumulation incrémentale + AVX2 fill
    ;
    ; AVANT : 3 × idiv (600) par ligne × 600 lignes = 1800 idiv/frame
    ;         200 movdqu SSE2 par ligne (4 pixels)
    ;
    ; APRÈS : 3 idiv UNE SEULE FOIS (calcul du pas), puis additions
    ;         100 vmovdqu AVX2 par ligne (8 pixels) → ×2 sur le fill
    ;
    ; Gain total estimé : ×8-15 sur sky_render
    ; ============================================================

    ; --- Pré-calculer step_R, step_G, step_B (3 idiv, faits UNE SEULE FOIS) ---
    ; step = (bot - top) * 256 / SCREEN_H  (point fixe 8.8)
    ; Chaque ligne ajoute le step à l'accumulateur.
    ; Résultat par ligne : top + (acc >> 8)

    ; step_R
    mov eax, r13d
    shr eax, 16
    and eax, 0xFF                   ; bot_R
    sub eax, ebp                    ; delta_R = bot_R - top_R
    shl eax, 8                      ; delta_R << 8
    cdq
    mov ecx, SCREEN_H
    idiv ecx                        ; step_R (8.8 fixe)
    push rax                        ; [rsp+24] = step_R

    ; step_G
    mov eax, r13d
    shr eax, 8
    and eax, 0xFF                   ; bot_G
    sub eax, esi                    ; delta_G
    shl eax, 8
    cdq
    mov ecx, SCREEN_H
    idiv ecx                        ; step_G
    push rax                        ; [rsp+16] = step_G

    ; step_B
    mov eax, r13d
    and eax, 0xFF                   ; bot_B
    sub eax, ebx                    ; delta_B
    shl eax, 8
    cdq
    mov ecx, SCREEN_H
    idiv ecx                        ; step_B
    push rax                        ; [rsp+8] = step_B

    ; acc_B sur le stack (mutable chaque ligne), acc_R et acc_G dans r12d/r13d
    xor eax, eax
    push rax                        ; [rsp+0] = acc_B = 0
    xor r12d, r12d                  ; acc_R = 0  (r12d libéré après extraction)
    xor r13d, r13d                  ; acc_G = 0  (r13d libéré après extraction)

    ; --- Boucle sur 600 lignes ---
    xor r14d, r14d                  ; r14d = ligne courante (0..599)

.sky_line:
    cmp r14d, SCREEN_H
    jge .sky_done

    ; R(y) = top_R + (acc_R >> 8)
    mov eax, r12d
    sar eax, 8
    add eax, ebp                    ; + top_R (ebp)
    cmp eax, 0
    jge .sr_pos
    xor eax, eax
.sr_pos:
    cmp eax, 255
    jle .sr_ok
    mov eax, 255
.sr_ok:
    shl eax, 16
    mov r15d, eax

    ; G(y) = top_G + (acc_G >> 8)
    mov eax, r13d
    sar eax, 8
    add eax, esi                    ; + top_G (esi)
    cmp eax, 0
    jge .sg_pos
    xor eax, eax
.sg_pos:
    cmp eax, 255
    jle .sg_ok
    mov eax, 255
.sg_ok:
    shl eax, 8
    or r15d, eax

    ; B(y) = top_B + (acc_B >> 8)
    mov eax, dword [rsp]            ; acc_B
    sar eax, 8
    add eax, ebx                    ; + top_B (ebx)
    cmp eax, 0
    jge .sb_pos
    xor eax, eax
.sb_pos:
    cmp eax, 255
    jle .sb_ok
    mov eax, 255
.sb_ok:
    or r15d, eax

    ; --- Incrémenter les accumulateurs (additions, pas de divisions) ---
    mov ecx, dword [rsp+24]         ; step_R
    add r12d, ecx
    mov ecx, dword [rsp+16]         ; step_G
    add r13d, ecx
    mov ecx, dword [rsp+8]          ; step_B
    add dword [rsp], ecx            ; acc_B += step_B

    ; --- AVX2 : remplir 800 pixels (8 pixels par store = 100 stores) ---
    ; Gain ×2 vs SSE2 (200 movdqu → 100 vmovdqu)
    movd xmm0, r15d
    vpbroadcastd ymm0, xmm0        ; 8 pixels broadcast 256-bit

    mov eax, r14d
    imul eax, SCREEN_W
    lea rcx, [rdi + rax*4]

    mov edx, 100                    ; 800 / 8 = 100 stores AVX2
.sky_fill:
    vmovdqu [rcx], ymm0
    add rcx, 32
    dec edx
    jnz .sky_fill

    inc r14d
    jmp .sky_line

.sky_done:
    vzeroupper                      ; nettoyer état YMM (compatibilité SSE)
    add rsp, 32                     ; libérer 4 push × 8 = 32 bytes

    add rsp, 40                     ; libérer le sub rsp initial (doit matcher sub rsp, 40)
    pop rdi
    pop rsi
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret