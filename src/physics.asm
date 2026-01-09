BITS 64
DEFAULT REL

global physics_init
global physics_update
global game_over
global vel_y

extern player_y
extern player_x
extern camera_y

section .data
gravity    dd 1
jump_force dd -18
floor_y    dd 520

section .bss
vel_y resd 1
game_over resd 1

section .text

physics_init:
    mov dword [rel vel_y], 0
    mov dword [rel game_over], 0
    ret

physics_update:
    ; Si game over, on ne calcule plus la physique
    mov eax, [rel game_over]
    cmp eax, 0
    jne .already_over
    
    ; Gravité
    mov eax, [rel vel_y]
    add eax, [rel gravity]
    mov [rel vel_y], eax

    ; Mouvement Y
    mov eax, [rel player_y]
    add eax, [rel vel_y]
    mov [rel player_y], eax

    ; Vérifier mort (chute)
    mov eax, [rel player_y]
    
    ; Si on tombe tout en bas de l'écran (quel que soit le scroll)
    ; On considère mort si player_y > 600 (hauteur écran)
    ; ATTENTION: player_y est en coordonnées écran grâce au scroll.asm
    cmp eax, 600
    jle .check_floor
    
    ; --- GAME OVER ---
    mov dword [rel game_over], 1
    ret ; On retourne simplement, le Main gère l'affichage

.check_floor:
    ; Au tout début (camera_y = 0), on a un sol invisible pour ne pas mourir direct
    mov eax, [rel camera_y]
    cmp eax, 0
    jne .done ; Si on a commencé à scroller, plus de sol de sécurité
    
    mov eax, [rel player_y]
    cmp eax, [rel floor_y]
    jl .done

    ; Rebond sur le sol de départ
    mov eax, [rel floor_y]
    mov [rel player_y], eax
    mov eax, [rel jump_force]
    mov [rel vel_y], eax

.done:
    ret

.already_over:
    ret