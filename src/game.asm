BITS 64
DEFAULT REL

global game_init
global game_update

extern physics_init
extern physics_update
extern input_update
extern platforms_init
extern platforms_update
extern scroll_init
extern scroll_update
extern score_init
extern score_update
extern player_y
extern player_x

section .text

game_init:
    ; Remise à zéro totale
    mov dword [rel player_x], 380
    mov dword [rel player_y], 500  ; On commence un peu plus bas pour être sûr de toucher le sol
    
    call physics_init
    call scroll_init    ; CRITIQUE : Reset Camera_Y à 0
    call platforms_init
    call score_init
    ret

game_update:
    call input_update
    call physics_update
    call platforms_update
    call scroll_update
    call score_update
    ret