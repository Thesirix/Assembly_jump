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
global wrap_smooth_log  ; (ecx=val_int)           -> eax [0,255]
global wrap_plat_freq   ; (ecx=index)             -> xmm0 (double)

extern helper_perlin2d
extern helper_smooth_log
extern helper_plat_freq

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
; wrap_smooth_log — Passe une valeur entière par log(log(x))
;                   Technique de smooth coloring du Mandelbrot
;
; Entrée : ecx = valeur entière (ex: abs(camera_y))
; Sortie : eax = résultat [0, 255]
;
; Alignement RSP :
;   0 pushes + sub 40 = 40. (8 - 40) mod 16 = 0. OK
; =============================================================
wrap_smooth_log:
    sub rsp, 40                     ; shadow space

    ; --- Convertir ecx (int) -> double dans xmm0 ---
    movsxd rax, ecx
    cvtsi2sd xmm0, rax              ; xmm0 = (double)val

    ; --- Appel C : helper_smooth_log(val) ---
    ; Retour dans xmm0 (double dans [0.0, 255.0])
    call helper_smooth_log

    ; --- Convertir double -> entier [0, 255] ---
    cvttsd2si eax, xmm0

    ; Clamp [0, 255]
    cmp eax, 0
    jge .pos
    xor eax, eax
.pos:
    cmp eax, 255
    jle .done
    mov eax, 255
.done:
    add rsp, 40
    ret

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