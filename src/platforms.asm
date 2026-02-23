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

; Import du bridge C (helper.asm -> helper.c)
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
%define MAX_PARTICLES   512         ; AUGMENTÉ : 32*16 = 512 slots particules

; ============================================================
section .data
; ============================================================
rand_seed dd 12345

; vel_y est maintenant double64 (resq dans physics.asm)
; bounce_vel doit aussi être double64 pour la cohérence
bounce_vel dq -12.0             ; double64 — même taille que vel_y

; Table de permutation Perlin 1D (256 entrées, Fisher-Yates)
perlin_perm:
    times 256 db 0

; --- Constantes FPU oscillation plateformes mobiles ---
fpu_base_freq   dd 0.008        ; Fréquence de base (ralentie)
fpu_desync      dd 0.7          ; Décalage de phase par index (désynchronisation)
fpu_40          dd 40.0         ; Amplitude en pixels

; Compteur animation plateformes mobiles
anim_tick dd 0

; --- Marges pour arrondir les bords des plateformes (PLATFORM_H = 12) ---
; Coupe 4 pixels au sommet, puis 2, puis 1, puis droit, et pareil en bas.
plat_margins db 4, 2, 1, 0, 0, 0, 0, 0, 0, 1, 2, 4

; ============================================================
section .bss
; ============================================================
platforms_x      resd MAX_PLATFORMS
platforms_y      resd MAX_PLATFORMS
platforms_active resb MAX_PLATFORMS

; Plateformes mobiles (flag, 20% aléatoire)
platforms_mobile resb MAX_PLATFORMS
platforms_base_x resd MAX_PLATFORMS

; Timer de flash visuel (cosmétique seulement)
platforms_hit_timer resb MAX_PLATFORMS

highest_platform_y resd 1
highest_platform_x resd 1

; Couleur HSV des plateformes (BGR32)
platform_color resd 1

; --- Particules de désintégration (MAX_PARTICLES = 512) ---
part_x      resd MAX_PARTICLES
part_y      resd MAX_PARTICLES
part_vx     resd MAX_PARTICLES
part_vy     resd MAX_PARTICLES
part_life   resb MAX_PARTICLES
part_color  resd MAX_PARTICLES

; Compteur de gravité douce des particules (1 incrément tous les 3 frames)
part_grav_tick resd 1

; Temporaire SSE2 (cvttsd2si → offset entier)
fpu_temp resd 1

; Temporaire pour le bridge wrap_plat_freq (double retourné dans xmm0)
fpu_freq_tmp resq 1

; Temporaire pour sauvegarder l'index particule entre les appels random
emit_save_idx resd 1

; ============================================================
section .text
; ============================================================

; ============================================================
; random — LCG (Linear Congruential Generator)
; Retourne : eax = 0..32767
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
; perlin_init — Initialise la table de permutation 1D
; Algorithme Fisher-Yates depuis rdtsc (aléatoire à chaque démarrage)
; 2 pushes + sub 40 = 56. 56 mod 16 = 8. OK
; ============================================================
perlin_init:
    push rbx
    push r12
    sub rsp, 40

    ; Remplir 0..255
    lea rbx, [rel perlin_perm]
    xor ecx, ecx
.fill:
    mov byte [rbx + rcx], cl
    inc ecx
    cmp ecx, 256
    jl .fill

    ; Mélange Fisher-Yates
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

; ============================================================
; noise1d — Bruit de Perlin 1D entier (table perlin_perm)
; Entrée : ecx = coordonnée
; Sortie : eax = [-128, +127]
; ============================================================
noise1d:
    push rbx
    push r12
    push r13

    mov eax, ecx
    mov r12d, eax
    and r12d, 0xFF              ; partie fractionnaire (0..255)

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

    ; Interpolation linéaire entière
    sub eax, ecx
    imul eax, r12d
    sar eax, 8
    add eax, ecx               ; résultat = grad0 + frac*(grad1-grad0)

    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; hsv_to_rgb — Conversion HSV -> RGB entier pur
; Entrée : ecx=hue(0..359), edx=sat(0..255), r8d=val(0..255)
; Retour  : eax = 0x00BBGGRR
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

