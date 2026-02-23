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
; --- Constantes SSE2 double précision 64-bit (dq) ---
; movsd charge/stocke directement en 64-bit dans registres XMM
gravity     dq 0.5              ; Gravité — double précision 64-bit
jump_force  dq -12.0            ; Force de saut — double précision 64-bit
floor_y_f   dq 520.0            ; Sol de départ — double précision 64-bit
max_fall    dq 600.0            ; Seuil de mort — double précision 64-bit
zero_f      dq 0.0              ; Constante zéro — double précision 64-bit

section .bss
; vel_y = double 64-bit (resq) — compatible avec platforms.asm via mov rax
vel_y       resq 1              ; Vélocité Y — double précision 64-bit (8 octets)
game_over   resd 1              ; Flag game over (entier 32-bit)

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
; physics_update — Physique parabolique SSE2 scalaire double
;
; ARCHITECTURE :
;   vel_y = double64 (resq), gravity = double64 (dq)
;   SSE2 scalaire : registres XMM (xmm0..xmm15), 64-bit double
;   movsd / addsd / cvttsd2si / ucomisd
;   Conforme ABI Win64 moderne (zéro x87)
;
;   vel_y += gravity        (addsd      — double scalaire SSE2)
;   player_y += (int)vel_y  (cvttsd2si  — double -> int32)
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

    ; --- SSE2 scalaire : vel_y += gravity ---
    movsd xmm0, [rel vel_y]         ; xmm0 = vel_y (double64)
    addsd xmm0, [rel gravity]       ; xmm0 = vel_y + gravity
    movsd [rel vel_y], xmm0         ; vel_y = résultat (double64)

    ; --- SSE2 : convertir vel_y double64 en entier pour player_y ---
    ; cvttsd2si : troncature double64 -> int32 (remplace fistp)
    cvttsd2si eax, xmm0             ; eax = (int)vel_y (troncature)
    add eax, [rel player_y]
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

    ; --- SSE2 scalaire : comparer player_y (int) avec floor_y (520.0) ---
    mov eax, [rel player_y]
    cvtsi2sd xmm0, eax              ; xmm0 = (double)player_y
    movsd xmm1, [rel floor_y_f]     ; xmm1 = 520.0
    ; ucomisd : CF=1 si xmm1 < xmm0, ZF=1 si égaux
    ; jae .done : CF=0 && ZF=0 → 520.0 >= player_y → joueur au-dessus → pas de rebond
    ucomisd xmm1, xmm0              ; compare 520.0 vs player_y
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