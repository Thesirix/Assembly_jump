BITS 64
DEFAULT REL

global score_init
global score_update
global score_get
global score_render
global draw_number_at

extern player_y
extern backbuffer
extern camera_y  ; IMPORTANT : On a besoin de la caméra pour le calcul absolu

%define SCREEN_W 800
%define SCREEN_H 600

section .data
; Bitmap des chiffres (0-9) - 3x5 pixels
digits_bitmap:
    db 1,1,1, 1,0,1, 1,0,1, 1,0,1, 1,1,1 ; 0
    db 0,1,0, 0,1,0, 0,1,0, 0,1,0, 0,1,0 ; 1
    db 1,1,1, 0,0,1, 1,1,1, 1,0,0, 1,1,1 ; 2
    db 1,1,1, 0,0,1, 1,1,1, 0,0,1, 1,1,1 ; 3
    db 1,0,1, 1,0,1, 1,1,1, 0,0,1, 0,0,1 ; 4
    db 1,1,1, 1,0,0, 1,1,1, 0,0,1, 1,1,1 ; 5
    db 1,1,1, 1,0,0, 1,1,1, 1,0,1, 1,1,1 ; 6
    db 1,1,1, 0,0,1, 0,0,1, 0,0,1, 0,0,1 ; 7
    db 1,1,1, 1,0,1, 1,1,1, 1,0,1, 1,1,1 ; 8
    db 1,1,1, 1,0,1, 1,1,1, 0,0,1, 1,1,1 ; 9

section .bss
global current_score
current_score resd 1
highest_y resd 1
start_y   resd 1

section .text

score_init:
    mov dword [rel current_score], 0
    ; On initialise highest_y à la position de départ (ex: 500)
    mov dword [rel highest_y], 520 
    mov dword [rel start_y], 520
    ret

score_update:
    ; Score = (Start_Y - (Player_Y + Camera_Y))
    ; En gros : la distance totale parcourue vers le haut
    
    mov eax, [rel player_y]
    add eax, [rel camera_y] ; Position Y absolue dans le monde
    
    mov edx, [rel highest_y]
    
    ; Comme Y va vers le bas, monter signifie Y diminue.
    ; Si (Player+Cam) < Highest, on a monté.
    cmp eax, edx
    jge .done
    
    ; Nouveau record de hauteur
    mov [rel highest_y], eax
    
    ; Calcul du score : (Start - Current_Highest)
    mov ecx, [rel start_y]
    sub ecx, eax
    
    ; On divise par 5 pour avoir un score plus "joli" (pas trop grand)
    xor edx, edx
    mov eax, ecx
    mov ecx, 5
    div ecx
    
    mov [rel current_score], eax
    
.done:
    ret

score_get:
    mov eax, [rel current_score]
    ret

; ==========================================
; Dessin des nombres (inchangé sauf couleur)
; ==========================================
draw_number_at:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40

    mov r14d, r8d  ; X
    mov r15d, r9d  ; Y

    mov eax, ecx
    mov rbx, 10
    xor ecx, ecx   ; Compteur chiffres

    ; Cas spécial : Si score est 0
    test eax, eax
    jnz .div_loop
    push 0
    inc ecx
    jmp .draw_stack_loop

.div_loop:
    xor edx, edx
    div rbx
    push rdx
    inc ecx
    test eax, eax
    jnz .div_loop

.draw_stack_loop:
    pop rax
    call draw_single_digit
    add r14d, 15   ; Espacement plus large (15px)
    dec ecx
    jnz .draw_stack_loop

    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

draw_single_digit:
    push rcx
    push rdx
    
    imul eax, 15
    lea rsi, [rel digits_bitmap]
    add rsi, rax
    
    xor ecx, ecx 
.line_loop:
    xor edx, edx
.col_loop:
    lodsb 
    cmp al, 0
    je .skip_draw
    
    push r8
    push r9
    
    ; X pixel
    mov r8d, r14d
    lea eax, [edx*4]
    add r8d, eax
    
    ; Y pixel
    mov r9d, r15d
    lea eax, [ecx*4]
    add r9d, eax
    
    call draw_fat_pixel
    pop r9
    pop r8
    
.skip_draw:
    inc edx
    cmp edx, 3
    jl .col_loop
    inc ecx
    cmp ecx, 5
    jl .line_loop
    
    pop rdx
    pop rcx
    ret

draw_fat_pixel:
    push rdi
    push rax
    lea rdi, [rel backbuffer]
    mov r10d, 0
.dy:
    mov r11d, 0
.dx:
    mov eax, r9d
    add eax, r10d
    imul eax, SCREEN_W
    add eax, r8d
    add eax, r11d
    
    cmp eax, 0
    jl .skip
    cmp eax, SCREEN_W*SCREEN_H
    jge .skip
    
    ; COULEUR DU SCORE : JAUNE DORE (0x00D7FF) ou BLANC (0xFFFFFF)
    mov dword [rdi + rax*4], 0x0000D7FF 

.skip:
    inc r11d
    cmp r11d, 4
    jl .dx
    inc r10d
    cmp r10d, 4
    jl .dy
    pop rax
    pop rdi
    ret
score_render:
    mov ecx, [rel current_score]
    mov r8d, 10
    mov r9d, 10
    call draw_number_at
    ret