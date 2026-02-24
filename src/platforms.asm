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


global part_x
global part_y
global part_vx
global part_vy
global part_life
global part_color
global part_grav_tick

extern backbuffer
extern player_x
extern player_y
extern vel_y
extern camera_y
extern current_score

extern audio_post_cmd
%define CMD_PLAY_JUMP 1

extern platpool_consume
extern platpool_request

extern wrap_perlin2d
extern wrap_plat_freq
extern wrap_sin

%define SCREEN_W        800
%define SCREEN_H        600
%define PLAYER_W        24
%define PLAYER_H        24
%define PLATFORM_W      80
%define PLATFORM_H      12
%define MAX_PLATFORMS   32
%define MAX_PARTICLES   512

section .data

rand_seed dd 12345
bounce_vel dq -12.0

perlin_perm:
    times 256 db 0

fpu_base_freq   dd 0.008
fpu_desync      dd 0.7          ; decalage de phase par index
fpu_40          dd 40.0

anim_tick dd 0


plat_margins db 4, 2, 1, 0, 0, 0, 0, 0, 0, 1, 2, 4

section .bss

platforms_x      resd MAX_PLATFORMS
platforms_y      resd MAX_PLATFORMS
platforms_active resb MAX_PLATFORMS
platforms_mobile resb MAX_PLATFORMS
platforms_base_x resd MAX_PLATFORMS
platforms_hit_timer resb MAX_PLATFORMS
highest_platform_y resd 1
highest_platform_x resd 1
platform_color resd 1

part_x      resd MAX_PARTICLES
part_y      resd MAX_PARTICLES
part_vx     resd MAX_PARTICLES
part_vy     resd MAX_PARTICLES
part_life   resb MAX_PARTICLES
part_color  resd MAX_PARTICLES
part_grav_tick resd 1

fpu_temp     resd 1
fpu_freq_tmp resq 1
emit_save_idx resd 1

section .text


; random - LCG (Linear Congruential Generator)
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


perlin_init:
    push rbx
    push r12
    sub rsp, 40


    lea rbx, [rel perlin_perm]
    xor ecx, ecx
.fill:
    mov byte [rbx + rcx], cl
    inc ecx
    cmp ecx, 256
    jl .fill


    mov r12d, 255
.shuffle:
    cmp r12d, 0
    jle .shuffle_done
    call random
    xor edx, edx
    mov ecx, r12d
    inc ecx
    div ecx
    lea rbx, [rel perlin_perm]
    mov al,  [rbx + r12]
    mov cl,  [rbx + rdx]
    mov [rbx + r12], cl
    mov [rbx + rdx], al
    dec r12d
    jmp .shuffle
.shuffle_done:
    add rsp, 40
    pop r12
    pop rbx
    ret


noise1d:
    push rbx
    push r12
    push r13

    mov eax, ecx
    mov r12d, eax
    and r12d, 0xFF             

    sar eax, 8
    and eax, 0xFF
    mov ebx, eax

    lea r13, [rel perlin_perm]
    movzx eax, byte [r13 + rbx]
    sub eax, 128
    mov ecx, eax               

    inc ebx
    and ebx, 0xFF
    movzx eax, byte [r13 + rbx]
    sub eax, 128               

    ; Interpolation linéaire entière
    sub eax, ecx
    imul eax, r12d
    sar eax, 8
    add eax, ecx               

    pop r13
    pop r12
    pop rbx
    ret

