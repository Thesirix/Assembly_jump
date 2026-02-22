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
global particles_update
global particles_render

extern backbuffer
extern player_x
extern player_y
extern vel_y
extern camera_y
extern current_score

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
%define MAX_PARTICLES 256

; ============================================================
section .data
; ============================================================
rand_seed dd 12345

; Constante float pour le rebond (vel_y est un float)
bounce_vel dd -12.0

; Table de permutation Perlin (256 entrées)
perlin_perm:
    times 256 db 0

; Constantes FPU pour oscillation des plateformes mobiles
fpu_point05  dd 0.05            ; Fréquence d'oscillation
fpu_40       dd 40.0            ; Amplitude en pixels

; Compteur animation plateformes mobiles
anim_tick dd 0

; ============================================================
section .bss
; ============================================================
platforms_x      resd MAX_PLATFORMS
platforms_y      resd MAX_PLATFORMS
platforms_active resb MAX_PLATFORMS

; Plateformes mobiles (1 sur 4)
platforms_mobile resb MAX_PLATFORMS
platforms_base_x resd MAX_PLATFORMS

; Timer de flash visuel (ne désactive PAS la plateforme)
platforms_hit_timer resb MAX_PLATFORMS

highest_platform_y resd 1
highest_platform_x resd 1

; Couleur HSV calculée pour les plateformes (BGR32)
platform_color resd 1

; --- Particules de désintégration ---
part_x    resd MAX_PARTICLES
part_y    resd MAX_PARTICLES
part_vx   resd MAX_PARTICLES
part_vy   resd MAX_PARTICLES
part_life resb MAX_PARTICLES
part_color resd MAX_PARTICLES

; Temporaire FPU
fpu_temp resd 1

; Temporaire pour sauvegarder l'index particule (évite push/pop)
emit_save_idx resd 1

; ============================================================
section .text
; ============================================================

; ============================================================
; random — LCG, retourne eax = 0..32767
; ============================================================
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

; ============================================================
; perlin_init — Table de permutation Fisher-Yates
; 2 pushes + sub 40 = 56. 56 mod 16 = 8. OK
; ============================================================
perlin_init:
    push rbx
    push r12
    sub rsp, 40                 ; CORRIGÉ (était 32)

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
    mov al, [rbx + r12]
    mov cl, [rbx + rdx]
    mov [rbx + r12], cl
    mov [rbx + rdx], al
    dec r12d
    jmp .shuffle
.shuffle_done:
    add rsp, 40
    pop r12
    pop rbx
    ret

; ============================================================
; noise1d — Bruit de Perlin 1D entier
; Entrée : ecx = coordonnée
; Sortie : eax = [-128, +127]
; Pas de calls → alignement non critique
; ============================================================
noise1d:
    push rbx
    push r12
    push r13

    mov eax, ecx
    mov r12d, eax
    and r12d, 0xFF              ; frac

    sar eax, 8
    and eax, 0xFF
    mov ebx, eax

    lea r13, [rel perlin_perm]
    movzx eax, byte [r13 + rbx]
    sub eax, 128
    mov ecx, eax               ; grad0

    inc ebx
    and ebx, 0xFF
    movzx eax, byte [r13 + rbx]
    sub eax, 128               ; grad1

    sub eax, ecx
    imul eax, r12d
    sar eax, 8
    add eax, ecx

    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; hsv_to_rgb — HSV → RGB entier
; ecx=hue(0..359), edx=sat(0..255), r8d=val(0..255)
; Retour : eax = 0x00BBGGRR
; 5 pushes + 2 pushes internes. Pas de calls → OK.
; ============================================================
hsv_to_rgb:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, ecx               ; hue
    mov r13d, edx               ; sat
    mov r14d, r8d               ; val

    mov eax, r12d
    xor edx, edx
    mov ecx, 60
    div ecx
    mov ebx, eax                ; sector
    mov r15d, edx               ; remainder

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

.sec0:
    mov eax, edx
    shl eax, 8
    or eax, r15d
    shl eax, 8
    or eax, r14d
    jmp .hsv_done
.sec1:
    mov eax, edx
    shl eax, 8
    or eax, r14d
    shl eax, 8
    or eax, ecx
    jmp .hsv_done
.sec2:
    mov eax, r15d
    shl eax, 8
    or eax, r14d
    shl eax, 8
    or eax, edx
    jmp .hsv_done
.sec3:
    mov eax, r14d
    shl eax, 8
    or eax, ecx
    shl eax, 8
    or eax, edx
    jmp .hsv_done
