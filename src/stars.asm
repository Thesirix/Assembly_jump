BITS 64
DEFAULT REL

; =================================================================
; stars.asm — Parallax starfield background (3 layers) + scintillement
; =================================================================
; Layer 0 : 40 small  distant stars, scroll speed = camera_y / 8 (slow)
;           Taille 1x1, PAS de scintillement (trop loin)
; Layer 1 : 30 medium stars,         scroll speed = camera_y / 4
;           Taille 2x2, scintillement actif
; Layer 2 : 20 large  close stars,   scroll speed = camera_y / 2 (fast)
;           Taille 3x3 (croix), scintillement actif
; =================================================================

global stars_init
global stars_render

extern backbuffer
extern camera_y

%define SCREEN_W    800
%define SCREEN_H    600

%define LAYER0_COUNT  40
%define LAYER1_COUNT  30
%define LAYER2_COUNT  20
%define TOTAL_STARS   (LAYER0_COUNT + LAYER1_COUNT + LAYER2_COUNT)

%define STAR_WORLD_H  50000

section .data

star_seed dd 31337

; Couleurs de base par couche
star_color0 dd 0x00555577      ; Bleu-gris (lointaines)
star_color1 dd 0x008888AA      ; Bleu moyen
star_color2 dd 0x00CCCCFF      ; Blanc-bleu vif (proches)

section .bss

star_x      resd TOTAL_STARS
star_y      resd TOTAL_STARS
star_phase  resb TOTAL_STARS   ; Phase de scintillement (0..255)

section .text

; ============================================================
; star_random — LCG
; ============================================================
star_random:
    push rbx
    mov eax, [rel star_seed]
    mov ebx, 1103515245
    imul eax, ebx
    add eax, 12345
    mov [rel star_seed], eax
    shr eax, 16
    and eax, 0x7FFF
    pop rbx
    ret

; ============================================================
; stars_init — Generer positions et phases
; ============================================================
stars_init:
    push rbx
    push r12
    push r13
    sub rsp, 48

    rdtsc
    xor eax, 0xCAFEBABE
    mov [rel star_seed], eax

    lea r12, [rel star_x]
    lea r13, [rel star_y]
    xor ebx, ebx

.gen_loop:
    cmp ebx, TOTAL_STARS
    jge .init_phase

    call star_random
    xor edx, edx
    mov ecx, SCREEN_W
    div ecx
    mov [r12 + rbx*4], edx

    call star_random
    imul eax, eax, 3
    xor edx, edx
    mov ecx, STAR_WORLD_H
    div ecx
    neg edx
    mov [r13 + rbx*4], edx

    inc ebx
    jmp .gen_loop

.init_phase:
    ; Phases aleatoires
    lea r12, [rel star_phase]
    xor ebx, ebx
.phase_loop:
    cmp ebx, TOTAL_STARS
    jge .done
    call star_random
    and eax, 0xFF
    mov [r12 + rbx], al
    inc ebx
    jmp .phase_loop

.done:
    add rsp, 48
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; stars_render — 3 couches parallax + scintillement
; ============================================================
stars_render:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rsi
    sub rsp, 40

    lea rsi, [rel backbuffer]
    lea r14, [rel star_x]
    lea r15, [rel star_y]

    ; ---- LAYER 0 : lointaines, 1x1, pas de scintillement ----
    xor ebx, ebx
    mov r12d, [rel camera_y]
    sar r12d, 3
.layer0:
    cmp ebx, LAYER0_COUNT
    jge .start_layer1

    ; Incrementer phase (meme si pas utilisee pour layer0)
    lea rax, [rel star_phase]
    inc byte [rax + rbx]

    mov eax, [r15 + rbx*4]
    sub eax, r12d
    cdq
    mov ecx, SCREEN_H
    idiv ecx
    mov eax, edx
    test eax, eax
    jge .l0_pos
    add eax, SCREEN_H
.l0_pos:
    cmp eax, SCREEN_H
    jge .l0_next

    mov ecx, [r14 + rbx*4]
    cmp ecx, 0
    jl .l0_next
    cmp ecx, SCREEN_W
    jge .l0_next

    imul eax, SCREEN_W
    add eax, ecx
    mov edx, [rel star_color0]
    mov [rsi + rax*4], edx

.l0_next:
    inc ebx
    jmp .layer0

    ; ---- LAYER 1 : moyennes, 2x2, scintillement ----
.start_layer1:
    mov ebx, LAYER0_COUNT
    mov r12d, [rel camera_y]
    sar r12d, 2
