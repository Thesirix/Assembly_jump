BITS 64
DEFAULT REL

global platforms_init
global platforms_update
global platforms_render
global platforms_check_collision
global random
global highest_platform_y
global highest_platform_x
global rand_seed

extern backbuffer
extern player_x
extern player_y
extern vel_y
extern camera_y

; Import du son (via thread ring buffer)
extern audio_post_cmd
%define CMD_PLAY_JUMP 1

; Import du platform pool (thread.asm)
extern platpool_consume
extern platpool_request

%define SCREEN_W 800
%define SCREEN_H 600
%define PLAYER_W 24
%define PLAYER_H 24
%define PLATFORM_W 80
%define PLATFORM_H 12
%define MAX_PLATFORMS 32 

section .data
rand_seed dd 12345

section .bss
platforms_x resd MAX_PLATFORMS
platforms_y resd MAX_PLATFORMS
platforms_active resb MAX_PLATFORMS
highest_platform_y resd 1
highest_platform_x resd 1

section .text

; Générateur aléatoire
random:
    push rbx
    mov eax, [rel rand_seed]
    mov ebx, 1103515245
    imul eax, ebx
    add eax, 12345
    mov [rel rand_seed], eax
    shr eax, 16
    and eax, 0x7FFF
    pop rbx
    ret

; Initialisation
platforms_init:
    push rbx
    push r12
    push r13
    sub rsp, 32  ; Correction de l'alignement de la pile
    
    rdtsc
    mov [rel rand_seed], eax
    
    ; Reset
    xor r12d, r12d
    lea rbx, [rel platforms_active]
.clear_loop:
    mov byte [rbx + r12], 0
    inc r12d
    cmp r12d, MAX_PLATFORMS
    jl .clear_loop
    
    ; Première plateforme fixe (Base)
    lea rbx, [rel platforms_x]
    mov dword [rbx], 350
    lea rbx, [rel platforms_y]
    mov dword [rbx], 520
    lea rbx, [rel platforms_active]
    mov byte [rbx], 1
    
    mov dword [rel highest_platform_y], 520
    mov dword [rel highest_platform_x], 350
    
    ; Génération initiale
    mov r12d, 1
.gen_loop:
    cmp r12d, MAX_PLATFORMS
    jge .done
    call create_one_platform
    inc r12d
    jmp .gen_loop
    
.done:
    add rsp, 32
    pop r13
    pop r12
    pop rbx
    ret

platforms_update:
    sub rsp, 40
    call platforms_check_collision
    call platforms_cleanup_old
    call platforms_generate_new
    add rsp, 40
    ret

platforms_cleanup_old:
    push rbx
    push r12
    xor r12d, r12d
.loop:
    cmp r12d, MAX_PLATFORMS
    jge .done
    
    lea rbx, [rel platforms_active]
    cmp byte [rbx + r12], 0
    je .next
    
    lea rbx, [rel platforms_y]
    mov eax, [rbx + r12*4]
    
    mov edx, [rel camera_y]
    sub eax, edx
    
    cmp eax, SCREEN_H + 50
    jl .next
    
    lea rbx, [rel platforms_active]
    mov byte [rbx + r12], 0
.next:
    inc r12d
    jmp .loop
.done:
    pop r12
    pop rbx
    ret

platforms_generate_new:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 40

    mov eax, [rel highest_platform_y]
    mov edx, [rel camera_y]
    sub eax, edx

    cmp eax, 0
    jg .done

    xor r12d, r12d
    lea rbx, [rel platforms_active]
.find_slot:
    cmp r12d, MAX_PLATFORMS
    jge .done
    cmp byte [rbx + r12], 0
    je .found
    inc r12d
    jmp .find_slot

.found:
    ; Try to consume from pre-generated pool first
    call platpool_consume
    test ecx, ecx
    jz .fallback

    ; Got a platform from pool: eax=x, edx=y
    mov r13d, eax
    mov r14d, edx
    lea rbx, [rel platforms_x]
    mov [rbx + r12*4], r13d
    lea rbx, [rel platforms_y]
    mov [rbx + r12*4], r14d
    lea rbx, [rel platforms_active]
    mov byte [rbx + r12], 1

    ; On ne modifie PLUS highest_platform_y ici pour ne pas corrompre le thread de génération

    ; Request more generation if pool is getting low
    call platpool_request
    jmp .done

.fallback:
    ; Pool empty — fall back to synchronous generation
    call create_one_platform

.done:
    add rsp, 40
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

create_one_platform:
    call random
    xor edx, edx
    mov ecx, 400        
    div ecx             
    sub edx, 200        
    add edx, [rel highest_platform_x]
    
    cmp edx, 0
    jge .check_max
    mov edx, 0
    jmp .save_x
.check_max:
    cmp edx, 720
    jle .save_x
    mov edx, 720
.save_x:
    mov r13d, edx
    mov [rel highest_platform_x], r13d
    lea rbx, [rel platforms_x]
    mov [rbx + r12*4], r13d
    call random
    xor edx, edx
    mov ecx, 60
    div ecx
    add edx, 30
    mov eax, [rel highest_platform_y]
    sub eax, edx
    lea rbx, [rel platforms_y]
    mov [rbx + r12*4], eax
    mov [rel highest_platform_y], eax
    lea rbx, [rel platforms_active]
    mov byte [rbx + r12], 1
    ret

