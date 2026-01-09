BITS 64
DEFAULT REL

global platforms_init
global platforms_update
global platforms_render
global platforms_check_collision

extern backbuffer
extern player_x
extern player_y
extern vel_y

%define SCREEN_W 800
%define SCREEN_H 600
%define PLAYER_W 24
%define PLAYER_H 24
%define PLATFORM_W 80
%define PLATFORM_H 12
%define MAX_PLATFORMS 6

section .data
platforms_x dd 100, 300, 520, 200, 420, 150
platforms_y dd 520, 450, 380, 300, 220, 140

section .text

platforms_init:
    ret

platforms_update:
    call platforms_check_collision
    ret

; -------------------------------
; Collision
; -------------------------------
platforms_check_collision:
    lea rbx, [rel platforms_x]
    lea rdi, [rel platforms_y]

    mov ecx, MAX_PLATFORMS
    xor rsi, rsi

.loop:
    mov eax, [rbx + rsi*4]
    mov edx, [rdi + rsi*4]

    mov r8d, [rel player_x]
    mov r9d, [rel player_y]

    cmp r8d, eax
    jl .next
    mov r10d, eax
    add r10d, PLATFORM_W
    cmp r8d, r10d
    jg .next

    mov r11d, r9d
    add r11d, PLAYER_H
    cmp r11d, edx
    jl .next
    add edx, PLATFORM_H
    cmp r9d, edx
    jg .next

    mov eax, [rel vel_y]
    cmp eax, 0
    jl .next

    mov eax, [rdi + rsi*4]
    sub eax, PLAYER_H
    mov [rel player_y], eax
    mov dword [rel vel_y], -18

.next:
    inc rsi
    loop .loop
    ret

; -------------------------------
; Render
; -------------------------------
platforms_render:
    lea rbx, [rel platforms_x]
    lea rdi, [rel platforms_y]
    lea rdx, [rel backbuffer]

    mov ecx, MAX_PLATFORMS
    xor rsi, rsi

.ploop:
    mov r12d, [rbx + rsi*4]
    mov r13d, [rdi + rsi*4]

    mov r14d, PLATFORM_H
.y:
    mov r15d, PLATFORM_W
.x:
    mov eax, r13d
    add eax, PLATFORM_H
    sub eax, r14d
    imul eax, SCREEN_W

    mov r8d, r12d
    add r8d, PLATFORM_W
    sub r8d, r15d
    add eax, r8d

    cmp eax, 0
    jl .skip
    cmp eax, SCREEN_W*SCREEN_H
    jge .skip

    mov dword [rdx + rax*4], 0x0000FF00

.skip:
    dec r15d
    jnz .x
    dec r14d
    jnz .y

    inc rsi
    loop .ploop
    ret