; ============================================================
; platforms_update
; 0 pushes + sub 40 = 40. 40 mod 16 = 8. OK
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

    mov ecx, edx               ; hue = (camera_y/50) mod 360
    mov edx, 200               ; saturation
    mov r8d, 220               ; valeur
    call hsv_to_rgb
    mov [rel platform_color], eax

    add rsp, 32
    pop rbx
    ret

; ============================================================
; platforms_hit_timer_update — Décrémenter timers flash visuel
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
.next:
    inc r12d
    jmp .loop
.done:
    pop r12
    pop rbx
    ret

; ============================================================
; platforms_update_mobile — Oscillation SSE2 + sin via bridge C
; ============================================================
platforms_update_mobile:
    push rbx
    push r12
    sub rsp, 56

    xor r12d, r12d

.loop:
    cmp r12d, MAX_PLATFORMS
    jge .done

    ; Vérifier si cette plateforme est mobile et active
    lea rbx, [rel platforms_mobile]
    cmp byte [rbx + r12], 0
    je .next

    lea rbx, [rel platforms_active]
    cmp byte [rbx + r12], 0
    je .next

    ; --- Obtenir la fréquence propre via bridge C ---
    ; wrap_plat_freq(index) -> xmm0 (double)
    mov ecx, r12d
    call wrap_plat_freq             ; xmm0 = fréquence de cette plateforme
    ; Sauvegarder la fréquence en mémoire (double64 → fpu_freq_tmp)
    movsd [rel fpu_freq_tmp], xmm0

    ; --- SSE2 : angle = anim_tick * freq + index * 0.7 ---
    ; Partie 1 : anim_tick * freq (freq = double64 dans fpu_freq_tmp)
    mov eax, [rel anim_tick]
    cvtsi2sd xmm0, eax                  ; xmm0 = (double)anim_tick
    mulsd xmm0, [rel fpu_freq_tmp]      ; xmm0 = anim_tick * freq

    ; Partie 2 : index * 0.7 (désynchronisation par plateforme)
    cvtsi2sd xmm1, r12d                 ; xmm1 = (double)index
    movss xmm2, [rel fpu_desync]        ; xmm2[31:0] = 0.7 (float32)
    cvtss2sd xmm2, xmm2                 ; xmm2 = 0.7 (double64)
    mulsd xmm1, xmm2                    ; xmm1 = index * 0.7
    addsd xmm0, xmm1                    ; xmm0 = angle = tick*freq + index*0.7

    ; sin(angle) via bridge C (remplace fsin x87)
    call wrap_sin                       ; xmm0 = sin(angle) dans [-1.0, +1.0]

    ; Multiplier par amplitude (40 pixels)
    movss xmm1, [rel fpu_40]            ; xmm1[31:0] = 40.0 (float32)
    cvtss2sd xmm1, xmm1                 ; xmm1 = 40.0 (double64)
    mulsd xmm0, xmm1                    ; xmm0 = sin(angle) * 40

    ; Convertir en entier par troncature (remplace fistp)
    cvttsd2si eax, xmm0                 ; eax = (int)(sin(angle)*40)
    mov [rel fpu_temp], eax             ; fpu_temp = offset pixels

    ; Appliquer l'offset à la position de base
    lea rbx, [rel platforms_base_x]
    mov eax, [rbx + r12*4]
    add eax, [rel fpu_temp]

    ; Clamp [30, 690] (bords visibles, plateforme jamais collée aux murs)
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

; ============================================================
; platforms_cleanup_old — Supprimer les plateformes sorties du bas
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
; platforms_generate_new — Créer une plateforme si nécessaire
; ============================================================
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
    div ecx                     ; edx = random % 5
    lea rbx, [rel platforms_mobile]
    cmp edx, 0                  ; 1 chance sur 5 = 20%
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
; create_one_platform — LCG + biais Perlin 2D (via bridge C)
; ============================================================
create_one_platform:
    push r14
    push r15
    sub rsp, 56

    ; --- X : LCG random offset [-200, +200] centré sur highest_x ---
    call random
    xor edx, edx
    mov ecx, 400
    div ecx                     ; edx = random % 400
    sub edx, 200               ; offset dans [-200, +199]
    add edx, [rel highest_platform_x]

    ; --- Biais Perlin 2D via bridge C (wrap_perlin2d) ---
    mov dword [rsp+32], edx     ; sauvegarder X LCG brut (espace local, pas push)

    mov ecx, [rel highest_platform_y]
    sar ecx, 7                  ; / 128 → coordonnée Perlin Y
    mov edx, [rel highest_platform_x]
    sar edx, 7                  ; / 128 → coordonnée Perlin X
    call wrap_perlin2d          ; eax = bruit Perlin 2D double précision

    ; Réduire le biais à 25%
    sar eax, 2                  ; eax = biais Perlin 2D réduit [-32, +32]

    mov edx, dword [rsp+32]     ; récupérer X LCG (depuis espace local)
    add edx, eax               ; X final = LCG + petit biais Perlin 2D

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
    ; score >= 5000 : gap 55..100
    mov r14d, 55
    mov r15d, 45
    jmp .gen_gap
.easy:
    ; score < 1000 : gap 30..60
    mov r14d, 30
    mov r15d, 30
    jmp .gen_gap
.medium:
    ; score 1000..5000 : gap 40..80
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

    ; --- MOBILE : 20% aléatoire ---
    call random
    xor edx, edx
    mov ecx, 5
    div ecx                     ; edx = random % 5
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

; ============================================================
; SSE2 SIMD collision — 4 plateformes par itération
; ============================================================
platforms_check_collision:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 40

    ; vel_y est un double IEEE 754 64-bit : bit 63 = signe
    mov rax, [rel vel_y]            ; charger double64 en entier
    test rax, rax
    js .col_done                    ; bit 63 = 1 → négatif → monte
    jz .col_done                    ; zéro → pas de mouvement

    lea r14, [rel platforms_x]
    lea r15, [rel platforms_y]
    lea r13, [rel platforms_active]

    mov r8d, [rel player_x]
    mov r9d, [rel player_y]
    mov ebp, r9d
    add ebp, PLAYER_H

    ; Préparer les registres SIMD SSE2 pour la détection 4-wide
    mov eax, r8d
    add eax, PLAYER_W
    movd xmm1, eax
    pshufd xmm1, xmm1, 0           ; xmm1 = [player_x+W, ...]

    movd xmm2, r8d
    pshufd xmm2, xmm2, 0           ; xmm2 = [player_x, ...]

    movd xmm3, ebp
    pshufd xmm3, xmm3, 0           ; xmm3 = [player_bottom, ...]

    mov eax, [rel camera_y]
    movd xmm5, eax
    pshufd xmm5, xmm5, 0           ; xmm5 = [camera_y, ...]

    mov eax, PLATFORM_W
    movd xmm6, eax
    pshufd xmm6, xmm6, 0           ; xmm6 = [PLATFORM_W, ...]

    mov eax, 16
    movd xmm7, eax
    pshufd xmm7, xmm7, 0           ; xmm7 = [16, ...]

    xor r12d, r12d

.simd_loop:
    cmp r12d, MAX_PLATFORMS
    jge .col_done

    ; Charger 4 X et 4 Y de plateformes simultanément (SSE2 4-wide)
    movdqu xmm8, [r14 + r12*4]     ; xmm8 = [x0, x1, x2, x3]
    movdqu xmm9, [r15 + r12*4]     ; xmm9 = [y0, y1, y2, y3]
    psubd xmm9, xmm5               ; xmm9 = [y-cam, ...] = screen Y

    ; Test X overlap : player_x+W > plat_x
    movdqa xmm10, xmm1
    pcmpgtd xmm10, xmm8            ; xmm10 = mask (player_x+W > plat_x)

    ; Test X overlap : plat_x+W > player_x
    movdqa xmm11, xmm8
    paddd xmm11, xmm6
    pcmpgtd xmm11, xmm2            ; xmm11 = mask (plat_x+W > player_x)

    ; Test Y overlap haut : player_bottom+1 > plat_y
    movdqa xmm12, xmm3
    mov eax, 1
    movd xmm0, eax
    pshufd xmm0, xmm0, 0
    paddd xmm12, xmm0
    pcmpgtd xmm12, xmm9            ; xmm12 = mask

    ; Test Y overlap bas : plat_y+16+1 > player_bottom
    movdqa xmm0, xmm9
    paddd xmm0, xmm7
    mov eax, 1
    movd xmm4, eax
    pshufd xmm4, xmm4, 0
    paddd xmm0, xmm4
    pcmpgtd xmm0, xmm3             ; xmm0 = mask

    ; AND de tous les masques → collision si tous vrais
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
    ; Rebond : vel_y = -12.0 (double64)
    mov rax, [rel bounce_vel]       ; charger double64 -12.0
    mov [rel vel_y], rax            ; stocker double64

    ; Son de saut
    mov ecx, CMD_PLAY_JUMP
    call audio_post_cmd

    ; --- NOUVEAU : Désactiver la plateforme instantanément ---
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

