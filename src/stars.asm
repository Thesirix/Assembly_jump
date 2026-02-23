BITS 64
DEFAULT REL

; =================================================================
; stars.asm — Fireflies (Lucioles) parallax + Mouvement brownien
; =================================================================
; Layer 0 : 40 petites lucioles sombres au loin (1x1)
; Layer 1 : 30 lucioles moyennes (2x2), pulsation douce
; Layer 2 : 20 grosses lucioles (croix 3x3 avec centre blanc)
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

; Couleurs Zelda / Forêt (Format GDI : 0x00RRGGBB)
star_color0 dd 0x00113311      ; Vert sombre (lointaines)
star_color1 dd 0x00338822      ; Vert forêt (moyennes)
star_color2 dd 0x0099FF33      ; Jaune-vert vif (proches)

section .bss

star_x      resd TOTAL_STARS
star_y      resd TOTAL_STARS
star_vx     resd TOTAL_STARS   ; Vélocité X pour la dérive
star_vy     resd TOTAL_STARS   ; Vélocité Y pour la dérive
star_phase  resb TOTAL_STARS   ; Phase de pulsation (0..255)
star_tick   resd 1             ; Compteur global pour ralentir la dérive

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
; stars_init — Générer positions, phases et vélocités
; ============================================================
stars_init:
    push rbx
    push r12
    push r13
    sub rsp, 48

    rdtsc
    xor eax, 0xCAFEBABE
    mov [rel star_seed], eax
    mov dword [rel star_tick], 0

    lea r12, [rel star_x]
    lea r13, [rel star_y]
    xor ebx, ebx

.gen_loop:
    cmp ebx, TOTAL_STARS
    jge .init_phase

    ; X aléatoire
    call star_random
    xor edx, edx
    mov ecx, SCREEN_W
    div ecx
    mov [r12 + rbx*4], edx

    ; Y aléatoire dans le monde
    call star_random
    imul eax, eax, 3
    xor edx, edx
    mov ecx, STAR_WORLD_H
    div ecx
    neg edx
    mov [r13 + rbx*4], edx

    ; Vélocité initiale à 0
    lea rax, [rel star_vx]
    mov dword [rax + rbx*4], 0
    lea rax, [rel star_vy]
    mov dword [rax + rbx*4], 0

    inc ebx
    jmp .gen_loop

.init_phase:
    ; Phases aléatoires
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
; stars_render — Rendu des lucioles avec dérive organique
; ============================================================
stars_render:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rsi
    push rbp
    sub rsp, 40

    ; --- 1. MISE À JOUR : MOUVEMENT BROWNIEN LENT ---
    inc dword [rel star_tick]
    xor ebx, ebx
    lea r14, [rel star_vx]
    lea r15, [rel star_vy]

.update_loop:
    cmp ebx, TOTAL_STARS
    jge .render_layers

    ; 1 chance sur 64 de changer de direction (vol beaucoup plus lent/paresseux)
    call star_random
    test eax, 63
    jnz .apply_vel

    ; Changer vx (-1, 0, ou +1)
    call star_random
    xor edx, edx
    mov ecx, 3
    div ecx
    sub edx, 1                  ; edx = -1, 0, 1
    mov eax, [r14 + rbx*4]
    add eax, edx
    ; Clamp vélocité X entre -1 et 1
    cmp eax, -1
    jge .vx_min
    mov eax, -1
.vx_min:
    cmp eax, 1
    jle .vx_max
    mov eax, 1
.vx_max:
    mov [r14 + rbx*4], eax

    ; Changer vy (-1, 0, ou +1)
    call star_random
    xor edx, edx
    mov ecx, 3
    div ecx
    sub edx, 1
    mov eax, [r15 + rbx*4]
    add eax, edx
    ; Clamp vélocité Y entre -1 et 1
    cmp eax, -1
    jge .vy_min
    mov eax, -1
.vy_min:
    cmp eax, 1
    jle .vy_max
    mov eax, 1
.vy_max:
    mov [r15 + rbx*4], eax

