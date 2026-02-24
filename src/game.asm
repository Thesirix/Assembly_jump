BITS 64
DEFAULT REL

global game_init
global game_update

extern physics_init
extern physics_update
extern input_update
extern platforms_init
extern platforms_update
extern scroll_init
extern scroll_update
extern score_init
extern score_update
extern audio_post_cmd
extern player_y
extern player_x
extern game_over

%define CMD_UPDATE_MUSIC 2
%define CMD_STOP_MUSIC   3

section .text

game_init:
    push rbx
    sub rsp, 32

    mov dword [rel player_x], 380
    mov dword [rel player_y], 500
    call physics_init
    call scroll_init
    call platforms_init
    call score_init
    mov ecx, CMD_STOP_MUSIC
    call audio_post_cmd

    add rsp, 32
    pop rbx
    ret

game_update:
    push rbx
    sub rsp, 32

    call input_update
    call physics_update

    mov eax, [rel game_over]
    cmp eax, 1
    je .stop_sound

    call platforms_update
    call scroll_update
    call score_update
    mov ecx, CMD_UPDATE_MUSIC
    call audio_post_cmd

    add rsp, 32
    pop rbx
    ret

.stop_sound:
    mov ecx, CMD_STOP_MUSIC
    call audio_post_cmd
    add rsp, 32
    pop rbx
    ret
