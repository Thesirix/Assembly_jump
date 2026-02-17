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

; --- IMPORT AUDIO ---
extern audio_update_music
extern audio_stop_music

extern player_y
extern player_x
extern game_over

section .text

game_init:
    ; Remise à zéro totale
    mov dword [rel player_x], 380
    mov dword [rel player_y], 500
    
    call physics_init
    call scroll_init
    call platforms_init
    call score_init
    
    ; RESET MUSIQUE (Silence + Rembobinage au début)
    sub rsp, 40       ; Alignement sécu
    call audio_stop_music
    add rsp, 40
    ret

game_update:
    call input_update
    call physics_update
    
    ; --- VERIFICATION MORT ---
    ; Si physics dit "Game Over", on coupe le son et on quitte l'update
    mov eax, [rel game_over]
    cmp eax, 1
    je .stop_sound
    
    call platforms_update
    call scroll_update
    call score_update
    
    ; --- MUSIQUE (Jeu en cours) ---
    sub rsp, 40       ; Alignement sécu
    call audio_update_music
    add rsp, 40
    ret

.stop_sound:
    ; Le jeu vient de finir, on coupe la note coincée
    sub rsp, 40
    call audio_stop_music
    add rsp, 40
    ret