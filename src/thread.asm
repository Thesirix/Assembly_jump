BITS 64
DEFAULT REL

;  3 worker threads : Render, Audio, Platform Generation
; Render Thread   : GetDC → StretchDIBits(front_buffer) → ReleaseDC
; Audio Thread    : SPSC ring buffer → dispatch waveOut commands
; PlatGen Thread  : Pre-generate platforms into a pool (spinlock)


; --- Win32 API ---
extern CreateThread
extern CreateEventA
extern SetEvent
extern WaitForSingleObject
extern CloseHandle
extern ExitThread
extern Sleep
extern GetDC
extern ReleaseDC
extern StretchDIBits

; --- From main.asm ---
extern hwnd_main
extern front_buffer
extern bmi

; --- From audio.asm ---
extern audio_play_jump
extern audio_update_music
extern audio_stop_music

; --- From platforms.asm ---
extern highest_platform_y
extern highest_platform_x
extern rand_seed

global threads_init
global threads_shutdown
global audio_post_cmd
global platpool_consume
global platpool_request
global evt_frame_ready
global evt_render_done
global thread_shutdown


%define SCREEN_W        800
%define SCREEN_H        600
%define SRCCOPY         0x00CC0020
%define DIB_RGB_COLORS  0
%define INFINITE        0xFFFFFFFF
%define WAIT_TIMEOUT    258

%define AUDIO_CMD_RING_SIZE  64
%define AUDIO_CMD_MASK       63
%define CMD_PLAY_JUMP        1
%define CMD_UPDATE_MUSIC     2
%define CMD_STOP_MUSIC       3

%define PLATPOOL_SIZE        16

section .data
platgen_rand_seed dd 67890     

section .bss


h_render_thread     resq 1
h_audio_thread      resq 1
h_platgen_thread    resq 1
render_thread_id    resd 1
audio_thread_id     resd 1
platgen_thread_id   resd 1

evt_frame_ready     resq 1
evt_render_done     resq 1
evt_audio_cmd       resq 1
evt_platgen_needed  resq 1

thread_shutdown     resd 1

; --- Audio SPSC ring buffer ---
audio_cmd_ring      resd AUDIO_CMD_RING_SIZE
audio_ring_head     resd 1      ; Written by main thread only
audio_ring_tail     resd 1      ; Written by audio thread only

; --- Platform pre-generation pool ---
platpool_x          resd PLATPOOL_SIZE
platpool_y          resd PLATPOOL_SIZE
platpool_count      resd 1
platpool_write_idx  resd 1
platpool_read_idx   resd 1
platpool_lock       resd 1

section .text

platgen_random:
    push rbx
    mov eax, [rel platgen_rand_seed]
    mov ebx, 1103515245
    imul eax, ebx
    add eax, 12345
    mov [rel platgen_rand_seed], eax
    shr eax, 16
    and eax, 0x7FFF
    pop rbx
    ret

; Spinlock helpers
platpool_lock_acquire:
.spin:
    mov eax, 1
    xchg [rel platpool_lock], eax
    test eax, eax
    jz .got_it
    pause                           ; CPU hint: spin-wait
    jmp .spin
.got_it:
    ret

platpool_lock_release:
    mfence
    mov dword [rel platpool_lock], 0
    ret

threads_init:
    push rbx
    push r12
    push r13
    sub rsp, 48

   
    mov dword [rel thread_shutdown], 0
    mov dword [rel audio_ring_head], 0
    mov dword [rel audio_ring_tail], 0
    mov dword [rel platpool_count], 0
    mov dword [rel platpool_write_idx], 0
    mov dword [rel platpool_read_idx], 0
    mov dword [rel platpool_lock], 0

    mov eax, [rel rand_seed]
    xor eax, 0xDEADBEEF
    mov [rel platgen_rand_seed], eax

    xor ecx, ecx
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    call CreateEventA
    mov [rel evt_frame_ready], rax

    xor ecx, ecx
    xor edx, edx
    mov r8d, 1
    xor r9d, r9d
    call CreateEventA
    mov [rel evt_render_done], rax

    xor ecx, ecx
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    call CreateEventA
    mov [rel evt_audio_cmd], rax

    xor ecx, ecx
    xor edx, edx
    mov r8d, 1
    xor r9d, r9d
    call CreateEventA
    mov [rel evt_platgen_needed], rax

    ; --- Spawn Render Thread ---
 
    xor ecx, ecx
    xor edx, edx
    lea r8, [rel render_thread_proc]
    xor r9, r9
    mov dword [rsp+32], 0
    lea rax, [rel render_thread_id]
    mov [rsp+40], rax
    call CreateThread
    mov [rel h_render_thread], rax

    ; --- Spawn Audio Thread ---
    xor ecx, ecx
    xor edx, edx
    lea r8, [rel audio_thread_proc]
    xor r9, r9
    mov dword [rsp+32], 0
    lea rax, [rel audio_thread_id]
    mov [rsp+40], rax
    call CreateThread
    mov [rel h_audio_thread], rax

    ; --- Spawn PlatGen Thread ---
    xor ecx, ecx
    xor edx, edx
    lea r8, [rel platgen_thread_proc]
    xor r9, r9
    mov dword [rsp+32], 0
    lea rax, [rel platgen_thread_id]
    mov [rsp+40], rax
    call CreateThread
    mov [rel h_platgen_thread], rax

    add rsp, 48
    pop r13
    pop r12
    pop rbx
    ret