.sec4:
    mov eax, r14d
    shl eax, 8
    or eax, edx
    shl eax, 8
    or eax, r15d
    jmp .hsv_done
.sec5:
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

; ============================================================
; platforms_init
; 3 pushes + sub 32 = 56. 56 mod 16 = 8. OK
; ============================================================
platforms_init:
    push rbx
    push r12
    push r13
    sub rsp, 32

    rdtsc
    mov [rel rand_seed], eax

    call perlin_init

    ; Reset plateformes
    xor r12d, r12d
    lea rbx, [rel platforms_active]
.clear_loop:
    mov byte [rbx + r12], 0
    inc r12d
    cmp r12d, MAX_PLATFORMS
    jl .clear_loop

    ; Reset mobiles
    xor r12d, r12d
    lea rbx, [rel platforms_mobile]
.clear_mobile:
    mov byte [rbx + r12], 0
    inc r12d
    cmp r12d, MAX_PLATFORMS
    jl .clear_mobile

    ; Reset hit timers
    xor r12d, r12d
    lea rbx, [rel platforms_hit_timer]
.clear_timer:
    mov byte [rbx + r12], 0
    inc r12d
    cmp r12d, MAX_PLATFORMS
    jl .clear_timer

    ; Reset particules
    xor r12d, r12d
    lea rbx, [rel part_life]
.clear_parts:
    mov byte [rbx + r12], 0
    inc r12d
    cmp r12d, MAX_PARTICLES
    jl .clear_parts

    mov dword [rel anim_tick], 0

    ; Première plateforme fixe (Base)
    lea rbx, [rel platforms_x]
    mov dword [rbx], 350
    lea rbx, [rel platforms_y]
    mov dword [rbx], 520
    lea rbx, [rel platforms_active]
    mov byte [rbx], 1
    lea rbx, [rel platforms_base_x]
    mov dword [rbx], 350
    lea rbx, [rel platforms_mobile]
    mov byte [rbx], 0

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

; ============================================================
; platforms_update
; 0 pushes + sub 40. 40 mod 16 = 8. OK
; ============================================================
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

; ============================================================
; update_platform_color — HSV depuis camera_y
; 1 push + sub 32 = 40. 40 mod 16 = 8. OK
; ============================================================
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

    mov ecx, edx               ; hue
    mov edx, 200               ; sat
    mov r8d, 220               ; val
    call hsv_to_rgb
    mov [rel platform_color], eax

    add rsp, 32
    pop rbx
    ret

; ============================================================
; platforms_hit_timer_update — Décrémenter timers (VISUEL SEULEMENT)
; Ne désactive PAS les plateformes !
; ============================================================
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
    ; PAS de désactivation — le flash est purement cosmétique
.next:
    inc r12d
    jmp .loop
.done:
    pop r12
    pop rbx
    ret

; ============================================================
; platforms_update_mobile — Oscillation FPU fsin
; Pas de calls externes → alignement non critique
; ============================================================
platforms_update_mobile:
    push rbx
    push r12

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

    ; FPU : angle = anim_tick * 0.05 * (index + 1)
    fild dword [rel anim_tick]
    fmul dword [rel fpu_point05]
    mov eax, r12d
    inc eax
    mov [rel fpu_temp], eax
    fild dword [rel fpu_temp]
    fmulp st1, st0
    ; sin(angle)
    fsin
    ; * amplitude 40
    fmul dword [rel fpu_40]
    ; Convertir en entier → fpu_temp
    fistp dword [rel fpu_temp]

    ; x = base_x + offset
    lea rbx, [rel platforms_base_x]
    mov eax, [rbx + r12*4]
    add eax, [rel fpu_temp]

    ; Clamp [0, 720]
    cmp eax, 0
    jge .clamp_max
    xor eax, eax
    jmp .store_x
.clamp_max:
    cmp eax, 720
    jle .store_x
    mov eax, 720
.store_x:
    lea rbx, [rel platforms_x]
    mov [rbx + r12*4], eax

.next:
    inc r12d
    jmp .loop
.done:
    pop r12
    pop rbx
    ret

; ============================================================
; platforms_cleanup_old
; ============================================================
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

; ============================================================
; platforms_generate_new
; 4 pushes + sub 40 = 72. 72 mod 16 = 8. OK
; ============================================================
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
    call platpool_consume
    test ecx, ecx
    jz .fallback

    mov r13d, eax
    mov r14d, edx
    lea rbx, [rel platforms_x]
    mov [rbx + r12*4], r13d
    lea rbx, [rel platforms_y]
    mov [rbx + r12*4], r14d
    lea rbx, [rel platforms_active]
    mov byte [rbx + r12], 1
    lea rbx, [rel platforms_base_x]
    mov [rbx + r12*4], r13d
    ; Mobile si index % 4 == 0
    mov eax, r12d
    and eax, 3
    lea rbx, [rel platforms_mobile]
    cmp eax, 0
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

