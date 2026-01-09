BITS 64
DEFAULT REL

; =========================
; Imports Windows
; =========================
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

global _start

; =========================
; Imports Jeu
; =========================
extern game_init
extern game_update
extern platforms_render
extern score_render
extern game_over
extern draw_number_at
extern current_score

; NOTE : On NE met PAS 'extern player_x' ici car c'est CE fichier qui les possède.

; =========================
; Constantes
; =========================
%define CS_HREDRAW           0x0002
%define CS_VREDRAW           0x0001
%define IDC_ARROW            32512
%define SW_SHOW              5
%define WS_OVERLAPPEDWINDOW  0x00CF0000
%define CW_USEDEFAULT        0x80000000
%define WM_DESTROY           0x0002
%define WM_PAINT             0x000F
%define WM_ERASEBKGND        0x0014
%define WM_QUIT              0x0012
%define WM_LBUTTONDOWN       0x0201

%define PM_REMOVE            0x0001
%define SRCCOPY              0x00CC0020
%define DIB_RGB_COLORS       0

%define SCREEN_W 800
%define SCREEN_H 600
%define VK_SPACE             0x20

; =========================
; Données
; =========================
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

; =========================
; BSS (Mémoire vive)
; =========================
section .bss
align 16
msg resb 48
ps  resb 72
wcx resb 80

global backbuffer
backbuffer resd SCREEN_W*SCREEN_H

; --- C'EST ICI QUE LES VARIABLES SONT CRÉÉES ---
global player_x    ; On rend la variable visible pour les autres fichiers
global player_y    ; Idem
player_x resd 1    ; On réserve la mémoire
player_y resd 1    ; On réserve la mémoire

hwnd_main resq 1

; =========================
; Code
; =========================
section .text

clear_backbuffer:
    lea rdi, [rel backbuffer]
    mov rcx, SCREEN_W*SCREEN_H
    mov eax, 0x0087CEEB ; Bleu ciel
    rep stosd
    ret

draw_player:
    lea rsi, [rel backbuffer]
    mov r12d, [rel player_x]
    mov r13d, [rel player_y]

    mov r14d, 24
.y:
    mov r15d, 24
.x:
    mov eax, r13d
    add eax, 24
    sub eax, r14d
    
    ; Clipping Y
    cmp eax, 0
    jl .skip_pixel
    cmp eax, SCREEN_H
    jge .skip_pixel
    
    imul eax, SCREEN_W

    mov edx, r12d
    add edx, 24
    sub edx, r15d
    
    ; Clipping X
    cmp edx, 0
    jl .skip_pixel
    cmp edx, SCREEN_W
    jge .skip_pixel
    
    add eax, edx
    mov dword [rsi + rax*4], 0x00FF0000 ; Rouge

.skip_pixel:
    dec r15d
    jnz .x
    dec r14d
    jnz .y
    ret

; =========================
; DESSIN GAME OVER
; =========================
draw_game_over:
    lea rsi, [rel backbuffer]
    
    ; 1. Fond gris
    mov r12d, 150
.y_rect:
    mov r13d, 200
.x_rect:
    mov eax, r12d
    imul eax, SCREEN_W
    add eax, r13d
    mov dword [rsi + rax*4], 0x00333333 ; Gris foncé
    inc r13d
    cmp r13d, 600
    jl .x_rect
    inc r12d
    cmp r12d, 450
    jl .y_rect
    
    ; 2. Score Final (Jaune/Or)
    mov ecx, [rel current_score]
    mov r8d, 350
    mov r9d, 200
    call draw_number_at
    
    ; 3. Bouton RESTART (Vert)
    mov r12d, 300
.btn_y:
    mov r13d, 300
.btn_x:
    mov eax, r12d
    imul eax, SCREEN_W
    add eax, r13d
    mov dword [rsi + rax*4], 0x0000AA00 ; Vert
    inc r13d
    cmp r13d, 500
    jl .btn_x
    inc r12d
    cmp r12d, 360
    jl .btn_y

    ; 4. Carré blanc "PLAY"
    mov r12d, 315
.play_y:
    mov r13d, 380
.play_x:
    mov eax, r12d
    imul eax, SCREEN_W
    add eax, r13d
    mov dword [rsi + rax*4], 0x00FFFFFF ; Blanc
    inc r13d
    cmp r13d, 420
    jl .play_x
    inc r12d
    cmp r12d, 345
    jl .play_y
    ret

; =========================
; WndProc
; =========================
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
    
    ; Récupération coordonnées souris (lParam dans R9 pour x64 WndProc convention)
    mov rax, r9
    
    mov rbx, rax
    and rbx, 0xFFFF ; X
    shr rax, 16
    and rax, 0xFFFF ; Y
    
    ; Check Zone Bouton (300-500, 300-360)
    cmp rbx, 300
    jl .def
    cmp rbx, 500
    jg .def
    cmp rax, 300
    jl .def
    cmp rax, 360
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

; =========================
; Entry Point
; =========================
_start:
    sub rsp, 40

    xor ecx, ecx
    call GetModuleHandleA
    mov r12, rax

    xor ecx, ecx
    mov edx, IDC_ARROW
    call LoadCursorA
    mov r13, rax

    ; Initialisation
    mov dword [rel player_x], 380
    mov dword [rel player_y], 100

    call game_init

    ; Register Class
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

    ; Create Window
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

; =========================
; Game Loop
; =========================
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
    ; Backup touche Espace
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
    xor ecx, ecx
    call ExitProcess