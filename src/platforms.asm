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
extern camera_y

%define SCREEN_W 800
%define SCREEN_H 600
%define PLAYER_W 24
%define PLAYER_H 24
%define PLATFORM_W 80
%define PLATFORM_H 12
%define MAX_PLATFORMS 12

section .data
rand_seed dd 12345

section .bss
platforms_x resd MAX_PLATFORMS
platforms_y resd MAX_PLATFORMS
platforms_active resb MAX_PLATFORMS
highest_platform_y resd 1

section .text

; =============================
; Générateur pseudo-aléatoire
; =============================
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

; =============================
; Initialisation
; =============================
platforms_init:
    push rbx
    push r12
    push r13
    sub rsp, 40
    
    ; Première plateforme sous le joueur
    lea rbx, [rel platforms_x]
    mov dword [rbx], 350        ; Centré à peu près
    
    lea rbx, [rel platforms_y]
    mov dword [rbx], 520
    
    lea rbx, [rel platforms_active]
    mov byte [rbx], 1
    
    mov dword [rel highest_platform_y], 520
    
    ; Générer les autres
    mov r12d, 1
.gen_loop:
    cmp r12d, MAX_PLATFORMS
    jge .done
    
    call random
    xor edx, edx
    mov ecx, SCREEN_W - PLATFORM_W
    div ecx
    mov r13d, edx
    
    lea rbx, [rel platforms_x]
    mov [rbx + r12*4], r13d
    
    call random
    xor edx, edx
    mov ecx, 80
    div ecx
    add edx, 60
    
    mov eax, [rel highest_platform_y]
    sub eax, edx
    
    lea rbx, [rel platforms_y]
    mov [rbx + r12*4], eax
    mov [rel highest_platform_y], eax
    
    lea rbx, [rel platforms_active]
    mov byte [rbx + r12], 1
    
    inc r12d
    jmp .gen_loop
    
.done:
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    ret

; =============================
; Update
; =============================
platforms_update:
    sub rsp, 40
    call platforms_check_collision
    call platforms_cleanup_old
    call platforms_generate_new
    add rsp, 40
    ret

; =============================
; Cleanup
; =============================
platforms_cleanup_old:
    push rbx
    push r12
    xor r12d, r12d
.loop:
    cmp r12d, MAX_PLATFORMS
    jge .done
    
    lea rbx, [rel platforms_y]
    mov eax, [rbx + r12*4]
    
    mov edx, [rel camera_y]
    sub eax, edx
    
    cmp eax, SCREEN_H + 50
    jl .keep
    
    lea rbx, [rel platforms_active]
    mov byte [rbx + r12], 0
.keep:
    inc r12d
    jmp .loop
.done:
    pop r12
    pop rbx
    ret

; =============================
; Generate New
; =============================
platforms_generate_new:
    push rbx
    push r12
    push r13
    sub rsp, 40
    
    xor r12d, r12d
    lea rbx, [rel platforms_active]
.find_loop:
    cmp r12d, MAX_PLATFORMS
    jge .no_slot
    cmp byte [rbx + r12], 0
    je .found_slot
    inc r12d
    jmp .find_loop
.no_slot:
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    ret
    
.found_slot:
    mov eax, [rel highest_platform_y]
    mov edx, [rel camera_y]
    sub eax, edx
    cmp eax, 0 ; Si la plus haute est hors écran (en haut), on génère
    jg .no_gen ; On attend qu'elle descende un peu
    
    call random
    xor edx, edx
    mov ecx, SCREEN_W - PLATFORM_W
    div ecx
    mov r13d, edx
    
    lea rbx, [rel platforms_x]
    mov [rbx + r12*4], r13d
    
    call random
    xor edx, edx
    mov ecx, 90
    div ecx
    add edx, 50
    
    mov eax, [rel highest_platform_y]
    sub eax, edx
    
    lea rbx, [rel platforms_y]
    mov [rbx + r12*4], eax
    mov [rel highest_platform_y], eax
    
    lea rbx, [rel platforms_active]
    mov byte [rbx + r12], 1
    
.no_gen:
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    ret

; =============================
; COLLISION (CORRIGÉ)
; =============================
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
    
    ; 1. Récupérer X et Y de la plateforme
    mov eax, [r14 + r12*4]      ; PLATFORM X
    mov edx, [r15 + r12*4]      ; PLATFORM Y (Monde)
    
    ; --- CORRECTION CRITIQUE ---
    ; On doit convertir la position MONDE de la plateforme en position ÉCRAN
    ; pour la comparer avec le joueur qui est en coordonnées écran.
    sub edx, [rel camera_y]     ; PLATFORM Y SCREEN
    ; ---------------------------

    mov r8d, [rel player_x]
    mov r9d, [rel player_y]
    
    ; Test X
    mov r10d, r8d
    add r10d, PLAYER_W
    cmp r10d, eax
    jle .next
    
    mov r10d, eax
    add r10d, PLATFORM_W
    cmp r8d, r10d
    jge .next
    
    ; Test Y
    ; On vérifie si le bas du joueur touche le haut de la plateforme
    mov r11d, r9d
    add r11d, PLAYER_H          ; Bas du joueur
    
    ; Tolérance de collision (on doit arriver par le haut)
    cmp r11d, edx               ; Si bas joueur < haut plat -> au dessus
    jl .next
    
    mov r10d, edx
    add r10d, 16                ; Tolérance (épaisseur collision)
    cmp r11d, r10d
    jg .next
    
    ; Vérifier qu'on tombe (vitesse positive)
    mov eax, [rel vel_y]
    cmp eax, 0
    jle .next
    
    ; REBOND
    mov dword [rel vel_y], -18
    
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

; =============================
; Render
; =============================
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
    
    mov ebx, [r14 + r12*4]      ; X
    mov edi, [r15 + r12*4]      ; Y Monde
    
    ; Conversion Monde -> Ecran
    mov eax, [rel camera_y]
    sub edi, eax
    
    ; Dessin (Pixel par pixel vert)
    mov r8d, PLATFORM_H
.y_loop:
    mov r9d, PLATFORM_W
.x_loop:
    mov eax, edi
    add eax, PLATFORM_H
    sub eax, r8d
    
    ; Clipping Y
    cmp eax, 0
    jl .skip_pixel
    cmp eax, SCREEN_H
    jge .skip_pixel
    
    imul eax, SCREEN_W
    
    mov r10d, ebx
    add r10d, PLATFORM_W
    sub r10d, r9d
    
    ; Clipping X
    cmp r10d, 0
    jl .skip_pixel
    cmp r10d, SCREEN_W
    jge .skip_pixel
    
    add eax, r10d
    mov dword [rdx + rax*4], 0x0000FF00 ; Vert
    
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