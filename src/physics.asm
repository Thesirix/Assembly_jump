BITS 64
DEFAULT REL

global physics_init
global physics_update

extern player_y
extern player_x

section .data
gravity    dd 1        ; force vers le bas
jump_force dd -18      ; impulsion de saut
floor_y    dd 520      ; sol fictif (bas écran)

section .bss
vel_y resd 1           ; vitesse verticale

section .text

physics_init:
    mov dword [rel vel_y], 0
    ret

physics_update:
    ; vel_y += gravity
    mov eax, [rel vel_y]
    add eax, [rel gravity]
    mov [rel vel_y], eax

    ; player_y += vel_y
    mov eax, [rel player_y]
    add eax, [rel vel_y]
    mov [rel player_y], eax

    ; si on touche le sol → saut automatique
    mov eax, [rel player_y]
    cmp eax, [rel floor_y]
    jl .done

    mov eax, [rel floor_y]
    mov [rel player_y], eax

    mov eax, [rel jump_force]
    mov [rel vel_y], eax

.done:
    ret