; ============================================================
; create_one_platform — ALGORITHME ORIGINAL (LCG random)
; + petit biais Perlin + difficulté progressive
; r12d = index du slot
; 2 pushes + sub 40 = 56. 56 mod 16 = 8. OK (CORRIGÉ)
; ============================================================
create_one_platform:
    push r14
    push r15
    sub rsp, 40                 ; CORRIGÉ (était 32)

    ; --- X : algorithme original LCG (comme avant) ---
    ; random offset dans [-200, +200] centré sur highest_platform_x
    call random
    xor edx, edx
    mov ecx, 400
    div ecx                     ; edx = random % 400
    sub edx, 200               ; offset = [-200, +199]
    add edx, [rel highest_platform_x]

    ; Ajouter un petit biais Perlin (±50 pixels) pour cohérence
    push rdx                    ; sauvegarder X brut
    mov ecx, [rel highest_platform_y]
    mov eax, ecx
    cdq
    mov ecx, 100
    idiv ecx
    mov ecx, eax
    call noise1d                ; eax = [-128, +127]
    ; Réduire à ±50
    sar eax, 1                  ; eax ≈ [-64, +63]
    pop rdx
    add edx, eax               ; X final = random + petit biais Perlin

    ; Clamp X à [0, 720]
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
    ; score >= 5000 : gap 55-100
    mov r14d, 55
    mov r15d, 45
    jmp .gen_gap
