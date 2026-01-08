BITS 64
DEFAULT REL

global game_init
global game_update

extern physics_init
extern physics_update

section .text

game_init:
    call physics_init
    ret

game_update:
    call physics_update
    ret
