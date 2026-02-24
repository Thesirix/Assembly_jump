BITS 64
DEFAULT REL


extern waveOutOpen, waveOutPrepareHeader, waveOutWrite
extern waveOutReset, waveOutClose, waveOutUnprepareHeader
extern GlobalAlloc, RtlMoveMemory


global Audio_Init
global Audio_Cleanup
global audio_play_jump
global audio_update_music
global audio_stop_music


%include "kick_data.inc"

; --- CONSTANTES SON DE SAUT ---
%define JUMP_RATE       44100
%define JUMP_SAMPLES    8000
%define JUMP_HDR_SIZE   44
%define JUMP_TOTAL      (JUMP_HDR_SIZE + JUMP_SAMPLES)

section .data

    ; ---- Format musique de fond ----
    wfx:
        dw 1
        dw WavChannels
        dd WavRate
        dd WavRate * WavChannels * 2
        dw WavChannels * 2
        dw 16
        dw 0

    TotalBufferSize equ KickSizeBytes * 4


    wfx_jump:
        dw 1            
        dw 1            
        dd JUMP_RATE
        dd JUMP_RATE  
        dw 1            
        dw 8           
        dw 0

    ; ---- Constantes FPU pour synthèse "bouing" ----
    j_start_freq    dq 0.12
    j_freq_accel    dq 0.00006
    j_max_vol       dq 110.0
    j_center        dq 128.0
    j_decay         dq 0.9995

section .bss
    ; ---- Musique de fond ----
    hWaveOut        resq 1
    pBuffer         resq 1
    waveHdr         resb 64
    music_playing   resd 1

    ; ---- Son de saut ----
    hWaveOut_jump   resq 1
    waveHdr_jump    resb 64
    jump_buffer     resb JUMP_TOTAL

    ; ---- Variables FPU temporaires (synthèse) ----
    j_angle         resq 1
    j_freq          resq 1
    j_vol           resq 1
    j_temp          resq 1

section .text

%macro zero_header64 1
    lea     rdi, [rel %1]
    xor     eax, eax
    mov     rcx, 8
%%loop:
    mov     qword [rdi + rcx*8 - 8], 0
    dec     rcx
    jnz     %%loop
%endmacro


start_music_playback:
    push    rbx
    sub     rsp, 40

    zero_header64 waveHdr

    lea     rbx, [rel waveHdr]
    mov     rax, [rel pBuffer]
    mov     [rbx],          rax
    mov     dword [rbx+8],  TotalBufferSize
    mov     dword [rbx+24], 12      
    mov     dword [rbx+28], -1     

    mov     rcx, [rel hWaveOut]
    mov     rdx, rbx
    mov     r8,  48
    call    waveOutPrepareHeader

    mov     rcx, [rel hWaveOut]
    lea     rdx, [rel waveHdr]
    mov     r8,  48
    call    waveOutWrite

    mov     dword [rel music_playing], 1

    add     rsp, 40
    pop     rbx
    ret


Audio_Init:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48
    push    rbx
    push    rdi

    ; --- 1. SYNTHESE DU SON DE SAUT ---
    lea rdi, [rel jump_buffer]
    mov dword [rdi],    0x46464952
    mov dword [rdi+4],  JUMP_TOTAL - 8
    mov dword [rdi+8],  0x45564157
    mov dword [rdi+12], 0x20746d66
    mov dword [rdi+16], 16
    mov word  [rdi+20], 1
    mov word  [rdi+22], 1
    mov dword [rdi+24], JUMP_RATE
    mov dword [rdi+28], JUMP_RATE
    mov word  [rdi+32], 1
    mov word  [rdi+34], 8
    mov dword [rdi+36], 0x61746164
    mov dword [rdi+40], JUMP_SAMPLES

    lea rdi, [rel jump_buffer + JUMP_HDR_SIZE]
    mov rcx, JUMP_SAMPLES

    finit
    fldz
    fstp qword [rel j_angle]
    fld  qword [rel j_start_freq]
    fstp qword [rel j_freq]
    fld  qword [rel j_max_vol]
    fstp qword [rel j_vol]

