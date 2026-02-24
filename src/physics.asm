BITS 64
DEFAULT REL

global physics_init
global physics_update
global game_over
global vel_y

extern player_y
extern player_x
extern camera_y
extern audio_post_cmd

%define CMD_PLAY_JUMP 1
%define SCREEN_H 600

section .data
gravity     dq 0.5
jump_force  dq -12.0
floor_y_f   dq 520.0
zero_f      dq 0.0

section .bss
vel_y       resq 1
game_over   resd 1

section .text

physics_init:
    mov rax, [rel zero_f]
    mov [rel vel_y], rax
    mov dword [rel game_over], 0
    ret

physics_update:
    sub rsp, 40

    mov eax, [rel game_over]
    test eax, eax
    jnz .already_over

    ; vel_y += gravity, player_y += vel_y
    movsd xmm0, [rel vel_y]
    addsd xmm0, [rel gravity]
    movsd [rel vel_y], xmm0
    cvttsd2si eax, xmm0
    add eax, [rel player_y]
    mov [rel player_y], eax

    cmp eax, SCREEN_H
    jg .game_over

    ; sol fixe uniquement au debut (camera_y = 0)
    mov eax, [rel camera_y]
    test eax, eax
    jnz .done

    mov eax, [rel player_y]
    cvtsi2sd xmm0, eax
    movsd xmm1, [rel floor_y_f]
    ucomisd xmm1, xmm0
    jae .done

    mov dword [rel player_y], 520
    mov rax, [rel jump_force]
    mov [rel vel_y], rax
    mov ecx, CMD_PLAY_JUMP
    call audio_post_cmd

.done:
    add rsp, 40
    ret

.game_over:
    mov dword [rel game_over], 1
    add rsp, 40
    ret

.already_over:
    add rsp, 40
    ret
