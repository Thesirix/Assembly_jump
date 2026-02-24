BITS 64
DEFAULT REL

global particles_update
global particles_render

; Données particules (définies dans platforms.asm, exportées via global)
extern part_x
extern part_y
extern part_vx
extern part_vy
extern part_life
extern part_color
extern part_grav_tick

extern backbuffer

%define SCREEN_W        800
%define SCREEN_H        600
%define MAX_PARTICLES   512

section .text

; ============================================================
; particles_update — SIMD SSE2 : 4 particules par itération
;
; Optimisations vs version scalaire originale :
;   - div par 3 (tick gravité) calculé UNE SEULE FOIS avant la boucle
;     → supprime 512 divisions entières par frame
;   - psubusb : décrémente 4 life bytes en 1 instruction (saturation à 0)
;   - paddd   : x+=vx et y+=vy pour 4 particules simultanément
;   - paddd   : vy+=gravité pour 4 particules (0 ou 1 selon le frame)
;   - Aucune branche par particule (les mortes restent à 0 via psubusb)
;   - Gain estimé : ×4 vs scalaire
; ============================================================
particles_update:
    push rbx
    push r12

    ; --- Gravité : calculé UNE FOIS pour toutes les particules ---
    inc dword [rel part_grav_tick]
    mov eax, [rel part_grav_tick]
    xor edx, edx
    mov ecx, 3
    div ecx                         ; edx = tick % 3

    ; xmm5 = vecteur gravité dwords [grav,grav,grav,grav]
    ; grav = 1 si frame de gravité (tick%3==0), 0 sinon
    xor ecx, ecx
    test edx, edx
    setz cl                         ; cl = 1 si frame gravité
    movd xmm5, ecx
    pshufd xmm5, xmm5, 0           ; broadcast → [grav,grav,grav,grav]

    ; xmm7 = [1,1,...,1] (16 bytes) pour psubusb
    ; psubusb fait : life[k] = max(life[k]-1, 0) → particules mortes restent à 0
    pcmpeqb xmm7, xmm7             ; xmm7 = 0xFF×16
    psrlw   xmm7, 15               ; words = [0x0001 × 8]
    packuswb xmm7, xmm7            ; bytes = [0x01 × 16]

    ; Pré-charger les adresses de base (une fois avant la boucle)
    lea r8,  [rel part_x]
    lea r9,  [rel part_vx]
    lea r10, [rel part_y]
    lea r11, [rel part_vy]
    lea rbx, [rel part_life]

    xor r12d, r12d                  ; i = 0

.loop4:
    cmp r12d, MAX_PARTICLES
    jge .done

    ; --- life[i..i+3] -= 1 avec saturation (0-1 = 0, pas d'underflow) ---
    movd xmm6, dword [rbx + r12]   ; 4 bytes life dans xmm6 low dword
    psubusb xmm6, xmm7             ; life[k] = max(life[k]-1, 0)
    movd dword [rbx + r12], xmm6   ; stocker 4 bytes mis à jour

    ; --- x[i..i+3] += vx[i..i+3] (4 dwords simultanément) ---
    movdqu xmm0, [r8  + r12*4]    ; [x0, x1, x2, x3]
    movdqu xmm1, [r9  + r12*4]    ; [vx0, vx1, vx2, vx3]
    paddd  xmm0, xmm1
    movdqu [r8  + r12*4], xmm0

    ; --- y[i..i+3] += vy[i..i+3] ---
    movdqu xmm2, [r10 + r12*4]    ; [y0, y1, y2, y3]
    movdqu xmm3, [r11 + r12*4]    ; [vy0, vy1, vy2, vy3]
    paddd  xmm2, xmm3
    movdqu [r10 + r12*4], xmm2

    ; --- vy[i..i+3] += gravité (0 ou 1, calculé une seule fois avant la boucle) ---
    paddd  xmm3, xmm5              ; vy += 0 ou 1
    movdqu [r11 + r12*4], xmm3

    add r12d, 4
    jmp .loop4

.done:
    pop r12
    pop rbx
    ret


; ============================================================
; particles_render — Taille adaptative (3×3→1×1) + fade sans division
;
; Optimisations vs version scalaire originale :
;   - fade = life*17>>2 au lieu de life*255÷60 (exact, 0 div)
;   - R/G/B fade : component*fade>>8 au lieu de ÷255 (erreur <0.4%, invisible)
;   - Économie : 4 divisions entières → 0 par particule vivante
;   - Gain estimé : ×5-8 sur le calcul de couleur
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
    mov r13d, [rbx + r12*4]        ; r13d = x
    lea rbx, [rel part_y]
    mov r14d, [rbx + r12*4]        ; r14d = y

    ; Bounds check conservateur (3×3 max)
    cmp r13d, 0
    jl .next
    cmp r13d, SCREEN_W - 3
    jge .next
    cmp r14d, 0
    jl .next
    cmp r14d, SCREEN_H - 3
    jge .next

    ; --- Couleur originale ---
    lea rbx, [rel part_color]
    mov r15d, [rbx + r12*4]

    ; --- Fade factor : life*17>>2 (exact pour life∈[0,60], aucune division) ---
    ; Preuve : 60*17=1020, 1020>>2=255 ✓   30*17=510, 510>>2=127 ✓
    lea rbx, [rel part_life]
    movzx eax, byte [rbx + r12]    ; eax = life
    imul eax, 17
    shr eax, 2                      ; fade ∈ [0, 255]
    mov ebx, eax                    ; ebx = fade

    ; --- R : (R * fade) >> 8  (≈ R*fade/255, erreur max 1 niveau sur 255) ---
    mov eax, r15d
    and eax, 0xFF
    imul eax, ebx
    shr eax, 8
    mov esi, eax                    ; R final

    ; --- G : (G * fade) >> 8 ---
    mov eax, r15d
    shr eax, 8
    and eax, 0xFF
    imul eax, ebx
    shr eax, 8
    shl eax, 8
    or esi, eax                     ; |= G<<8

    ; --- B : (B * fade) >> 8 ---
    mov eax, r15d
    shr eax, 16
    and eax, 0xFF
    imul eax, ebx
    shr eax, 8
    shl eax, 16
    or esi, eax                     ; |= B<<16

    ; --- Adresse de base dans le backbuffer ---
    mov eax, r14d
    imul eax, SCREEN_W
    add eax, r13d                   ; eax = y*800 + x

    ; --- Taille adaptative selon life ---
    lea rbx, [rel part_life]
    movzx ecx, byte [rbx + r12]

    cmp ecx, 40
    jg .size_3x3                    ; life > 40 → 3×3
    cmp ecx, 20
    jg .size_2x2                    ; life > 20 → 2×2
    jmp .size_1x1                   ; life ≤ 20 → 1×1

.size_3x3:
    ; 3 lignes × 3 colonnes = 9 pixels
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
    ; 2 lignes × 2 colonnes = 4 pixels
    mov [rbp + rax*4    ], esi
    mov [rbp + rax*4 + 4], esi
    lea edx, [eax + SCREEN_W]
    mov [rbp + rdx*4    ], esi
    mov [rbp + rdx*4 + 4], esi
    jmp .next

.size_1x1:
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
