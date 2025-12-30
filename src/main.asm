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
extern InvalidateRect
extern Sleep

extern BeginPaint
extern EndPaint
extern StretchDIBits

global _start


%define CS_HREDRAW           0x0002
%define CS_VREDRAW           0x0001
%define IDC_ARROW            32512
%define SW_SHOW              5
%define WS_OVERLAPPEDWINDOW  0x00CF0000
%define CW_USEDEFAULT        0x80000000

%define WM_DESTROY           0x0002
%define WM_PAINT             0x000F
%define WM_QUIT              0x0012

%define PM_REMOVE            0x0001

%define SRCCOPY              0x00CC0020
%define DIB_RGB_COLORS       0

%define SCREEN_W 800
%define SCREEN_H 600


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


section .bss
align 16
wcx resb 80
msg resb 48
ps  resb 72

backbuffer resd SCREEN_W*SCREEN_H

player_x resd 1
player_y resd 1

section .text

clear_backbuffer:
    lea rdi, [rel backbuffer]
    mov rcx, SCREEN_W*SCREEN_H
    xor eax, eax
    rep stosd
    ret

draw_player_rect:

    lea rsi, [rel backbuffer]

    mov r12d, [rel player_x]
    mov r13d, [rel player_y]

    mov r14d, 24
.y_loop:
    mov r15d, 24
.x_loop:

    mov eax, r13d
    mov edx, 24
    sub edx, r14d
    add eax, edx
    imul eax, SCREEN_W

    mov edx, r12d
    mov ecx, 24
    sub ecx, r15d
    add edx, ecx
    add eax, edx

    mov edx, 0x00FFFFFF
    mov [rsi + rax*4], edx

    dec r15d
    jnz .x_loop
    dec r14d
    jnz .y_loop
    ret


WndProc:
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


    mov dword [rel player_x], 380
    mov dword [rel player_y], 260

  
    call clear_backbuffer
    call draw_player_rect


    lea rbx, [rel wcx]
    mov dword [rbx+0], 80
    mov dword [rbx+4], CS_HREDRAW | CS_VREDRAW
    lea rax, [rel WndProc]
    mov qword [rbx+8], rax
    mov dword [rbx+16], 0
    mov dword [rbx+20], 0
    mov qword [rbx+24], r12
    mov qword [rbx+32], 0
    mov qword [rbx+40], r13
    mov qword [rbx+48], 0
    mov qword [rbx+56], 0
    lea rax, [rel class_name]
    mov qword [rbx+64], rax
    mov qword [rbx+72], 0

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
    mov qword [rsp+64], 0
    mov qword [rsp+72], 0
    mov qword [rsp+80], r12
    mov qword [rsp+88], 0

    call CreateWindowExA
    mov r14, rax               

    mov rcx, r14
    mov edx, SW_SHOW
    call ShowWindow

    mov rcx, r14
    call UpdateWindow


game_loop:

.pump:
    lea rcx, [rel msg]
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    sub rsp, 40
    mov dword [rsp+32], PM_REMOVE
    call PeekMessageA
    add rsp, 40
    test eax, eax
    jz .no_msg


    cmp dword [rel msg+8], WM_QUIT
    je .quit

    lea rcx, [rel msg]
    call TranslateMessage
    lea rcx, [rel msg]
    call DispatchMessageA
    jmp .pump

.no_msg:

    call clear_backbuffer
    call draw_player_rect

 
    mov rcx, r14
    xor edx, edx
    xor r8d, r8d
    call InvalidateRect


    mov ecx, 16
    call Sleep
    jmp game_loop

.quit:
    add rsp, 40
    xor ecx, ecx
    call ExitProcess