.layer1:
    cmp ebx, LAYER0_COUNT + LAYER1_COUNT
    jge .start_layer2

    ; Incrementer phase
    lea rax, [rel star_phase]
    inc byte [rax + rbx]

    mov eax, [r15 + rbx*4]
    sub eax, r12d
    cdq
    mov ecx, SCREEN_H
    idiv ecx
    mov eax, edx
    test eax, eax
    jge .l1_pos
    add eax, SCREEN_H
.l1_pos:
    cmp eax, SCREEN_H - 1
    jge .l1_next

    mov ecx, [r14 + rbx*4]
    cmp ecx, 0
    jl .l1_next
    cmp ecx, SCREEN_W - 1
    jge .l1_next

    ; Couleur + scintillement
    ; Si (phase & 0x1F) >= 24 : ajouter luminosite
    lea r13, [rel star_phase]
    movzx edx, byte [r13 + rbx]
    and edx, 0x1F
    mov r13d, [rel star_color1]
    cmp edx, 24
    jl .l1_draw
    ; Ajouter 0x40 a chaque composante avec clamp
    mov edx, r13d
    mov eax, edx
    and eax, 0xFF
    add eax, 0x40
    cmp eax, 0xFF
    cmovg eax, [rel star_color2] ; hack: just clamp
    and eax, 0xFF
    mov r13d, eax
    mov eax, edx
    shr eax, 8
    and eax, 0xFF
    add eax, 0x40
    cmp eax, 0xFF
    jle .l1_g
    mov eax, 0xFF
.l1_g:
    shl eax, 8
    or r13d, eax
    mov eax, edx
    shr eax, 16
    and eax, 0xFF
    add eax, 0x40
    cmp eax, 0xFF
    jle .l1_b
    mov eax, 0xFF
.l1_b:
    shl eax, 16
    or r13d, eax

.l1_draw:
    ; Dessiner 2x2
    mov eax, [r15 + rbx*4]
    sub eax, r12d
    cdq
    mov ecx, SCREEN_H
    idiv ecx
    mov eax, edx
    test eax, eax
    jge .l1_pos2
    add eax, SCREEN_H
.l1_pos2:
    mov ecx, [r14 + rbx*4]
    imul eax, SCREEN_W
    add eax, ecx
    mov edx, r13d
    mov [rsi + rax*4], edx
    mov [rsi + rax*4 + 4], edx
    add eax, SCREEN_W
    mov [rsi + rax*4], edx
    mov [rsi + rax*4 + 4], edx

.l1_next:
    inc ebx
    jmp .layer1

    ; ---- LAYER 2 : proches, 3x3 croix, scintillement ----
.start_layer2:
    mov ebx, LAYER0_COUNT + LAYER1_COUNT
    mov r12d, [rel camera_y]
    sar r12d, 1
.layer2:
    cmp ebx, TOTAL_STARS
    jge .done

    ; Incrementer phase
    lea rax, [rel star_phase]
    inc byte [rax + rbx]

    mov eax, [r15 + rbx*4]
    sub eax, r12d
    cdq
    mov ecx, SCREEN_H
    idiv ecx
    mov eax, edx
    test eax, eax
    jge .l2_pos
    add eax, SCREEN_H
.l2_pos:
    cmp eax, SCREEN_H - 2
    jge .l2_next
    cmp eax, 1                  ; y >= 1 requis (croix écrit à y-1)
    jl .l2_next

    mov ecx, [r14 + rbx*4]
    cmp ecx, 1
    jl .l2_next
    cmp ecx, SCREEN_W - 2
    jge .l2_next

    ; Couleur + scintillement
    lea r13, [rel star_phase]
    movzx edx, byte [r13 + rbx]
    and edx, 0x1F
    mov r13d, [rel star_color2]
    cmp edx, 24
    jl .l2_draw
    ; Boost luminosite : clamp chaque composante a 255
    or r13d, 0x00FFFFFF         ; full white pour flash maximal

.l2_draw:
    mov eax, [r15 + rbx*4]
    sub eax, r12d
    cdq
    mov ecx, SCREEN_H
    idiv ecx
    mov eax, edx
    test eax, eax
    jge .l2_pos2
    add eax, SCREEN_H
.l2_pos2:
    mov ecx, [r14 + rbx*4]
    imul eax, SCREEN_W
    add eax, ecx
    mov edx, r13d

    ; Croix 3x3
    mov [rsi + rax*4 - 4], edx
    mov [rsi + rax*4], edx
    mov [rsi + rax*4 + 4], edx
    sub eax, SCREEN_W
    mov [rsi + rax*4], edx
    add eax, SCREEN_W
    add eax, SCREEN_W
    mov [rsi + rax*4], edx

.l2_next:
    inc ebx
    jmp .layer2

.done:
    add rsp, 40
    pop rsi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