; ============================================================
; SSE2 SIMD collision detection — 4 platforms per iteration
; ============================================================
platforms_check_collision:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 40

    mov eax, [rel vel_y]
    cmp eax, 0
    jle .col_done

    lea r14, [rel platforms_x]
    lea r15, [rel platforms_y]
    lea r13, [rel platforms_active]

    mov r8d, [rel player_x]        
    mov r9d, [rel player_y]        
    mov ebp, r9d
    add ebp, PLAYER_H              

    mov eax, r8d
    add eax, PLAYER_W              
    movd xmm1, eax
    pshufd xmm1, xmm1, 0           

    movd xmm2, r8d
    pshufd xmm2, xmm2, 0

    movd xmm3, ebp
    pshufd xmm3, xmm3, 0

    mov eax, [rel camera_y]
    movd xmm5, eax
    pshufd xmm5, xmm5, 0

    mov eax, PLATFORM_W
    movd xmm6, eax
    pshufd xmm6, xmm6, 0

    mov eax, 16
    movd xmm7, eax
    pshufd xmm7, xmm7, 0

    xor r12d, r12d                  

.simd_loop:
    cmp r12d, MAX_PLATFORMS
    jge .col_done

    movdqu xmm8, [r14 + r12*4]     
    movdqu xmm9, [r15 + r12*4]     
    psubd xmm9, xmm5               

    movdqa xmm10, xmm1             
    pcmpgtd xmm10, xmm8            

    movdqa xmm11, xmm8             
    paddd xmm11, xmm6              
    pcmpgtd xmm11, xmm2            

    movdqa xmm12, xmm3             
    mov eax, 1
    movd xmm0, eax
    pshufd xmm0, xmm0, 0
    paddd xmm12, xmm0              
    pcmpgtd xmm12, xmm9            

    movdqa xmm0, xmm9              
    paddd xmm0, xmm7               
    mov eax, 1
    movd xmm4, eax
    pshufd xmm4, xmm4, 0
    paddd xmm0, xmm4               
    pcmpgtd xmm0, xmm3             

    pand xmm10, xmm11
    pand xmm10, xmm12
    pand xmm10, xmm0               

    pmovmskb eax, xmm10            
    test eax, eax
    jz .simd_next                   

    test eax, 0x000F
    jz .check_lane1
    mov ebx, r12d
    cmp byte [r13 + rbx], 0
    je .check_lane1
    jmp .collision_hit

.check_lane1:
    test eax, 0x00F0
    jz .check_lane2
    lea ebx, [r12d + 1]
    cmp ebx, MAX_PLATFORMS
    jge .check_lane2
    cmp byte [r13 + rbx], 0
    je .check_lane2
    jmp .collision_hit

.check_lane2:
    test eax, 0x0F00
    jz .check_lane3
    lea ebx, [r12d + 2]
    cmp ebx, MAX_PLATFORMS
    jge .check_lane3
    cmp byte [r13 + rbx], 0
    je .check_lane3
    jmp .collision_hit

.check_lane3:
    test eax, 0xF000
    jz .simd_next
    lea ebx, [r12d + 3]
    cmp ebx, MAX_PLATFORMS
    jge .simd_next
    cmp byte [r13 + rbx], 0
    je .simd_next

.collision_hit:
    mov dword [rel vel_y], -18
    mov ecx, CMD_PLAY_JUMP
    call audio_post_cmd
    jmp .col_done

.simd_next:
    add r12d, 4                     
    jmp .simd_loop

.col_done:
    add rsp, 40
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

platforms_render:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    push rsi

    lea rdx, [rel backbuffer]
    xor r12d, r12d

    lea r13, [rel platforms_active]
    lea r14, [rel platforms_x]
    lea r15, [rel platforms_y]

.ploop:
    cmp r12d, MAX_PLATFORMS
    jge .pdone

    cmp byte [r13 + r12], 0
    je .next_platform

    mov ebx, [r14 + r12*4]
    mov edi, [r15 + r12*4]          

    mov eax, 520
    sub eax, edi                    
    sar eax, 3
    cmp eax, 0
    jge .clamp_hi
    xor eax, eax
.clamp_hi:
    cmp eax, 255
    jle .clamp_done
    mov eax, 255
.clamp_done:
    mov esi, eax                    

    mov ecx, 255
    sub ecx, esi                    
    shl ecx, 8                      

    mov eax, esi
    shr eax, 1
    add eax, 128                    
    cmp eax, 255
    jle .b_ok
    mov eax, 255
.b_ok:
    shl eax, 16                     
    or ecx, eax                     
    or ecx, esi                     
    mov ebp, ecx                    

    mov eax, [rel camera_y]
    sub edi, eax                    

    mov r8d, PLATFORM_H
.y_loop:
    mov r9d, PLATFORM_W
.x_loop:
    mov eax, edi
    add eax, PLATFORM_H
    sub eax, r8d

    cmp eax, 0
    jl .skip_pixel
    cmp eax, SCREEN_H
    jge .skip_pixel

    imul eax, SCREEN_W

    mov r10d, ebx
    add r10d, PLATFORM_W
    sub r10d, r9d

    cmp r10d, 0
    jl .skip_pixel
    cmp r10d, SCREEN_W
    jge .skip_pixel

    add eax, r10d
    mov [rdx + rax*4], ebp          

.skip_pixel:
    dec r9d
    jnz .x_loop
    dec r8d
    jnz .y_loop

.next_platform:
    inc r12d
    jmp .ploop

.pdone:
    pop rsi
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret