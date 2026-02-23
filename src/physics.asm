BITS 64
DEFAULT REL

global physics_init
global physics_update
global game_over
global vel_y

extern player_y
extern player_x
extern camera_y

; Import du son (via thread ring buffer)
extern audio_post_cmd
%define CMD_PLAY_JUMP 1

%define SCREEN_H 600

section .data
; --- Constantes FPU double précision 64-bit (dq) ---
; Passage de float32 (dd) à double64 (dq) :
; précision interne FPU x87 = 80-bit, charge + stocke en 64-bit
gravity     dq 0.5              ; Gravité — double précision 64-bit
jump_force  dq -12.0            ; Force de saut — double précision 64-bit
floor_y_f   dq 520.0            ; Sol de départ — double précision 64-bit
max_fall    dq 600.0            ; Seuil de mort — double précision 64-bit
zero_f      dq 0.0              ; Constante zéro — double précision 64-bit

section .bss
; vel_y = double 64-bit (resq) — compatible avec platforms.asm via mov rax
vel_y       resq 1              ; Vélocité Y — double précision 64-bit (8 octets)
game_over   resd 1              ; Flag game over (entier 32-bit)
temp_y      resd 1              ; Temporaire entier pour fistp (player_y reste int32)

section .text

; ============================================================
; physics_init — Remise à zéro de la physique
; ============================================================
physics_init:
    ; vel_y = 0.0 (double64 : 8 octets à zéro)
    mov rax, [rel zero_f]       ; charger les 64 bits de 0.0
    mov [rel vel_y], rax        ; stocker 8 octets
    ; game_over = 0
    mov dword [rel game_over], 0
    ret

; ============================================================
; physics_update — Physique parabolique FPU x87 double précision
;
; ARCHITECTURE :
;   vel_y = double64 (resq), gravity = double64 (dq)
;   FPU x87 : registres internes 80-bit extended precision
;   fld qword → charge 64-bit en 80-bit interne
;   fstp qword → stocke 80-bit → 64-bit (arrondi double)
;
;   vel_y += gravity        (double64 → accumulation précise)
;   player_y += (int)vel_y  (fistp : double → entier 32-bit)
;
; Alignement RSP :
;   0 pushes + sub 40 = 40. (8-40) mod 16 = 0 mod 16. OK
; ============================================================
physics_update:
    sub rsp, 40

    ; Si game over, ne pas calculer la physique
    mov eax, [rel game_over]
    cmp eax, 0
    jne .already_over

    ; --- FPU double précision : vel_y += gravity ---
    ; Charger vel_y 64-bit sur la pile FPU (st0 = vel_y, 80-bit interne)
    fld qword [rel vel_y]           ; st0 = vel_y (double64 → 80-bit)
    ; Ajouter gravity 64-bit (st0 = vel_y + gravity, 80-bit interne)
    fadd qword [rel gravity]        ; st0 = vel_y + 0.5 (double précision)
    ; Stocker le résultat en double64 (80-bit → 64-bit, pile FPU vidée)
    fstp qword [rel vel_y]          ; vel_y = résultat (double64)

    ; --- FPU : convertir vel_y double64 en entier pour player_y ---
    ; Charger vel_y 64-bit (st0 = vel_y, 80-bit interne)
    fld qword [rel vel_y]           ; st0 = vel_y (double64 → 80-bit)
    ; Convertir double → entier arrondi, stocker dans temp_y (int32)
    ; fistp dword : arrondi selon mode FPU (round-to-nearest), pile vidée
    fistp dword [rel temp_y]        ; temp_y = (int)vel_y, pile FPU = vide
    ; player_y += temp_y (entier)
    mov eax, [rel player_y]
    add eax, [rel temp_y]
    mov [rel player_y], eax

    ; --- Vérifier mort : joueur sous le bas de l'écran ---
    mov eax, [rel player_y]
    cmp eax, SCREEN_H
    jle .check_floor

    ; --- GAME OVER ---
    mov dword [rel game_over], 1
    add rsp, 40
    ret

.check_floor:
    ; Sol fixe uniquement si camera_y = 0 (début du jeu)
    mov eax, [rel camera_y]
    cmp eax, 0
    jne .done                       ; déjà scrollé → plus de sol

    ; --- FPU double64 : comparer player_y (int) avec floor_y (520.0) ---
    ; Charger player_y comme entier → FPU (st0 = (double)player_y)
    fild dword [rel player_y]       ; st0 = player_y (int → 80-bit)
    ; Charger floor_y 64-bit (st0 = floor_y_f, st1 = player_y)
    fld qword [rel floor_y_f]       ; st0 = 520.0 (double64 → 80-bit)
    ; Comparer et dépiler : fcomip compare st0 vs st1, dépile st0
    ; Résultat dans FLAGS : ZF, PF, CF
    fcomip st0, st1                 ; compare 520.0 vs player_y, dépile 520.0
    ; Libérer st0 restant (player_y)
    fstp st0                        ; pile FPU vide
    ; fcomip : CF=1 si st0 < st1, CF=0 si st0 >= st1
    ; Ici : si floor_y (520.0) >= player_y → joueur au-dessus du sol → pas de rebond
    jae .done

    ; --- Rebond sur le sol de départ ---
    ; player_y = 520
    mov dword [rel player_y], 520
    ; vel_y = jump_force (-12.0) en double64
    mov rax, [rel jump_force]       ; charger 8 octets de -12.0
    mov [rel vel_y], rax            ; stocker en double64
    ; Jouer le son de saut (via ring buffer audio thread)
    mov ecx, CMD_PLAY_JUMP
    call audio_post_cmd

.done:
    add rsp, 40
    ret

.already_over:
    add rsp, 40
    ret