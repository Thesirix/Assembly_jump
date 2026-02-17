BITS 64
DEFAULT REL

extern GetModuleHandleA
extern LoadCursorA
extern RegisterClassExA
extern CreateWindowExA
extern ShowWindow
extern UpdateWindow
extern PeekMessageA
extern TranslateMessage
extern DispatchMessageA
extern DefWindowProcA
extern PostQuitMessage
extern ExitProcess
extern Sleep
extern InvalidateRect
extern GetAsyncKeyState

extern BeginPaint
extern EndPaint
extern StretchDIBits

; --- AUDIO INIT SEULEMENT ---
extern audio_init
extern audio_cleanup

global _start
global backbuffer
global player_x
global player_y

extern game_init
extern game_update
extern platforms_render
extern score_render
extern game_over

; --- LE VOILA LE COUPABLE ---
extern draw_game_over 

%define SCREEN_W 800
%define SCREEN_H 600
%define CS_HREDRAW 0x0002
%define CS_VREDRAW 0x0001
%define IDC_ARROW  32512
%define SW_SHOW    5
%define WS_OVERLAPPEDWINDOW 0x00CF0000
%define CW_USEDEFAULT 0x80000000
%define WM_DESTROY 0x0002
%define WM_PAINT   0x000F
%define WM_ERASEBKGND 0x0014
%define WM_QUIT    0x0012
%define WM_LBUTTONDOWN 0x0201
%define PM_REMOVE  0x0001
%define SRCCOPY    0x00CC0020
%define DIB_RGB_COLORS 0
%define VK_SPACE   0x20
%define SPRITE_W 24
%define SPRITE_H 24

section .data
class_name   db "DoodleAsmWnd", 0
window_title db "Doodle Jump - Assembly", 0

bmi:
    dd 40
    dd SCREEN_W
    dd -SCREEN_H
    dw 1
    dw 32
    dd 0
    dd SCREEN_W*SCREEN_H*4
    dd 0
    dd 0
    dd 0
    dd 0

doodle_bitmap:
    db 0,0,0,0,0,0,0,0,2,2,2,2,2,2,2,2,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,2,2,1,1,1,1,1,1,1,1,2,2,0,0,0,0,0,0
    db 0,0,0,0,0,2,1,1,5,5,1,1,5,5,1,1,1,1,2,0,0,0,0,0
    db 0,0,0,0,2,1,1,5,5,5,1,5,5,1,1,1,1,1,1,2,0,0,0,0
    db 0,0,0,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,0,0,0
    db 0,0,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,0,0
    db 0,0,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,0,0
    db 0,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,0
    db 0,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,0
    db 0,2,1,1,1,3,3,3,1,1,1,1,1,1,3,3,3,1,1,1,1,1,2,0
    db 2,1,1,1,3,3,3,3,1,1,1,1,1,3,3,3,3,1,1,1,1,1,1,2
    db 2,1,1,1,3,3,3,3,1,1,1,1,1,3,3,3,3,1,1,1,1,1,1,2
    db 2,1,1,1,1,3,3,1,1,1,3,1,1,1,3,3,1,1,1,1,1,1,1,2
    db 2,1,1,1,4,4,4,1,1,3,1,3,1,1,4,4,4,1,1,1,1,1,1,2
    db 2,1,1,1,1,1,1,1,1,1,3,1,1,1,1,1,1,1,1,1,1,1,1,2
    db 2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2
    db 2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2
    db 2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2
    db 0,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,0
    db 0,2,1,1,1,1,1,2,1,1,1,1,1,1,2,1,1,1,1,1,1,1,2,0
    db 0,0,2,1,1,1,2,0,2,1,1,1,1,2,0,2,1,1,1,1,1,2,0,0
    db 0,0,2,1,1,1,2,0,2,1,1,1,1,2,0,0,2,1,1,1,2,0,0,0
    db 0,0,0,2,2,2,0,0,0,2,2,2,2,0,0,0,0,2,2,2,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

section .bss
align 16
msg resb 48
ps  resb 72
wcx resb 80

backbuffer resd SCREEN_W*SCREEN_H
player_x resd 1
player_y resd 1

hwnd_main resq 1

section .text

clear_backbuffer:
    lea rdi, [rel backbuffer]
    mov rcx, SCREEN_W*SCREEN_H
    mov eax, 0x0087CEEB 
    rep stosd
    ret

draw_player:
    lea rsi, [rel backbuffer]   
    lea rbx, [rel doodle_bitmap]
    mov r12d, [rel player_x]    
    mov r13d, [rel player_y]    
    xor r14d, r14d
.y_loop:
    xor r15d, r15d
.x_loop:
    mov eax, r14d
    imul eax, SPRITE_W
    add eax, r15d
    mov cl, byte [rbx + rax]
    cmp cl, 0
    je .next_pixel
    mov eax, r13d
    add eax, r14d
    cmp eax, 0
    jl .next_pixel
    cmp eax, SCREEN_H
    jge .next_pixel
    imul eax, SCREEN_W
    mov edx, r12d
    add edx, r15d
    cmp edx, 0
    jl .next_pixel
    cmp edx, SCREEN_W
    jge .next_pixel
    add eax, edx
    cmp cl, 1
    je .col_body
    cmp cl, 2
    je .col_outline
    cmp cl, 3
    je .col_eyes
    cmp cl, 4
    je .col_cheeks
    cmp cl, 5
    je .col_highlight
    jmp .next_pixel
