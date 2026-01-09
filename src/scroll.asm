BITS 64
DEFAULT REL

global scroll_init
global scroll_update
global scroll_get_offset

extern player_y

%define SCREEN_H 600
%define SCROLL_THRESHOLD 200  ; Quand le joueur atteint Y=200, on scroll

section .bss
global camera_y
camera_y resd 1           ; Position Y de la caméra (offset de scroll)

section .text

; =============================
; Initialisation du scroll
; =============================
scroll_init:
    mov dword [rel camera_y], 0
    ret

; =============================
; Mise à jour du scroll
; =============================
scroll_update:
    ; Si le joueur monte au-dessus du seuil, faire descendre la caméra
    mov eax, [rel player_y]
    cmp eax, SCROLL_THRESHOLD
    jge .done
    
    ; Le joueur est trop haut, on doit scroller
    ; On calcule de combien scroller
    mov edx, SCROLL_THRESHOLD
    sub edx, eax              ; distance = THRESHOLD - player_y
    
    ; Ajuster player_y vers le bas
    mov eax, [rel player_y]
    add eax, edx
    mov [rel player_y], eax
    
    ; Ajuster camera_y (pour le score et les plateformes)
    mov eax, [rel camera_y]
    sub eax, edx              ; camera monte (Y diminue)
    mov [rel camera_y], eax
    
.done:
    ret

; =============================
; Obtenir l'offset de scroll (retour dans EAX)
; =============================
scroll_get_offset:
    mov eax, [rel camera_y]
    ret