.easy:
    ; score < 1000 : gap 30-60 (comme l'original)
    mov r14d, 30
    mov r15d, 30
    jmp .gen_gap
.medium:
    ; score 1000-5000 : gap 40-80
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

    ; Activer
    lea rbx, [rel platforms_active]
    mov byte [rbx + r12], 1

    ; Mobile si index % 4 == 0
    mov eax, r12d
    and eax, 3
    lea rbx, [rel platforms_mobile]
    cmp eax, 0
    jne .not_mobile
    mov byte [rbx + r12], 1
    jmp .plat_created
.not_mobile:
    mov byte [rbx + r12], 0
.plat_created:
    lea rbx, [rel platforms_hit_timer]
    mov byte [rbx + r12], 0

    add rsp, 40
    pop r15
    pop r14
    ret

; ============================================================
; SSE2 SIMD collision — 4 plateformes par itération
; 6 pushes + sub 40 = 88. 88 mod 16 = 8. OK
; ============================================================
platforms_check_collision:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 40

    ; vel_y est un float IEEE 754 : bit 31 = signe
    mov eax, [rel vel_y]
    test eax, eax
    js .col_done               ; négatif → monte
    test eax, 0x7FFFFFFF
    jz .col_done               ; zéro

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
    ; ebx = index plateforme touchée
    ; Rebond : vel_y = -12.0f
    mov eax, [rel bounce_vel]
    mov [rel vel_y], eax

    ; Son de saut
    mov ecx, CMD_PLAY_JUMP
    call audio_post_cmd

    ; Flash visuel (30 frames, purement cosmétique)
    lea rax, [rel platforms_hit_timer]
    mov byte [rax + rbx], 30

    ; Émettre 8 particules
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

; ============================================================
; emit_particles — 8 particules depuis la plateforme ebx
; Appelé depuis collision_hit (rsp = 0 mod 16 à ce point)
; 4 pushes + sub 48 = 80. 80 mod 16 = 0.
; Entrée: rsp = 0 mod 16 (pas via call standard, même contexte)
; Pour robustesse : on utilise [rsp+32] pour sauvegarder l'index
; au lieu de push/pop autour des calls.
; ============================================================
emit_particles:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48                 ; shadow space + local save

    ; Position de la plateforme
    lea rax, [rel platforms_x]
    mov r13d, [rax + rbx*4]
    lea rax, [rel platforms_y]
    mov r14d, [rax + rbx*4]
    mov eax, [rel camera_y]
    sub r14d, eax

    ; Couleur
    mov r15d, [rel platform_color]

    ; Chercher 8 slots libres
    xor r12d, r12d              ; compteur émissions
    xor ecx, ecx               ; index particule

.find_part:
    cmp ecx, MAX_PARTICLES
    jge .emit_done
    cmp r12d, 8
    jge .emit_done

    lea rax, [rel part_life]
    cmp byte [rax + rcx], 0
    jne .next_part

    ; Sauvegarder l'index dans une variable statique (pas sur la pile)
    mov [rel emit_save_idx], ecx

    ; x = plat_x + random offset dans [0, PLATFORM_W]
    call random
    xor edx, edx
    mov ecx, PLATFORM_W
    div ecx
    mov ecx, [rel emit_save_idx]
    add edx, r13d
    lea rax, [rel part_x]
    mov [rax + rcx*4], edx

    ; y = plat_y (screen)
    lea rax, [rel part_y]
    mov [rax + rcx*4], r14d

    ; vx = random(-3..+3)
    mov [rel emit_save_idx], ecx
    call random
    xor edx, edx
    mov ecx, 7
    div ecx
    sub edx, 3
    mov ecx, [rel emit_save_idx]
    lea rax, [rel part_vx]
    mov [rax + rcx*4], edx

    ; vy = random(-5..-1)
    mov [rel emit_save_idx], ecx
    call random
    xor edx, edx
    mov ecx, 5
    div ecx
    sub edx, 5
    mov ecx, [rel emit_save_idx]
    lea rax, [rel part_vy]
    mov [rax + rcx*4], edx

    ; life = 30
    lea rax, [rel part_life]
    mov byte [rax + rcx], 30

    ; couleur
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

; ============================================================
; particles_update — x += vx, y += vy, vy += 1, life--
; ============================================================
particles_update:
    push rbx
    push r12
    xor r12d, r12d

.loop:
    cmp r12d, MAX_PARTICLES
    jge .done

    lea rbx, [rel part_life]
    cmp byte [rbx + r12], 0
    je .next

    dec byte [rbx + r12]

    lea rbx, [rel part_vx]
    mov eax, [rbx + r12*4]
    lea rbx, [rel part_x]
    add [rbx + r12*4], eax

    lea rbx, [rel part_vy]
    mov eax, [rbx + r12*4]
    lea rbx, [rel part_y]
    add [rbx + r12*4], eax

    lea rbx, [rel part_vy]
    inc dword [rbx + r12*4]

.next:
    inc r12d
    jmp .loop
.done:
    pop r12
    pop rbx
    ret

; ============================================================
; particles_render — 2x2 pixels, dégradé selon life
; ============================================================
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

    ; Bounds check (2x2 pixels)
    cmp r13d, 0
    jl .next
    cmp r13d, SCREEN_W - 2
    jge .next
    cmp r14d, 0
    jl .next
    cmp r14d, SCREEN_H - 2
    jge .next

    ; Couleur + fade
    lea rbx, [rel part_color]
    mov r15d, [rbx + r12*4]
    lea rbx, [rel part_life]
    movzx eax, byte [rbx + r12]
    mov ecx, 30
    sub ecx, eax
    shl ecx, 2
    cmp ecx, 120
    jle .fade_ok
    mov ecx, 120
.fade_ok:
    mov eax, r15d
    and eax, 0xFF
    add eax, ecx
    cmp eax, 255
    jle .r_ok
    mov eax, 255
.r_ok:
    mov edx, eax

    mov eax, r15d
    shr eax, 8
    and eax, 0xFF
    add eax, ecx
    cmp eax, 255
    jle .g_ok
    mov eax, 255
.g_ok:
    shl eax, 8
    or edx, eax

    mov eax, r15d
    shr eax, 16
    and eax, 0xFF
    add eax, ecx
    cmp eax, 255
    jle .b_ok
    mov eax, 255
.b_ok:
    shl eax, 16
    or edx, eax

    ; 2x2 pixels
    mov eax, r14d
    imul eax, SCREEN_W
    add eax, r13d
    mov [rbp + rax*4], edx
    mov [rbp + rax*4 + 4], edx
    add eax, SCREEN_W
    mov [rbp + rax*4], edx
    mov [rbp + rax*4 + 4], edx

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

; ============================================================
; platforms_render — HSV color + flash visuel
; ============================================================
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

    ; Screen Y
    mov eax, [rel camera_y]
    sub edi, eax

    ; Couleur : flash blanc si hit_timer actif
    mov esi, ebp
    lea rax, [rel platforms_hit_timer]
    movzx ecx, byte [rax + r12]
    test ecx, ecx
    jz .no_flash
    test ecx, 4
    jz .no_flash
    mov esi, 0x00FFFFFF
.no_flash:

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
    mov [rdx + rax*4], esi

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
