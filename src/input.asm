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

    ; ---- WRAP UNIQUE ET ATOMIQUE ----
    cmp eax, -PLAYER_W
    jl .wrap_left

    cmp eax, SCREEN_W
    jg .wrap_right

    jmp .done

.wrap_left:
    mov eax, SCREEN_W
    mov [rel player_x], eax
    jmp .done

.wrap_right:
    mov eax, -PLAYER_W
    mov [rel player_x], eax

.done:
    add rsp, 40
    ret
