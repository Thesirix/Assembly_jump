default rel
bits 64

; --- EXPORTS ---
global Audio_Init
global Audio_Cleanup

; --- IMPORTS ---
extern waveOutOpen, waveOutPrepareHeader, waveOutWrite, waveOutReset, waveOutClose
extern GlobalAlloc, RtlMoveMemory

; --- INCLUSION DONNÉES SON ---
%include "kick_data.inc"

section .data
    wfx:
        dw 1                    
        dw WavChannels          
        dd WavRate              
        dd WavRate * WavChannels * 2 
        dw WavChannels * 2      
        dw 16                   
        dw 0                    
    
    TotalBufferSize equ KickSizeBytes * 4

section .bss
    hWaveOut     resq 1
    pBuffer      resq 1
    waveHdr      resb 64

section .text

; =================================================================
; Audio_Init : Alloue la mémoire, copie le son, lance la lecture
; =================================================================
Audio_Init:
    ; Prologue standard
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48         ; Espace de travail safe
    push    rbx
    push    rdi

    ; 1. Allocation
    mov     rcx, 0x0040     ; GPTR
    mov     rdx, TotalBufferSize
    call    GlobalAlloc
    test    rax, rax
    jz      .Fail
    mov     [pBuffer], rax

    ; 2. Copie (4 boucles)
    mov     rdi, rax
    mov     rbx, 4
.FillLoop:
    mov     rcx, rdi
    lea     rdx, [KickData]
    mov     r8, KickSizeBytes
    push    rdi             ; Sauvegarde registres volatils
    push    rbx
    sub     rsp, 32
    call    RtlMoveMemory
    add     rsp, 32
    pop     rbx
    pop     rdi
    add     rdi, KickSizeBytes
    dec     rbx
    jnz     .FillLoop

    ; 3. Open
    lea     rcx, [hWaveOut]
    mov     rdx, -1
    lea     r8, [wfx]
    xor     r9, r9
    mov     qword [rsp+32], 0
    mov     qword [rsp+40], 0
    call    waveOutOpen
    test    rax, rax
    jnz     .Fail

    ; 4. Prepare & Play
    lea     rbx, [waveHdr]
    mov     rax, [pBuffer]
    mov     [rbx], rax
    mov     dword [rbx+8], TotalBufferSize
    mov     dword [rbx+24], 12  ; LOOP
    mov     dword [rbx+28], -1  ; INFINI
    
    mov     rcx, [hWaveOut]
    mov     rdx, rbx
    mov     r8, 48
    call    waveOutPrepareHeader

    mov     rcx, [hWaveOut]
    lea     rdx, [waveHdr]
    mov     r8, 48
    call    waveOutWrite

.Fail:
    pop     rdi
    pop     rbx
    mov     rsp, rbp
    pop     rbp
    ret

; =================================================================
; Audio_Cleanup : Arrête tout
; =================================================================
Audio_Cleanup:
    sub     rsp, 40
    mov     rcx, [hWaveOut]
    test    rcx, rcx
    jz      .Done
    call    waveOutReset
    mov     rcx, [hWaveOut]
    call    waveOutClose
.Done:
    add     rsp, 40
    ret