.col_body:
    mov dword [rsi + rax*4], 0x009B9BEE 
    jmp .next_pixel
.col_outline:
    mov dword [rsi + rax*4], 0x002B2B55 
    jmp .next_pixel
.col_eyes:
    mov dword [rsi + rax*4], 0x00000000
    jmp .next_pixel
.col_cheeks:
    mov dword [rsi + rax*4], 0x00FF8888 
    jmp .next_pixel
.col_highlight:
    mov dword [rsi + rax*4], 0x00FFFFDD
    jmp .next_pixel
.next_pixel:
    inc r15d
    cmp r15d, SPRITE_W
    jl .x_loop
    inc r14d
    cmp r14d, SPRITE_H
    jl .y_loop
    ret

WndProc:
    cmp edx, WM_LBUTTONDOWN
    je .check_click
    cmp edx, WM_ERASEBKGND
    jne .check_destroy
    mov eax, 1
    ret
.check_click:
    mov eax, [rel game_over]
    cmp eax, 1
    jne .def
    mov rax, r9
    mov rbx, rax
    and rbx, 0xFFFF
    shr rax, 16
    and rax, 0xFFFF
    cmp rbx, 200
    jl .def
    cmp rbx, 600
    jg .def
    cmp rax, 250
    jl .def
    cmp rax, 450
    jg .def
    call game_init
    xor eax, eax
    ret
.check_destroy:
    cmp edx, WM_DESTROY
    jne .check_paint
    xor ecx, ecx
    call PostQuitMessage
    xor eax, eax
    ret
.check_paint:
    cmp edx, WM_PAINT
    jne .def
    sub rsp, 200
    mov r10, rcx
    mov rcx, r10
    lea rdx, [rel ps]
    call BeginPaint
    mov r11, rax
    mov rcx, r11
    xor edx, edx
    xor r8d, r8d
    mov r9d, SCREEN_W
    mov dword [rsp+32], SCREEN_H
    mov dword [rsp+40], 0
    mov dword [rsp+48], 0
    mov dword [rsp+56], SCREEN_W
    mov dword [rsp+64], SCREEN_H
    lea rax, [rel backbuffer]
    mov qword [rsp+72], rax
    lea rax, [rel bmi]
    mov qword [rsp+80], rax
    mov dword [rsp+88], DIB_RGB_COLORS
    mov dword [rsp+96], SRCCOPY
    call StretchDIBits
    mov rcx, r10
    lea rdx, [rel ps]
    call EndPaint
    add rsp, 200
    xor eax, eax
    ret
.def:
    jmp DefWindowProcA

_start:
    sub rsp, 40
    xor ecx, ecx
    call GetModuleHandleA
    mov r12, rax
    xor ecx, ecx
    mov edx, IDC_ARROW
    call LoadCursorA
    mov r13, rax
    call audio_init
    mov dword [rel player_x], 380
    mov dword [rel player_y], 100
    call game_init
    lea rbx, [rel wcx]
    mov dword [rbx+0], 80
    mov dword [rbx+4], CS_HREDRAW | CS_VREDRAW
    lea rax, [rel WndProc]
    mov qword [rbx+8], rax
    mov qword [rbx+24], r12
    mov qword [rbx+40], r13
    mov qword [rbx+48], 0
    lea rax, [rel class_name]
    mov qword [rbx+64], rax
    lea rcx, [rel wcx]
    call RegisterClassExA
    xor ecx, ecx
    lea rdx, [rel class_name]
    lea r8,  [rel window_title]
    mov r9d, WS_OVERLAPPEDWINDOW
    mov dword [rsp+32], CW_USEDEFAULT
    mov dword [rsp+40], CW_USEDEFAULT
    mov dword [rsp+48], SCREEN_W
    mov dword [rsp+56], SCREEN_H
    mov qword [rsp+80], r12
    call CreateWindowExA
    mov [rel hwnd_main], rax
    mov rcx, rax
    mov edx, SW_SHOW
    call ShowWindow
    mov rcx, [rel hwnd_main]
    call UpdateWindow

game_loop:
.msg:
    lea rcx, [rel msg]
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    sub rsp, 40
    mov dword [rsp+32], PM_REMOVE
    call PeekMessageA
    add rsp, 40
    test eax, eax
    jz .frame
    cmp dword [rel msg+8], WM_QUIT
    je .quit
    lea rcx, [rel msg]
    call TranslateMessage
    lea rcx, [rel msg]
    call DispatchMessageA
    jmp .msg
.frame:
    mov eax, [rel game_over]
    cmp eax, 1
    je .handle_gameover
    call game_update
    jmp .render
.handle_gameover:
    mov rcx, VK_SPACE
    call GetAsyncKeyState
    test ax, 0x8000
    jz .render
    call game_init
    mov ecx, 200
    call Sleep
.render:
    call clear_backbuffer
    call platforms_render
    call draw_player
    call score_render
    mov eax, [rel game_over]
    cmp eax, 1
    jne .paint
    call draw_game_over
.paint:
    mov rcx, [rel hwnd_main]
    xor edx, edx
    xor r8d, r8d
    call InvalidateRect
    mov rcx, [rel hwnd_main]
    call UpdateWindow
    mov ecx, 16
    call Sleep
    jmp game_loop
.quit:
    call audio_cleanup
    xor ecx, ecx
    call ExitProcess