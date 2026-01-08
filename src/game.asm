BITS 64
DEFAULT REL

global game_init
global game_update

extern physics_update
extern input_update

section .text

game_init:
    ret

game_update:
    ; 1) Lecture clavier
    call input_update

    ; 2) Physique verticale
    call physics_update

    ret
