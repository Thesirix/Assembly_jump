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
; --- Constantes FPU flottantes ---
gravity     dd 0.5              ; Gravité douce (float 32-bit)
jump_force  dd -12.0            ; Force de saut (float 32-bit)
floor_y_f   dd 520.0            ; Sol de départ en float
max_fall    dd 600.0            ; Seuil de mort (bas de l'écran)
zero_f      dd 0.0              ; Constante zéro

section .bss
vel_y       resd 1              ; Vélocité Y (float 32-bit, dd 0.0)
game_over   resd 1              ; Flag game over (entier)
temp_y      resd 1              ; Temporaire pour conversion float → int

section .text

; ============================================================
; physics_init — Remise à zéro de la physique
; ============================================================
physics_init:
    ; vel_y = 0.0f
    mov eax, [rel zero_f]
    mov [rel vel_y], eax
    ; game_over = 0
    mov dword [rel game_over], 0
    ret

; ============================================================
; physics_update — Physique parabolique FPU x87
; Utilise la FPU x87 pour vel_y (float) et player_y (entier)
; vel_y += gravity        (flottant)
; player_y += (int)vel_y  (conversion float → entier)
; ============================================================
physics_update:
    sub rsp, 40

    ; Si game over, on ne calcule plus la physique
    mov eax, [rel game_over]
    cmp eax, 0
    jne .already_over

    ; --- FPU : vel_y += gravity ---
    ; Charger vel_y sur la pile FPU (st0 = vel_y)
    fld dword [rel vel_y]
    ; Ajouter gravity (st0 = vel_y + gravity)
    fadd dword [rel gravity]
    ; Stocker le résultat dans vel_y (pile FPU vidée)
    fstp dword [rel vel_y]

    ; --- FPU : convertir vel_y en entier et l'ajouter à player_y ---
    ; Charger vel_y (st0 = vel_y, float)
    fld dword [rel vel_y]
    ; Convertir float → entier arrondi et stocker dans temp_y
    fistp dword [rel temp_y]
    ; player_y += temp_y (entier)
    mov eax, [rel player_y]
    add eax, [rel temp_y]
    mov [rel player_y], eax

    ; --- Vérifier mort (chute sous l'écran) ---
    ; Charger player_y comme entier, comparer à SCREEN_H
    mov eax, [rel player_y]
    cmp eax, SCREEN_H
    jle .check_floor

    ; --- GAME OVER : le joueur est tombé ---
    mov dword [rel game_over], 1
    add rsp, 40
    ret

.check_floor:
    ; Au tout début (camera_y = 0), sol invisible pour ne pas mourir direct
    mov eax, [rel camera_y]
    cmp eax, 0
    jne .done               ; Si on a commencé à scroller, plus de sol

    ; --- FPU : comparer player_y avec floor_y (520) ---
    ; Charger player_y comme entier sur la pile FPU
    fild dword [rel player_y]
    ; Charger floor_y en float
    fld dword [rel floor_y_f]
    ; Comparer : st0 = floor_y, st1 = player_y
    fcomip st0, st1
    ; Libérer st0 restant (player_y)
    fstp st0
    ; Si floor_y >= player_y (joueur au-dessus du sol), pas de rebond
    jae .done

    ; --- Rebond sur le sol de départ ---
    ; player_y = 520 (sol)
    mov dword [rel player_y], 520
    ; vel_y = jump_force (-12.0f)
    mov eax, [rel jump_force]
    mov [rel vel_y], eax

    ; JOUER SON "BOUING" (post to audio thread)
    mov ecx, CMD_PLAY_JUMP
    call audio_post_cmd

.done:
    add rsp, 40
    ret

.already_over:
    add rsp, 40
    ret
