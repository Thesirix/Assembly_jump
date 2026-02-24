BITS 64
DEFAULT REL

global scroll_init
global scroll_update
global scroll_get_offset

extern player_y

%define SCREEN_H         600
%define SCROLL_THRESHOLD 200

section .bss
global camera_y
camera_y resd 1

section .text

scroll_init:
    mov dword [rel camera_y], 0
    ret

scroll_update:
    mov eax, [rel player_y]
    cmp eax, SCROLL_THRESHOLD
    jge .done

    ; joueur trop haut : compenser en poussant tout vers le bas
    mov edx, SCROLL_THRESHOLD
    sub edx, eax
    add [rel player_y], edx
    sub [rel camera_y], edx

.done:
    ret

scroll_get_offset:
    mov eax, [rel camera_y]
    ret