; ============================================================
; emit_particles — Émettre 16 particules depuis la plateforme
; ============================================================
emit_particles:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48

    ; Position de la plateforme (en coordonnées écran)
    lea rax, [rel platforms_x]
    mov r13d, [rax + rbx*4]     ; r13d = plat_x
    lea rax, [rel platforms_y]
    mov r14d, [rax + rbx*4]     ; r14d = plat_y monde
    mov eax, [rel camera_y]
    sub r14d, eax               ; r14d = plat_y écran

    ; Couleur avec éclat initial (OR +0x30 sur chaque composante BGR)
    mov r15d, [rel platform_color]
    mov eax, r15d
    or eax, 0x00303030          ; éclat blanc partiel au départ
    ; Clamp chaque composante à 255
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
    mov r15d, eax               ; couleur avec éclat

    ; Chercher 16 slots libres
    xor r12d, r12d              ; compteur émissions (max 16)
    xor ecx, ecx               ; index particule (0..MAX_PARTICLES-1)

.find_part:
    cmp ecx, MAX_PARTICLES
    jge .emit_done
    cmp r12d, 16                ; CORRIGÉ : 16 particules (vs 8)
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
    mov ecx, 11                 ; 11 valeurs : 0..10
    div ecx
    sub edx, 5                 ; shift vers [-5, +5]
    mov ecx, [rel emit_save_idx]
    lea rax, [rel part_vx]
    mov [rax + rcx*4], edx

    ; vy = random(-8..-2)
    mov [rel emit_save_idx], ecx
    call random
    xor edx, edx
    mov ecx, 7                  ; 7 valeurs : 0..6
    div ecx
    sub edx, 8                 ; shift vers [-8, -2]
    mov ecx, [rel emit_save_idx]
    lea rax, [rel part_vy]
    mov [rax + rcx*4], edx

    ; life = 60
    lea rax, [rel part_life]
    mov byte [rax + rcx], 60

    ; Couleur avec éclat
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
; particles_update — Physique des particules
; ============================================================
particles_update:
    push rbx
    push r12
    xor r12d, r12d

    ; Incrémenter le compteur de gravité douce
    inc dword [rel part_grav_tick]

.loop:
    cmp r12d, MAX_PARTICLES
    jge .done

    lea rbx, [rel part_life]
    cmp byte [rbx + r12], 0
    je .next

    ; Décrémenter la durée de vie
    dec byte [rbx + r12]

    ; x += vx
    lea rbx, [rel part_vx]
    mov eax, [rbx + r12*4]
    lea rbx, [rel part_x]
    add [rbx + r12*4], eax

    ; y += vy
    lea rbx, [rel part_vy]
    mov eax, [rbx + r12*4]
    lea rbx, [rel part_y]
    add [rbx + r12*4], eax

    ; Gravité douce : vy += 1 seulement tous les 3 frames
    mov eax, [rel part_grav_tick]
    mov edx, 0
    mov ecx, 3
    div ecx
    test edx, edx
    jnz .next                   ; pas le bon frame → skip

    lea rbx, [rel part_vy]
    inc dword [rbx + r12*4]     ; vy += 1 (1 fois sur 3)

.next:
    inc r12d
    jmp .loop
.done:
    pop r12
    pop rbx
    ret

