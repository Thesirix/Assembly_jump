BITS 64
DEFAULT REL

global particles_update
global particles_render

extern part_x
extern part_y
extern part_vx
extern part_vy
extern part_life
extern part_color
extern part_grav_tick
extern backbuffer

%define SCREEN_W      800
%define SCREEN_H      600
%define MAX_PARTICLES 512

section .text

; --- update SIMD 4-wide ---
particles_update:
    push rbx
    push r12

    ; gravite une frame sur 3, calcule une seule fois pour les 512 particules
    inc dword [rel part_grav_tick]
    mov eax, [rel part_grav_tick]
    xor edx, edx
    mov ecx, 3
    div ecx
    xor ecx, ecx
    test edx, edx
    setz cl
    movd xmm5, ecx
    pshufd xmm5, xmm5, 0

    pcmpeqb xmm7, xmm7
    psrlw   xmm7, 15
    packuswb xmm7, xmm7

    lea r8,  [rel part_x]
    lea r9,  [rel part_vx]
    lea r10, [rel part_y]
    lea r11, [rel part_vy]
    lea rbx, [rel part_life]
    xor r12d, r12d

.loop4:
    cmp r12d, MAX_PARTICLES
    jge .done

    movd xmm6, dword [rbx + r12]
    psubusb xmm6, xmm7            
    movd dword [rbx + r12], xmm6

    movdqu xmm0, [r8  + r12*4]
    movdqu xmm1, [r9  + r12*4]
    paddd  xmm0, xmm1              
    movdqu [r8  + r12*4], xmm0

    movdqu xmm2, [r10 + r12*4]
    movdqu xmm3, [r11 + r12*4]
    paddd  xmm2, xmm3             
    movdqu [r10 + r12*4], xmm2

    paddd  xmm3, xmm5              
    movdqu [r11 + r12*4], xmm3

    add r12d, 4
    jmp .loop4

.done:
    pop r12
    pop rbx
    ret


; --- render sans division ---

particles_render:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    lea rbp, [rel backbuffer]
    xor r12d, r12d

.loop:
    cmp r12d, MAX_PARTICLES
    jge .done

    lea rbx, [rel part_life]
    movzx eax, byte [rbx + r12]
    test eax, eax
    jz .next

    lea rbx, [rel part_x]
    mov r13d, [rbx + r12*4]
    lea rbx, [rel part_y]
    mov r14d, [rbx + r12*4]

    cmp r13d, 0
    jl .next
    cmp r13d, SCREEN_W - 3
    jge .next
    cmp r14d, 0
    jl .next
    cmp r14d, SCREEN_H - 3
    jge .next

    lea rbx, [rel part_color]
    mov r15d, [rbx + r12*4]

    lea rbx, [rel part_life]
    movzx eax, byte [rbx + r12]
    imul eax, 17
    shr eax, 2                     
    mov ebx, eax

    mov eax, r15d
    and eax, 0xFF
    imul eax, ebx
    shr eax, 8
    mov esi, eax                    ; R

    mov eax, r15d
    shr eax, 8
    and eax, 0xFF
    imul eax, ebx
    shr eax, 8
    shl eax, 8
    or esi, eax                     ; G

    mov eax, r15d
    shr eax, 16
    and eax, 0xFF
    imul eax, ebx
    shr eax, 8
    shl eax, 16
    or esi, eax                     ; B

    mov eax, r14d
    imul eax, SCREEN_W
    add eax, r13d

    lea rbx, [rel part_life]
    movzx ecx, byte [rbx + r12]
    cmp ecx, 40
    jg .size_3x3
    cmp ecx, 20
    jg .size_2x2

.size_1x1:
    mov [rbp + rax*4], esi
    jmp .next

.size_2x2:
    mov [rbp + rax*4    ], esi
    mov [rbp + rax*4 + 4], esi
    lea edx, [eax + SCREEN_W]
    mov [rbp + rdx*4    ], esi
    mov [rbp + rdx*4 + 4], esi
    jmp .next

.size_3x3:
    mov [rbp + rax*4       ], esi
    mov [rbp + rax*4 + 4   ], esi
    mov [rbp + rax*4 + 8   ], esi
    lea edx, [eax + SCREEN_W]
    mov [rbp + rdx*4       ], esi
    mov [rbp + rdx*4 + 4   ], esi
    mov [rbp + rdx*4 + 8   ], esi
    lea edx, [eax + SCREEN_W*2]
    mov [rbp + rdx*4       ], esi
    mov [rbp + rdx*4 + 4   ], esi
    mov [rbp + rdx*4 + 8   ], esi

.next:
    inc r12d
    jmp .loop

.done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