threads_shutdown:
    push rbx
    push r12
    sub rsp, 40

    mov dword [rel thread_shutdown], 1
    mfence

    ; Wake all threads
    mov rcx, [rel evt_frame_ready]
    call SetEvent
    mov rcx, [rel evt_audio_cmd]
    call SetEvent
    mov rcx, [rel evt_platgen_needed]
    call SetEvent


    mov rcx, [rel h_render_thread]
    mov edx, 5000
    call WaitForSingleObject

    mov rcx, [rel h_audio_thread]
    mov edx, 5000
    call WaitForSingleObject

    mov rcx, [rel h_platgen_thread]
    mov edx, 5000
    call WaitForSingleObject

    mov rcx, [rel h_render_thread]
    call CloseHandle
    mov rcx, [rel h_audio_thread]
    call CloseHandle
    mov rcx, [rel h_platgen_thread]
    call CloseHandle

    mov rcx, [rel evt_frame_ready]
    call CloseHandle
    mov rcx, [rel evt_render_done]
    call CloseHandle
    mov rcx, [rel evt_audio_cmd]
    call CloseHandle
    mov rcx, [rel evt_platgen_needed]
    call CloseHandle

    add rsp, 40
    pop r12
    pop rbx
    ret

; RENDER THREAD - GetDC + StretchDIBits from front_buffer

render_thread_proc:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rsi
    push rdi
    sub rsp, 128                    

.loop:
    ; Wait for main thread to signal a new frame
    mov rcx, [rel evt_frame_ready]
    mov edx, INFINITE
    call WaitForSingleObject


    cmp dword [rel thread_shutdown], 1
    je .exit

    mov rcx, [rel hwnd_main]
    call GetDC
    mov r12, rax                   

    test r12, r12
    jz .signal_done                 

 
    mov rcx, r12
    xor edx, edx
    xor r8d, r8d
    mov r9d, SCREEN_W
    mov dword [rsp+32], SCREEN_H
    mov dword [rsp+40], 0
    mov dword [rsp+48], 0
    mov dword [rsp+56], SCREEN_W
    mov dword [rsp+64], SCREEN_H
    lea rax, [rel front_buffer]
    mov [rsp+72], rax
    lea rax, [rel bmi]
    mov [rsp+80], rax
    mov dword [rsp+88], DIB_RGB_COLORS
    mov dword [rsp+96], SRCCOPY
    call StretchDIBits

 
    mov rcx, [rel hwnd_main]
    mov rdx, r12
    call ReleaseDC

.signal_done:

    mov rcx, [rel evt_render_done]
    call SetEvent

    jmp .loop

.exit:
    add rsp, 128                   
    pop rdi
    pop rsi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    xor ecx, ecx
    call ExitThread

; AUDIO THREAD - Drain SPSC ring buffer, dispatch commands

audio_thread_proc:
    push rbx
    push r12
    sub rsp, 40

.loop:
  
    mov rcx, [rel evt_audio_cmd]
    mov edx, 500
    call WaitForSingleObject


    cmp dword [rel thread_shutdown], 1
    je .exit

  
.drain:
    mov eax, [rel audio_ring_tail]
    cmp eax, [rel audio_ring_head]
    je .loop                       

 
    mov edx, eax
    and edx, AUDIO_CMD_MASK
    lea r8, [rel audio_cmd_ring]
    mov ecx, [r8 + rdx*4]


    inc eax
    mov [rel audio_ring_tail], eax

    cmp ecx, CMD_PLAY_JUMP
    je .do_jump
    cmp ecx, CMD_UPDATE_MUSIC
    je .do_update
    cmp ecx, CMD_STOP_MUSIC
    je .do_stop
    jmp .drain                     

.do_jump:
    call audio_play_jump
    jmp .drain
.do_update:
    call audio_update_music
    jmp .drain
.do_stop:
    call audio_stop_music
    jmp .drain

.exit:
    add rsp, 40
    pop r12
    pop rbx
    xor ecx, ecx
    call ExitThread

; PLATGEN THREAD - Pre-generate platforms into pool

platgen_thread_proc:
    push rbx
    push r12
    push r13
    sub rsp, 48                   

.loop:

    mov rcx, [rel evt_platgen_needed]
    mov edx, 1000
    call WaitForSingleObject


    cmp dword [rel thread_shutdown], 1
    je .exit

    ; Generate platforms until pool is full
.gen_loop:
    call platpool_lock_acquire

    mov eax, [rel platpool_count]
    cmp eax, PLATPOOL_SIZE
    jge .release_done



    call platgen_random
    xor edx, edx
    mov ecx, 400
    div ecx
    sub edx, 200
    add edx, [rel highest_platform_x]

 
    cmp edx, 0
    jge .chk_max
    xor edx, edx
    jmp .save_x
.chk_max:
    cmp edx, 720
    jle .save_x
    mov edx, 720
.save_x:
    mov r12d, edx                  

   
    call platgen_random
    xor edx, edx
    mov ecx, 60
    div ecx
    add edx, 30
    mov eax, [rel highest_platform_y]
    sub eax, edx
    mov r13d, eax                  


    mov eax, [rel platpool_write_idx]
    lea rbx, [rel platpool_x]
    mov [rbx + rax*4], r12d
    lea rbx, [rel platpool_y]
    mov [rbx + rax*4], r13d

 
    inc eax
    cmp eax, PLATPOOL_SIZE
    jl .no_wrap_w
    xor eax, eax
.no_wrap_w:
    mov [rel platpool_write_idx], eax
    inc dword [rel platpool_count]

    mov [rel highest_platform_x], r12d
    mov [rel highest_platform_y], r13d

    call platpool_lock_release
    jmp .gen_loop

.release_done:
    call platpool_lock_release
    jmp .loop

.exit:
    add rsp, 48                     
    pop r13
    pop r12
    pop rbx
    xor ecx, ecx
    call ExitThread

; Post a command to the audio SPSC ring

audio_post_cmd:
    push rbx
    sub rsp, 32                     
    mov ebx, ecx                  


    mov eax, [rel audio_ring_head]
    mov edx, eax
    inc edx
    cmp edx, [rel audio_ring_tail]
    je .full                        


    mov ecx, eax
    and ecx, AUDIO_CMD_MASK
    lea r8, [rel audio_cmd_ring]
    mov [r8 + rcx*4], ebx

    
    mfence
    mov [rel audio_ring_head], edx

    mov rcx, [rel evt_audio_cmd]
    call SetEvent

.full:
    add rsp, 32                     
    pop rbx
    ret

; platpool_consume - Take one platform from the pool

platpool_consume:
    push rbx
    push r12
    push r13
    sub rsp, 32                    

    call platpool_lock_acquire

    cmp dword [rel platpool_count], 0
    je .empty


    mov eax, [rel platpool_read_idx]
    lea rbx, [rel platpool_x]
    mov r12d, [rbx + rax*4]
    lea rbx, [rel platpool_y]
    mov r13d, [rbx + rax*4]

 
    inc eax
    cmp eax, PLATPOOL_SIZE
    jl .no_wrap
    xor eax, eax
.no_wrap:
    mov [rel platpool_read_idx], eax
    dec dword [rel platpool_count]

    call platpool_lock_release

    mov eax, r12d                   
    mov edx, r13d                   
    mov ecx, 1                      
    jmp .ret

.empty:
    call platpool_lock_release
    xor ecx, ecx                    

.ret:
    add rsp, 32                     
    pop r13
    pop r12
    pop rbx
    ret


platpool_request:
    sub rsp, 40
    cmp dword [rel platpool_count], PLATPOOL_SIZE / 2
    jge .enough
    mov rcx, [rel evt_platgen_needed]
    call SetEvent
.enough:
    add rsp, 40
    ret
