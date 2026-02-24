BITS 64
DEFAULT REL

; bridge NASM -> C (Win64 ABI)
; shadow space : 32 bytes obligatoires avant tout call

global wrap_perlin2d    ; (ecx=x_int, edx=y_int) -> eax [-127,+127]
global wrap_plat_freq   
global wrap_sin         

extern helper_perlin2d
extern helper_plat_freq
extern helper_sin

section .data
d_scale127  dq 127.0

section .text

wrap_perlin2d:
    sub rsp, 56            

    movsxd rax, ecx
    cvtsi2sd xmm0, rax
    movsxd rax, edx
    cvtsi2sd xmm1, rax
    call helper_perlin2d   

    mulsd xmm0, [rel d_scale127]
    cvttsd2si eax, xmm0
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

wrap_plat_freq:
    sub rsp, 40
    call helper_plat_freq
    add rsp, 40
    ret

wrap_sin:
    sub rsp, 40
    call helper_sin
    add rsp, 40
    ret
