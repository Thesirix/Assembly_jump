BITS 64
DEFAULT REL

; =============================================================
; helper.asm — Bridge NASM x86-64 -> C (helper.c)
;
; Pattern identique au bridge ASM <-> Objective-C du projet CX
; (Mandelbrot AArch64 + ObjC), ici adapté Windows x64 :
;   CX  : bl/blt instructions d'appel ObjC runtime
;   Ici : call standard Win64 ABI vers helper.obj (cl.exe)
;
; Convention Win64 :
;   Doubles en xmm0..xmm3, entiers en rcx/rdx/r8/r9
;   Retour double dans xmm0, retour entier dans rax
;   Shadow space : 32 bytes TOUJOURS avant tout call
; =============================================================

global wrap_perlin2d    ; (ecx=x_int, edx=y_int) -> eax [-127,+127]
global wrap_plat_freq   ; (ecx=index)             -> xmm0 (double)
global wrap_sin         ; (xmm0=angle radians)    -> xmm0 (double)

extern helper_perlin2d
extern helper_plat_freq
extern helper_sin

section .data
; Constantes de mise à l'échelle pour les retours doubles
d_scale127  dq 127.0           ; Perlin : [-1.0,+1.0] -> [-127,+127]
d_scale255  dq 255.0           ; Smooth log : [0.0,255.0] -> [0,255]

section .text

; =============================================================
; wrap_perlin2d — Convertit 2 entiers en doubles, appelle C,
;                 retourne entier signé [-127, +127]
;
; Entrée : ecx = x_int, edx = y_int
; Sortie : eax = bruit Perlin 2D [-127, +127]
;
; Ce wrapper réalise le même rôle que le bridge ObjC dans CX :
; conversion de types, appel inter-langage, récupération résultat.
;
; Alignement RSP :
;   0 pushes + sub 56 = 56. (8 - 56) mod 16 = 0. OK
;   (56 = 32 shadow + 2*8 locals pour les doubles)
; =============================================================
wrap_perlin2d:
    sub rsp, 56                     ; shadow 32 + 2 qwords locaux

    ; --- Convertir ecx (int) -> double dans xmm0 ---
    ; Win64 ABI : premier arg double dans xmm0
    movsxd rax, ecx                 ; sign-extend ecx -> rax
    cvtsi2sd xmm0, rax              ; xmm0 = (double)x

    ; --- Convertir edx (int) -> double dans xmm1 ---
    ; Win64 ABI : second arg double dans xmm1
    movsxd rax, edx                 ; sign-extend edx -> rax
    cvtsi2sd xmm1, rax              ; xmm1 = (double)y

    ; --- Appel C : helper_perlin2d(x, y) ---
    ; Retour dans xmm0 (double dans [-1.0, +1.0])
    call helper_perlin2d

    ; --- Convertir résultat double -> entier [-127, +127] ---
    mulsd xmm0, [rel d_scale127]   ; xmm0 = résultat * 127.0
    cvttsd2si eax, xmm0            ; eax = (int)xmm0 (troncature)

    ; Clamp [-127, +127]
    cmp eax, -127
    jge .min_ok
    mov eax, -127
.min_ok:
    cmp eax, 127
    jle .max_ok
    mov eax, 127
.max_ok:
    add rsp, 56
    ret

; =============================================================
; =============================================================
; wrap_plat_freq — Retourne la fréquence d'oscillation propre
;                  à une plateforme donnée (via bridge C)
;
; Entrée : ecx = index plateforme
; Sortie : xmm0 = fréquence (double)
;
; Alignement RSP :
;   0 pushes + sub 40 = 40. (8 - 40) mod 16 = 0. OK
; =============================================================
wrap_plat_freq:
    sub rsp, 40                     ; shadow space
    ; ecx = index → déjà en place pour Win64 (premier arg entier)
    call helper_plat_freq           ; retour dans xmm0 (double)
    add rsp, 40
    ret

; =============================================================
; wrap_sin — Calcule sin(angle) via la CRT C (élimine fsin x87)
;
; Entrée : xmm0 = angle (double, radians)
; Sortie : xmm0 = sin(angle) dans [-1.0, +1.0]
;
; xmm0 est déjà le premier argument flottant Win64 ABI.
; Le résultat double retourne dans xmm0 — aucune conversion.
;
; Alignement RSP :
;   0 pushes + sub 40 = 40. (8-40) mod 16 = 0. OK
; =============================================================
wrap_sin:
    sub rsp, 40                     ; shadow space
    ; xmm0 = angle → déjà en place pour Win64 (premier arg double)
    call helper_sin                 ; retour dans xmm0 (double)
    add rsp, 40
    ret