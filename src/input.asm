BITS 64
DEFAULT REL

global input_update

extern GetAsyncKeyState
extern player_x

%define VK_LEFT   0x25
%define VK_RIGHT  0x27

%define SCREEN_W 800
%define PLAYER_W 24
%define SPEED_X  6

section .text

input_update:
    ; Win64 ABI shadow space
    sub rsp, 40

    ; --- LEFT ---
    mov ecx, VK_LEFT
    call GetAsyncKeyState
    test ax, 0x8000
    jz .check_right

    mov eax, [rel player_x]
    sub eax, SPEED_X
    mov [rel player_x], eax

.check_right:
    mov ecx, VK_RIGHT
    call GetAsyncKeyState
    test ax, 0x8000
    jz .wrap_check

    mov eax, [rel player_x]
    add eax, SPEED_X
    mov [rel player_x], eax

.wrap_check:
    mov eax, [rel player_x]

    ; ---- WRAP CORRIGÉ ----
    ; Le joueur wrap seulement quand il est COMPLÈTEMENT disparu
    
    ; Si player_x + PLAYER_W <= 0 (complètement sorti à gauche)
    ; alors téléporter à droite
    mov edx, eax
    add edx, PLAYER_W
    cmp edx, 0
    jle .wrap_to_right
    
    ; Si player_x >= SCREEN_W (complètement sorti à droite)
    ; alors téléporter à gauche
    cmp eax, SCREEN_W
    jge .wrap_to_left
    
    jmp .done

.wrap_to_right:
    ; Apparaît du côté droit (juste hors écran)
    mov eax, SCREEN_W
    mov [rel player_x], eax
    jmp .done

.wrap_to_left:
    ; Apparaît du côté gauche (juste hors écran)
    mov eax, -PLAYER_W
    mov [rel player_x], eax

.done:
    add rsp, 40
    ret