.synth_loop:
    fld  qword [rel j_angle]
    fsin
    fld  qword [rel j_vol]
    fmulp st1, st0
    fld  qword [rel j_center]
    faddp st1, st0
    fistp qword [rel j_temp]
    mov  al, byte [rel j_temp]
    mov  [rdi], al

    fld  qword [rel j_angle]
    fadd qword [rel j_freq]
    fstp qword [rel j_angle]

    fld  qword [rel j_freq]
    fadd qword [rel j_freq_accel]
    fstp qword [rel j_freq]

    fld  qword [rel j_vol]
    fmul qword [rel j_decay]
    fstp qword [rel j_vol]

    inc  rdi
    dec  rcx
    jnz  .synth_loop

    finit

    ; --- . ALLOCATION MUSIQUE DE FOND ---
    mov     rcx, 0x0040
    mov     rdx, TotalBufferSize
    call    GlobalAlloc
    test    rax, rax
    jz      .Fail
    mov     [rel pBuffer], rax

    mov     rdi, rax
    mov     rbx, 4
.fill_loop:
    mov     rcx, rdi
    lea     rdx, [KickData]
    mov     r8,  KickSizeBytes
    push    rdi
    push    rbx
    sub     rsp, 32
    call    RtlMoveMemory
    add     rsp, 32
    pop     rbx
    pop     rdi
    add     rdi, KickSizeBytes
    dec     rbx
    jnz     .fill_loop

    ; ---  DEVICE MUSIQUE ---
    lea     rcx, [rel hWaveOut]
    mov     rdx, -1
    lea     r8,  [rel wfx]
    xor     r9,  r9
    mov     qword [rsp+32], 0
    mov     qword [rsp+40], 0
    call    waveOutOpen
    test    rax, rax
    jnz     .Fail

    call    start_music_playback

    ; ---  DEVICE SON DE SAUT (handle séparé) ---
    lea     rcx, [rel hWaveOut_jump]
    mov     rdx, -1
    lea     r8,  [rel wfx_jump]
    xor     r9,  r9
    mov     qword [rsp+32], 0
    mov     qword [rsp+40], 0
    call    waveOutOpen

.Fail:
    pop     rdi
    pop     rbx
    mov     rsp, rbp
    pop     rbp
    ret


Audio_Cleanup:
    sub     rsp, 40

    mov     rcx, [rel hWaveOut]
    test    rcx, rcx
    jz      .cleanup_jump
    call    waveOutReset
    mov     rcx, [rel hWaveOut]
    lea     rdx, [rel waveHdr]
    mov     r8,  48
    call    waveOutUnprepareHeader
    mov     rcx, [rel hWaveOut]
    call    waveOutClose
    mov     qword [rel hWaveOut], 0

.cleanup_jump:
    mov     rcx, [rel hWaveOut_jump]
    test    rcx, rcx
    jz      .done
    call    waveOutReset
    mov     rcx, [rel hWaveOut_jump]
    lea     rdx, [rel waveHdr_jump]
    mov     r8,  48
    call    waveOutUnprepareHeader
    mov     rcx, [rel hWaveOut_jump]
    call    waveOutClose
    mov     qword [rel hWaveOut_jump], 0

.done:
    add     rsp, 40
    ret


audio_stop_music:
    sub     rsp, 40

    cmp     dword [rel music_playing], 0
    je      .done

    mov     rcx, [rel hWaveOut]
    test    rcx, rcx
    jz      .done
    call    waveOutReset

    mov     rcx, [rel hWaveOut]
    lea     rdx, [rel waveHdr]
    mov     r8,  48
    call    waveOutUnprepareHeader

    mov     dword [rel music_playing], 0

.done:
    add     rsp, 40
    ret


audio_update_music:
    sub     rsp, 40

    cmp     dword [rel music_playing], 1
    je      .done

    call    start_music_playback

.done:
    add     rsp, 40
    ret


; reset -> unprepare -> zero -> prepare -> write a chaque appel
audio_play_jump:
    push    rbx
    push    rdi
    sub     rsp, 40

    mov     rbx, [rel hWaveOut_jump]
    test    rbx, rbx
    jz      .done

    mov     rcx, rbx
    call    waveOutReset

    mov     rcx, rbx
    lea     rdx, [rel waveHdr_jump]
    mov     r8,  48
    call    waveOutUnprepareHeader

    zero_header64 waveHdr_jump

    lea     rdi, [rel waveHdr_jump]
    lea     rax, [rel jump_buffer]
    mov     [rdi],         rax
    mov     dword [rdi+8], JUMP_TOTAL

    mov     rcx, rbx
    mov     rdx, rdi
    mov     r8,  48
    call    waveOutPrepareHeader

    mov     rcx, rbx
    lea     rdx, [rel waveHdr_jump]
    mov     r8,  48
    call    waveOutWrite

.done:
    add     rsp, 40
    pop     rdi
    pop     rbx
    ret