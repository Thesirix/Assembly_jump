BITS 64
DEFAULT REL

global input_update

extern GetAsyncKeyState
extern player_x

%define VK_LEFT   0x25
%define VK_RIGHT  0x27
%define SCREEN_W  800
%define PLAYER_W  24
%define SPEED_X   6

section .text

input_update:
    sub rsp, 40

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

    ; wrap quand completement sorti de l'ecran
    mov edx, eax
    add edx, PLAYER_W
    cmp edx, 0
    jle .wrap_to_right
    cmp eax, SCREEN_W
    jge .wrap_to_left
    jmp .done

.wrap_to_right:
    mov dword [rel player_x], SCREEN_W
    jmp .done

.wrap_to_left:
    mov dword [rel player_x], -PLAYER_W

.done:
    add rsp, 40
    ret