; hsv_to_rgb - Conversion HSV -> RGB entier pur
hsv_to_rgb:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, ecx               ; hue
    mov r13d, edx               ; sat
    mov r14d, r8d               ; val

    ; Secteur HSV (0..5)
    mov eax, r12d
    xor edx, edx
    mov ecx, 60
    div ecx
    mov ebx, eax                ; secteur
    mov r15d, edx               ; reste

    ; f = reste * 255 / 60 (facteur d'interpolation)
    imul r15d, 255
    mov eax, r15d
    xor edx, edx
    mov ecx, 60
    div ecx
    mov r15d, eax               ; f

    ; p = val * (255 - sat) / 255
    mov eax, 255
    sub eax, r13d
    imul eax, r14d
    xor edx, edx
    mov ecx, 255
    div ecx
    push rax                    ; [rsp] = p

    ; q = val * (255 - sat*f/255) / 255
    mov eax, r13d
    imul eax, r15d
    xor edx, edx
    mov ecx, 255
    div ecx
    mov ecx, 255
    sub ecx, eax
    imul ecx, r14d
    mov eax, ecx
    xor edx, edx
    mov ecx, 255
    div ecx
    push rax                    ; [rsp]=q, [rsp+8]=p

    ; t = val * (255 - sat*(255-f)/255) / 255
    mov eax, 255
    sub eax, r15d
    imul eax, r13d
    xor edx, edx
    mov ecx, 255
    div ecx
    mov ecx, 255
    sub ecx, eax
    imul ecx, r14d
    mov eax, ecx
    xor edx, edx
    mov ecx, 255
    div ecx
    mov r15d, eax               ; t

    pop rcx                     ; q
    pop rdx                     ; p

    ; Sélectionner R,G,B selon le secteur
    cmp ebx, 0
    je .sec0
    cmp ebx, 1
    je .sec1
    cmp ebx, 2
    je .sec2
    cmp ebx, 3
    je .sec3
    cmp ebx, 4
    je .sec4
    jmp .sec5

.sec0: ; R=val, G=t,   B=p
    mov eax, edx
    shl eax, 8
    or eax, r15d
    shl eax, 8
    or eax, r14d
    jmp .hsv_done
.sec1: ; R=q,   G=val, B=p
    mov eax, edx
    shl eax, 8
    or eax, r14d
    shl eax, 8
    or eax, ecx
    jmp .hsv_done
.sec2: ; R=p,   G=val, B=t
    mov eax, r15d
    shl eax, 8
    or eax, r14d
    shl eax, 8
    or eax, edx
    jmp .hsv_done
.sec3: ; R=p,   G=q,   B=val
    mov eax, r14d
    shl eax, 8
    or eax, ecx
    shl eax, 8
    or eax, edx
    jmp .hsv_done
.sec4: ; R=t,   G=p,   B=val
    mov eax, r14d
    shl eax, 8
    or eax, edx
    shl eax, 8
    or eax, r15d
    jmp .hsv_done
.sec5: ; R=val, G=p,   B=q
    mov eax, ecx
    shl eax, 8
    or eax, edx
    shl eax, 8
    or eax, r14d

.hsv_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


platforms_init:
    push rbx
    push r12
    push r13
    sub rsp, 32

    rdtsc
    mov [rel rand_seed], eax

    call perlin_init

    ; Reset toutes les tables
    xor r12d, r12d
    lea rbx, [rel platforms_active]
.clear_active:
    mov byte [rbx + r12], 0
    inc r12d
    cmp r12d, MAX_PLATFORMS
    jl .clear_active

    xor r12d, r12d
    lea rbx, [rel platforms_mobile]
.clear_mobile:
    mov byte [rbx + r12], 0
    inc r12d
    cmp r12d, MAX_PLATFORMS
    jl .clear_mobile

    xor r12d, r12d
    lea rbx, [rel platforms_hit_timer]
.clear_timer:
    mov byte [rbx + r12], 0
    inc r12d
    cmp r12d, MAX_PLATFORMS
    jl .clear_timer

    ; Reset particules (MAX_PARTICLES = 512)
    xor r12d, r12d
    lea rbx, [rel part_life]
.clear_parts:
    mov byte [rbx + r12], 0
    inc r12d
    cmp r12d, MAX_PARTICLES
    jl .clear_parts

    mov dword [rel anim_tick], 0
    mov dword [rel part_grav_tick], 0

    ; Première plateforme fixe
    lea rbx, [rel platforms_x]
    mov dword [rbx], 350
    lea rbx, [rel platforms_y]
    mov dword [rbx], 520
    lea rbx, [rel platforms_active]
    mov byte [rbx], 1
    lea rbx, [rel platforms_base_x]
    mov dword [rbx], 350
    lea rbx, [rel platforms_mobile]
    mov byte [rbx], 0           ; première plateforme jamais mobile

    mov dword [rel highest_platform_y], 520
    mov dword [rel highest_platform_x], 350
    mov dword [rel platform_color], 0x0000FF00

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

    inc dword [rel anim_tick]

    call platforms_check_collision
    call platforms_hit_timer_update
    call platforms_update_mobile
    call platforms_cleanup_old
    call platforms_generate_new
    call update_platform_color

    add rsp, 40
    ret


update_platform_color:
    push rbx
    sub rsp, 32

    mov eax, [rel camera_y]
    neg eax
    cmp eax, 0
    jge .pos_cam
    xor eax, eax
.pos_cam:
    xor edx, edx
    mov ecx, 50
    div ecx
    xor edx, edx
    mov ecx, 360
    div ecx

    mov ecx, edx               
    mov edx, 200              
    mov r8d, 220              
    call hsv_to_rgb
    mov [rel platform_color], eax

    add rsp, 32
    pop rbx
    ret


platforms_hit_timer_update:
    push rbx
    push r12
    xor r12d, r12d
    lea rbx, [rel platforms_hit_timer]
.loop:
    cmp r12d, MAX_PLATFORMS
    jge .done
    cmp byte [rbx + r12], 0
    je .next
    dec byte [rbx + r12]
.next:
    inc r12d
    jmp .loop
.done:
    pop r12
    pop rbx
    ret

; platforms_update_mobile - Oscillation SSE2 + sin via bridge C
platforms_update_mobile:
    push rbx
    push r12
    sub rsp, 56

    xor r12d, r12d

.loop:
    cmp r12d, MAX_PLATFORMS
    jge .done


    lea rbx, [rel platforms_mobile]
    cmp byte [rbx + r12], 0
    je .next

    lea rbx, [rel platforms_active]
    cmp byte [rbx + r12], 0
    je .next


    mov ecx, r12d
    call wrap_plat_freq
    movsd [rel fpu_freq_tmp], xmm0

    mov eax, [rel anim_tick]
    cvtsi2sd xmm0, eax
    mulsd xmm0, [rel fpu_freq_tmp]

    cvtsi2sd xmm1, r12d
    movss xmm2, [rel fpu_desync]
    cvtss2sd xmm2, xmm2
    mulsd xmm1, xmm2
    addsd xmm0, xmm1

    call wrap_sin

    movss xmm1, [rel fpu_40]
    cvtss2sd xmm1, xmm1
    mulsd xmm0, xmm1

    cvttsd2si eax, xmm0
    mov [rel fpu_temp], eax
    lea rbx, [rel platforms_base_x]
    mov eax, [rbx + r12*4]
    add eax, [rel fpu_temp]

    ; Clamp  (bords visibles, plateforme jamais collée aux murs)
    cmp eax, 30
    jge .clamp_max
    mov eax, 30
    jmp .store_x
.clamp_max:
    cmp eax, 690
    jle .store_x
    mov eax, 690
.store_x:
    lea rbx, [rel platforms_x]
    mov [rbx + r12*4], eax

.next:
    inc r12d
    jmp .loop
.done:
    add rsp, 56
    pop r12
    pop rbx
    ret

; Supprimer les plateformes sorties du bas
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
    lea rbx, [rel platforms_hit_timer]
    mov byte [rbx + r12], 0
.next:
    inc r12d
    jmp .loop
.done:
    pop r12
    pop rbx
    ret

; Créer une plateforme si nécessaire
platforms_generate_new:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 40

    ; Si la plateforme la plus haute est encore à l'écran, ne rien faire
    mov eax, [rel highest_platform_y]
    mov edx, [rel camera_y]
    sub eax, edx
    cmp eax, 0
    jg .done

    ; Chercher un slot libre
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
    ; Essayer le pool du thread platgen d'abord
    call platpool_consume
    test ecx, ecx
    jz .fallback

    ; Plateforme depuis le pool
    mov r13d, eax               ; x
    mov r14d, edx               ; y
    lea rbx, [rel platforms_x]
    mov [rbx + r12*4], r13d
    lea rbx, [rel platforms_y]
    mov [rbx + r12*4], r14d
    lea rbx, [rel platforms_active]
    mov byte [rbx + r12], 1
    lea rbx, [rel platforms_base_x]
    mov [rbx + r12*4], r13d

    ; --- MOBILE : 20% aléatoire ---
    call random
    xor edx, edx
    mov ecx, 5
    div ecx
    lea rbx, [rel platforms_mobile]
    cmp edx, 0                 
    jne .not_mobile_pool
    mov byte [rbx + r12], 1
    jmp .pool_done
.not_mobile_pool:
    mov byte [rbx + r12], 0
.pool_done:
    lea rbx, [rel platforms_hit_timer]
    mov byte [rbx + r12], 0
    call platpool_request
    jmp .done

.fallback:
    call create_one_platform

.done:
    add rsp, 40
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

;LCG + biais Perlin 2D (via bridge C)
create_one_platform:
    push r14
    push r15
    sub rsp, 56

    ; --- X : LCG random offset [-200, +200] centré sur highest_x ---
    call random
    xor edx, edx
    mov ecx, 400
    div ecx
    sub edx, 200            
    add edx, [rel highest_platform_x]

 
    mov dword [rsp+32], edx    

    mov ecx, [rel highest_platform_y]
    sar ecx, 7                 
    mov edx, [rel highest_platform_x]
    sar edx, 7                  
    call wrap_perlin2d

    ; Réduire le biais à 25%
    sar eax, 2

    mov edx, dword [rsp+32]     ; récupérer X LCG (depuis espace local)
    add edx, eax               ; X final = LCG + petit biais Perlin 2D


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
    lea rbx, [rel platforms_base_x]
    mov [rbx + r12*4], r13d

    ; --- Y : gap progressif selon le score ---
    mov eax, [rel current_score]
    cmp eax, 1000
    jl .easy
    cmp eax, 5000
    jl .medium
    
    mov r14d, 55
    mov r15d, 45
    jmp .gen_gap
.easy:
   
    mov r14d, 30
    mov r15d, 30
    jmp .gen_gap
.medium:
 
    mov r14d, 40
    mov r15d, 40

.gen_gap:
    call random
    xor edx, edx
    mov ecx, r15d
    test ecx, ecx
    jz .use_min
    div ecx
    add edx, r14d
    jmp .apply_gap
.use_min:
    mov edx, r14d
.apply_gap:
    mov eax, [rel highest_platform_y]
    sub eax, edx
    lea rbx, [rel platforms_y]
    mov [rbx + r12*4], eax
    mov [rel highest_platform_y], eax


    lea rbx, [rel platforms_active]
    mov byte [rbx + r12], 1

 
    call random
    xor edx, edx
    mov ecx, 5
    div ecx
    lea rbx, [rel platforms_mobile]
    cmp edx, 0
    jne .not_mobile
    mov byte [rbx + r12], 1
    jmp .plat_created
.not_mobile:
    mov byte [rbx + r12], 0
.plat_created:
    lea rbx, [rel platforms_hit_timer]
    mov byte [rbx + r12], 0

    add rsp, 56
    pop r15
    pop r14
    ret

; SSE2 SIMD collision - 4 plateformes par itération
platforms_check_collision:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 40

    ; collision seulement si le joueur descend (vel_y > 0)
    mov rax, [rel vel_y]
    test rax, rax
    js .col_done
    jz .col_done

    lea r14, [rel platforms_x]
    lea r15, [rel platforms_y]
    lea r13, [rel platforms_active]

    mov r8d, [rel player_x]
    mov r9d, [rel player_y]
    mov ebp, r9d
    add ebp, PLAYER_H

    ; broadcast des valeurs joueur dans les registres SSE2 (4-wide)
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
    psubd xmm9, xmm5               ; screen_y = world_y - camera_y

    ; AABB 4-wide : 4 conditions en parallele
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

    ; collision si les 4 masques sont vrais
    pand xmm10, xmm11
    pand xmm10, xmm12
    pand xmm10, xmm0

    pmovmskb eax, xmm10
    test eax, eax
    jz .simd_next

    ; Trouver quelle lane a la collision
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
  
    mov rax, [rel bounce_vel]       
    mov [rel vel_y], rax          

    ; Son de saut
    mov ecx, CMD_PLAY_JUMP
    call audio_post_cmd

  
    mov byte [r13 + rbx], 0         ; La plateforme est détruite et disparait visuellement

    ; Émettre 16 particules à l'endroit exact où était la plateforme
    call emit_particles

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

; emit_particles — Émettre 16 particules depuis la plateforme
emit_particles:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48

 
    lea rax, [rel platforms_x]
    mov r13d, [rax + rbx*4]
    lea rax, [rel platforms_y]
    mov r14d, [rax + rbx*4]
    mov eax, [rel camera_y]
    sub r14d, eax

    ; Couleur avec éclat initial 
    mov r15d, [rel platform_color]
    mov eax, r15d
    or eax, 0x00303030         
 
    ; R
    mov edx, eax
    and edx, 0xFF
    cmp edx, 255
    jle .r_eclat_ok
    or eax, 0x000000FF
.r_eclat_ok:
    ; G
    mov edx, eax
    shr edx, 8
    and edx, 0xFF
    cmp edx, 255
    jle .g_eclat_ok
    or eax, 0x0000FF00
.g_eclat_ok:
    ; B
    mov edx, eax
    shr edx, 16
    and edx, 0xFF
    cmp edx, 255
    jle .b_eclat_ok
    or eax, 0x00FF0000
.b_eclat_ok:
    mov r15d, eax              


    xor r12d, r12d          
    xor ecx, ecx               

.find_part:
    cmp ecx, MAX_PARTICLES
    jge .emit_done
    cmp r12d, 16              
    jge .emit_done

    lea rax, [rel part_life]
    cmp byte [rax + rcx], 0
    jne .next_part

    mov [rel emit_save_idx], ecx

    ; x = plat_x + offset aléatoire dans [0, PLATFORM_W]
    call random
    xor edx, edx
    mov ecx, PLATFORM_W
    div ecx
    mov ecx, [rel emit_save_idx]
    add edx, r13d
    lea rax, [rel part_x]
    mov [rax + rcx*4], edx

    ; y = plat_y écran
    lea rax, [rel part_y]
    mov [rax + rcx*4], r14d

    ; vx = random(-5..+5)
    mov [rel emit_save_idx], ecx
    call random
    xor edx, edx
    mov ecx, 11                
    div ecx
    sub edx, 5               
    mov ecx, [rel emit_save_idx]
    lea rax, [rel part_vx]
    mov [rax + rcx*4], edx

    ; vy = random(-8..-2)
    mov [rel emit_save_idx], ecx
    call random
    xor edx, edx
    mov ecx, 7                 
    div ecx
    sub edx, 8               
    mov ecx, [rel emit_save_idx]
    lea rax, [rel part_vy]
    mov [rax + rcx*4], edx

  
    lea rax, [rel part_life]
    mov byte [rax + rcx], 60


    lea rax, [rel part_color]
    mov [rax + rcx*4], r15d

    inc r12d

.next_part:
    inc ecx
    jmp .find_part

.emit_done:
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    ret

;Rendu avec couleur HSV, forme arrondie
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

    mov ebp, [rel platform_color]

.ploop:
    cmp r12d, MAX_PLATFORMS
    jge .pdone

    cmp byte [r13 + r12], 0
    je .next_platform

    mov ebx, [r14 + r12*4]     
    mov edi, [r15 + r12*4]    

 
    mov eax, [rel camera_y]
    sub edi, eax


    mov esi, ebp
    lea rax, [rel platforms_hit_timer]
    movzx ecx, byte [rax + r12]
    test ecx, ecx
    jz .no_flash
    test ecx, 4
    jz .no_flash
    mov esi, 0x00FFFFFF
.no_flash:

    ; scanline SSE2 : 12 lignes, fill 4 pixels/store
    mov r8d, PLATFORM_H
.y_loop:
    mov ecx, PLATFORM_H
    sub ecx, r8d                   

    mov r9d, edi
    add r9d, ecx                  

    cmp r9d, 0
    jl .skip_row
    cmp r9d, SCREEN_H
    jge .skip_row

    lea rax, [rel plat_margins]
    movzx r10d, byte [rax + rcx]   
    mov r11d, ebx
    add r11d, r10d                
    mov ecx, ebx
    add ecx, PLATFORM_W
    sub ecx, r10d                  

    cmp r11d, SCREEN_W
    jge .skip_row
    cmp ecx, 0
    jle .skip_row
    cmp r11d, 0
    jge .lx_ok
    xor r11d, r11d
.lx_ok:
    cmp ecx, SCREEN_W
    jle .rx_ok
    mov ecx, SCREEN_W
.rx_ok:
    sub ecx, r11d
    cmp ecx, 0
    jle .skip_row

    imul r9d, SCREEN_W
    add r9d, r11d
    lea rax, [rdx + r9*4]

    movd xmm0, esi
    pshufd xmm0, xmm0, 0

    mov r10d, ecx
    shr r10d, 2
    jz .scalar_fill

.fill_sse2:
    movdqu [rax], xmm0
    add rax, 16
    dec r10d
    jnz .fill_sse2

.scalar_fill:
    and ecx, 3                      
    jz .skip_row
.fill_scalar:
    mov dword [rax], esi
    add rax, 4
    dec ecx
    jnz .fill_scalar

.skip_row:
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