; ============================================================
; particles_render — Taille adaptative selon la durée de vie
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
    mov r13d, [rbx + r12*4]     ; r13d = x
    lea rbx, [rel part_y]
    mov r14d, [rbx + r12*4]     ; r14d = y

    ; Bounds check conservateur (3×3 max → marge 3)
    cmp r13d, 0
    jl .next
    cmp r13d, SCREEN_W - 3
    jge .next
    cmp r14d, 0
    jl .next
    cmp r14d, SCREEN_H - 3
    jge .next

    ; --- Calculer couleur avec fade ---
    lea rbx, [rel part_color]
    mov r15d, [rbx + r12*4]     ; couleur originale

    lea rbx, [rel part_life]
    movzx eax, byte [rbx + r12] ; eax = life (0..60)

    ; Intensité = life * 4 (max 240), divise chaque composante
    mov ecx, eax
    imul ecx, 255
    xor edx, edx
    mov ebx, 60
    div ebx                     ; eax = life*255/60 = [0,255]
    mov ebx, eax                ; ebx = fade factor [0,255]

    ; Appliquer le fade à chaque composante
    ; R
    mov eax, r15d
    and eax, 0xFF
    imul eax, ebx
    xor edx, edx
    mov ecx, 255
    div ecx
    mov esi, eax                ; R final

    ; G
    mov eax, r15d
    shr eax, 8
    and eax, 0xFF
    imul eax, ebx
    xor edx, edx
    mov ecx, 255
    div ecx
    shl eax, 8
    or esi, eax                 ; |= G<<8

    ; B
    mov eax, r15d
    shr eax, 16
    and eax, 0xFF
    imul eax, ebx
    xor edx, edx
    mov ecx, 255
    div ecx
    shl eax, 16
    or esi, eax                 ; |= B<<16

    ; --- Calculer adresse de base ---
    mov eax, r14d
    imul eax, SCREEN_W
    add eax, r13d               ; eax = y*800 + x

    ; --- Choisir la taille selon life ---
    lea rbx, [rel part_life]
    movzx ecx, byte [rbx + r12]

    cmp ecx, 40
    jg .size_3x3                ; life > 40 → 3×3
    cmp ecx, 20
    jg .size_2x2                ; life > 20 → 2×2
    jmp .size_1x1               ; life <= 20 → 1×1

.size_3x3:
    ; Dessiner 3 lignes × 3 colonnes = 9 pixels
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
    jmp .next

.size_2x2:
    ; Dessiner 2 lignes × 2 colonnes = 4 pixels
    mov [rbp + rax*4    ], esi
    mov [rbp + rax*4 + 4], esi
    lea edx, [eax + SCREEN_W]
    mov [rbp + rdx*4    ], esi
    mov [rbp + rdx*4 + 4], esi
    jmp .next

.size_1x1:
    ; Dessiner 1 pixel
    mov [rbp + rax*4], esi

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
; platforms_render — Rendu avec couleur HSV, forme arrondie
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

    mov ebx, [r14 + r12*4]     ; x plateforme
    mov edi, [r15 + r12*4]     ; y monde

    ; Convertir en Y écran
    mov eax, [rel camera_y]
    sub edi, eax

    ; Couleur : flash blanc si hit_timer actif (ne sera plus très visible à cause de la destruction, mais on garde par sécurité)
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

    ; --- NOUVEAU : Lire la marge pour créer la forme arrondie ---
    mov ecx, PLATFORM_H
    sub ecx, r8d                 ; ecx = index de la ligne courante (0 à 11)
    lea rax, [rel plat_margins]
    movzx r11d, byte [rax + rcx] ; r11d = marge pour cette ligne (ex: 4 pixels aux extrémités)

    mov r9d, PLATFORM_W
.x_loop:

    ; --- NOUVEAU : Ignorer les pixels situés dans la marge ---
    cmp r9d, r11d
    jle .skip_pixel              ; Skip les pixels sur le bord droit
    mov eax, PLATFORM_W
    sub eax, r11d
    cmp r9d, eax
    jg .skip_pixel               ; Skip les pixels sur le bord gauche

    ; --- Rendu classique du pixel ---
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