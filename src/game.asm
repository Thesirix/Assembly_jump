BITS 64
DEFAULT REL

global game_init
global game_update

extern physics_update
extern input_update
extern platforms_init
extern platforms_update
extern platforms_render
extern platforms_check_collision

section .text

game_init:
    call platforms_init
    ret
game_update:
    ; 1) Lecture clavier
    call input_update

    ; 2) Physique verticale
    call physics_update
    call platforms_update

    ret