.apply_vel:
    ; Pour que ce soit très lent, on n'applique la vélocité qu'une frame sur 8
    test dword [rel star_tick], 7
    jnz .skip_move

    ; Appliquer la vélocité sur X (avec wrap aux bords de l'écran)
    lea r12, [rel star_x]
    mov eax, [r12 + rbx*4]
    add eax, [r14 + rbx*4]
    
    cmp eax, 0
    jge .chk_w
    add eax, SCREEN_W           ; Wrap par la gauche
    jmp .save_x
.chk_w:
    cmp eax, SCREEN_W
    jl .save_x
    sub eax, SCREEN_W           ; Wrap par la droite
.save_x:
    mov [r12 + rbx*4], eax

    ; Appliquer la vélocité sur Y (le monde est infini, on laisse dériver)
    lea r13, [rel star_y]
    mov eax, [r13 + rbx*4]
    add eax, [r15 + rbx*4]
    mov [r13 + rbx*4], eax

.skip_move:
    inc ebx
    jmp .update_loop

    ; --- 2. RENDU DES LAYERS (PARALLAX PLUS PROFOND) ---
.render_layers:
    lea rsi, [rel backbuffer]
    lea r14, [rel star_x]
    lea r15, [rel star_y]

    ; ---- LAYER 0 : Lointaines, sombres, pas de pulsation ----
    xor ebx, ebx
    mov r12d, [rel camera_y]
    sar r12d, 4                 ; Vitesse parallax très lente (1/16)
.layer0:
    cmp ebx, LAYER0_COUNT
    jge .start_layer1

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

    ; ---- LAYER 1 : Moyennes, vertes, pulsation douce (2x2) ----
.start_layer1:
    mov ebx, LAYER0_COUNT
    mov r12d, [rel camera_y]
    sar r12d, 3                 ; Vitesse parallax moyenne-lente (1/8)
.layer1:
    cmp ebx, LAYER0_COUNT + LAYER1_COUNT
    jge .start_layer2

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

    ; Pulsation "respiration" de la luciole très lente
    lea r13, [rel star_phase]
    movzx edx, byte [r13 + rbx]
    mov ecx, edx
    shr ecx, 3                  ; Cycle ralenti par 8 (respiration profonde)
    and ecx, 0x0F               ; Cycle de 0 à 15
    mov r13d, [rel star_color1]
    cmp ecx, 12                 ; Lueur à l'inspiration max
    jl .l1_draw
    mov r13d, 0x0077CC33        ; Halo plus clair

.l1_draw:
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

    ; ---- LAYER 2 : Grosses lucioles proches (Croix avec Glow) ----
.start_layer2:
    mov ebx, LAYER0_COUNT + LAYER1_COUNT
    mov r12d, [rel camera_y]
    sar r12d, 2                 ; Vitesse parallax plus rapide (1/4)
.layer2:
    cmp ebx, TOTAL_STARS
    jge .done

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
    cmp eax, SCREEN_H - 1
    jge .l2_next
    cmp eax, 1                  ; Marge requise pour dessiner la croix
    jl .l2_next

    mov ecx, [r14 + rbx*4]
    cmp ecx, 1
    jl .l2_next
    cmp ecx, SCREEN_W - 2
    jge .l2_next

    ; Pulsation "respiration" très lente
    lea r13, [rel star_phase]
    movzx edx, byte [r13 + rbx]
    mov ecx, edx
    shr ecx, 3                  ; Ralenti par 8
    and ecx, 0x0F
    
    mov r13d, [rel star_color2] ; Bordure de la luciole (halo)
    mov ebp, 0x00CCFF77         ; Centre de la luciole
    
    cmp ecx, 14                 ; Pic de respiration
    jl .l2_draw
    mov r13d, 0x00CCFF77        ; Halo devient très brillant
    mov ebp, 0x00FFFFFF         ; Centre devient pur blanc

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
    
    ; Dessiner la croix (Bords = Halo edx, Centre = ebp pur)
    mov [rsi + rax*4 - 4], edx          ; Gauche
    mov [rsi + rax*4 + 4], edx          ; Droite
    mov [rsi + rax*4], ebp              ; Centre
    
    mov r8d, eax
    sub r8d, SCREEN_W
    mov [rsi + r8*4], edx               ; Haut
    
    mov r8d, eax
    add r8d, SCREEN_W
    mov [rsi + r8*4], edx               ; Bas

.l2_next:
    inc ebx
    jmp .layer2

.done:
    add rsp, 40
    pop rbp
    pop rsi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret