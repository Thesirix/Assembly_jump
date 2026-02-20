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
    sub rsp, 40
    
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
    add rsp, 40
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

    ; Update tracking
    mov [rel highest_platform_x], r13d
    mov [rel highest_platform_y], r14d

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

platforms_check_collision:
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    xor r12d, r12d
    lea r13, [rel platforms_active]
    lea r14, [rel platforms_x]
    lea r15, [rel platforms_y]

.loop:
    cmp r12d, MAX_PLATFORMS
    jge .done
    
    cmp byte [r13 + r12], 0
    je .next
    
    mov eax, [r14 + r12*4]
    mov edx, [r15 + r12*4]
    sub edx, [rel camera_y]

    mov r8d, [rel player_x]
    mov r9d, [rel player_y]
    
    mov r10d, r8d
    add r10d, PLAYER_W
    cmp r10d, eax
    jle .next
    
    mov r10d, eax
    add r10d, PLATFORM_W
    cmp r8d, r10d
    jge .next
    
    mov r11d, r9d
    add r11d, PLAYER_H
    
    cmp r11d, edx
    jl .next
    
    mov r10d, edx
    add r10d, 16
    cmp r11d, r10d
    jg .next
    
    mov eax, [rel vel_y]
    cmp eax, 0
    jle .next
    
    ; --- COLLISION DETECTEE ---
    mov dword [rel vel_y], -18
    
    ; JOUER SON "BOUING" (post to audio thread)
    sub rsp, 40
    mov ecx, CMD_PLAY_JUMP
    call audio_post_cmd
    add rsp, 40
    
.next:
    inc r12d
    jmp .loop
    
.done:
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
    
    lea rdx, [rel backbuffer]
    xor r12d, r12d
    
    lea r13, [rel platforms_active]
    lea r14, [rel platforms_x]
    lea r15, [rel platforms_y]

.ploop:
    cmp r12d, MAX_PLATFORMS
    jge .done
    
    cmp byte [r13 + r12], 0
    je .next_platform
    
    mov ebx, [r14 + r12*4]
    mov edi, [r15 + r12*4]
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
    mov dword [rdx + rax*4], 0x0000FF00
    
.skip_pixel:
    dec r9d
    jnz .x_loop
    dec r8d
    jnz .y_loop
    
.next_platform:
    inc r12d
    jmp .ploop
    
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret