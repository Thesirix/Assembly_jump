BITS 64
DEFAULT REL

; =================================================================
; stars.asm — Parallax starfield background (3 layers)
; =================================================================

global stars_init
global stars_render

extern backbuffer
extern camera_y

%define SCREEN_W    800
%define SCREEN_H    600

%define LAYER0_COUNT  40
%define LAYER1_COUNT  30
%define LAYER2_COUNT  20
%define TOTAL_STARS   (LAYER0_COUNT + LAYER1_COUNT + LAYER2_COUNT)

; Star Y range — spread over a huge virtual space so they always visible
%define STAR_WORLD_H  50000

section .data

star_seed dd 31337

; Star colors per layer (dim → bright)
star_color0 dd 0x00555577      ; Dim blue-grey (distant)
star_color1 dd 0x008888AA      ; Medium blue
star_color2 dd 0x00CCCCFF      ; Bright white-blue (close)

section .bss

; Star positions: world-space X and Y
star_x      resd TOTAL_STARS
star_y      resd TOTAL_STARS

section .text

; ============================================================
; star_random — LCG for star generation
; Returns: eax = 0..32767
; ============================================================
star_random:
    push rbx
    mov eax, [rel star_seed]
    mov ebx, 1103515245
    imul eax, ebx
    add eax, 12345
    mov [rel star_seed], eax
    shr eax, 16
    and eax, 0x7FFF
    pop rbx
    ret

; ============================================================
; stars_init — Generate all star positions
; ============================================================
stars_init:
    push rbx
    push r12
    push r13
    sub rsp, 48

    ; Seed from rdtsc for variety
    rdtsc
    xor eax, 0xCAFEBABE
    mov [rel star_seed], eax

    lea r12, [rel star_x]
    lea r13, [rel star_y]
    xor ebx, ebx                   ; star index

.gen_loop:
    cmp ebx, TOTAL_STARS
    jge .done

    ; X = random() % SCREEN_W
    call star_random
    xor edx, edx
    mov ecx, SCREEN_W
    div ecx
    mov [r12 + rbx*4], edx

    ; Y = random() % STAR_WORLD_H (spread over large range)
    call star_random
    imul eax, eax, 3              ; Extend range
    xor edx, edx
    mov ecx, STAR_WORLD_H
    div ecx
    ; Make Y negative (stars are above start)
    neg edx
    mov [r13 + rbx*4], edx

    inc ebx
    jmp .gen_loop

.done:
    add rsp, 48
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; stars_render — Draw all 3 layers with parallax scrolling
; Called after clear_backbuffer, before platforms_render
; ============================================================
stars_render:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rsi
    sub rsp, 40

    lea rsi, [rel backbuffer]
    lea r14, [rel star_x]
    lea r15, [rel star_y]

    ; ---- LAYER 0 : distant, slow (camera_y / 8), 1×1 pixel ----
    xor ebx, ebx
    mov r12d, [rel camera_y]
    sar r12d, 3                     ; parallax divisor = 8
.layer0:
    cmp ebx, LAYER0_COUNT
    jge .start_layer1

    mov eax, [r15 + rbx*4]         ; world Y
    sub eax, r12d                   ; apply parallax scroll

    ; Wrap Y into screen space (modular)
    cdq
    mov ecx, SCREEN_H
    idiv ecx
    mov eax, edx
    ; Make positive
    test eax, eax
    jge .l0_pos
    add eax, SCREEN_H
.l0_pos:
    cmp eax, SCREEN_H
    jge .l0_next

    mov ecx, [r14 + rbx*4]         ; X
    cmp ecx, 0
    jl .l0_next
    cmp ecx, SCREEN_W
    jge .l0_next

    ; Plot 1×1 pixel
    imul eax, SCREEN_W
    add eax, ecx
    mov edx, [rel star_color0]
    mov [rsi + rax*4], edx

.l0_next:
    inc ebx
    jmp .layer0

    ; ---- LAYER 1 : medium, camera_y / 4, 2×2 pixel ----
.start_layer1:
    mov ebx, LAYER0_COUNT
    mov r12d, [rel camera_y]
    sar r12d, 2                     ; parallax divisor = 4
.layer1:
    cmp ebx, LAYER0_COUNT + LAYER1_COUNT
    jge .start_layer2

    mov eax, [r15 + rbx*4]
    sub eax, r12d

    cdq
    mov ecx, SCREEN_H
    idiv ecx
    mov eax, edx
    test eax, eax
    jge .l1_pos
    add eax, SCREEN_H
.l1_pos:
    cmp eax, SCREEN_H - 1
    jge .l1_next

    mov ecx, [r14 + rbx*4]
    cmp ecx, 0
    jl .l1_next
    cmp ecx, SCREEN_W - 1
    jge .l1_next

    ; Plot 2×2 pixel block
    mov r13d, eax                   ; save Y
    imul eax, SCREEN_W
    add eax, ecx
    mov edx, [rel star_color1]
    mov [rsi + rax*4], edx          ; (x, y)
    mov [rsi + rax*4 + 4], edx      ; (x+1, y)
    add eax, SCREEN_W
    mov [rsi + rax*4], edx          ; (x, y+1)
    mov [rsi + rax*4 + 4], edx      ; (x+1, y+1)

.l1_next:
    inc ebx
    jmp .layer1

    ; ---- LAYER 2 : close, fast (camera_y / 2), 3×3 pixel with glow ----
.start_layer2:
    mov ebx, LAYER0_COUNT + LAYER1_COUNT
    mov r12d, [rel camera_y]
    sar r12d, 1                     ; parallax divisor = 2
.layer2:
    cmp ebx, TOTAL_STARS
    jge .done

    mov eax, [r15 + rbx*4]
    sub eax, r12d

    cdq
    mov ecx, SCREEN_H
    idiv ecx
    mov eax, edx
    test eax, eax
    jge .l2_pos
    add eax, SCREEN_H
.l2_pos:
    ; CORRECTION ICI : Y doit être au moins 1, sinon Y-1 plantera le pointeur mémoire
    cmp eax, 1 
    jl .l2_next
    cmp eax, SCREEN_H - 2
    jge .l2_next

    mov ecx, [r14 + rbx*4]
    cmp ecx, 1
    jl .l2_next
    cmp ecx, SCREEN_W - 2
    jge .l2_next

    ; Plot 3×3 cross pattern (star shape)
    mov r13d, eax
    imul eax, SCREEN_W
    add eax, ecx
    mov edx, [rel star_color2]

    ; Center row: 3 pixels
    mov [rsi + rax*4 - 4], edx      ; (x-1, y)
    mov [rsi + rax*4], edx          ; (x, y)
    mov [rsi + rax*4 + 4], edx      ; (x+1, y)

    ; Row above: center pixel
    sub eax, SCREEN_W
    mov [rsi + rax*4], edx          ; (x, y-1)

    ; Row below: center pixel
    add eax, SCREEN_W
    add eax, SCREEN_W
    mov [rsi + rax*4], edx          ; (x, y+1)

.l2_next:
    inc ebx
    jmp .layer2

.done:
    add rsp, 40
    pop rsi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret