BITS 64
DEFAULT REL

; =================================================================
; thread.asm — 3 worker threads : Render, Audio, Platform Generation
; =================================================================
; Render Thread   : GetDC → StretchDIBits(front_buffer) → ReleaseDC
; Audio Thread    : SPSC ring buffer → dispatch waveOut commands
; PlatGen Thread  : Pre-generate platforms into a pool (spinlock)
;
; Stack alignment x64 Windows :
;   Thread entry : rsp = 8 mod 16 (appelé via call)
;   Avant call   : rsp doit être 0 mod 16
;   Règle        : (nb_pushes * 8 + sub_rsp_N) mod 16 == 8
; =================================================================

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

; --- Exports ---
global threads_init
global threads_shutdown
global audio_post_cmd
global platpool_consume
global platpool_request
global evt_frame_ready
global evt_render_done
global thread_shutdown

; --- Constants ---
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

; =================================================================
section .data
; =================================================================
platgen_rand_seed dd 67890      ; Separate RNG seed for platgen thread

; =================================================================
section .bss
; =================================================================

; --- Thread handles ---
h_render_thread     resq 1
h_audio_thread      resq 1
h_platgen_thread    resq 1
render_thread_id    resd 1
audio_thread_id     resd 1
platgen_thread_id   resd 1

; --- Event handles ---
evt_frame_ready     resq 1
evt_render_done     resq 1
evt_audio_cmd       resq 1
evt_platgen_needed  resq 1

; --- Shutdown flag ---
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

; =================================================================
section .text
; =================================================================

; ============================================================
; platgen_random — LCG random for platgen thread (own seed)
; Returns: eax = random value 0..32767
; ============================================================
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

; ============================================================
; Spinlock helpers
; ============================================================
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

; ============================================================
; threads_init — Create 4 events + spawn 3 worker threads
; Called from main thread. Entry: rsp = 8 mod 16.
; 3 pushes (24) + sub 48 = 72. (8-72) mod 16 = 0 mod 16. OK
; ============================================================
threads_init:
    push rbx
    push r12
    push r13
    sub rsp, 48

    ; --- Zero all state ---
    mov dword [rel thread_shutdown], 0
    mov dword [rel audio_ring_head], 0
    mov dword [rel audio_ring_tail], 0
    mov dword [rel platpool_count], 0
    mov dword [rel platpool_write_idx], 0
    mov dword [rel platpool_read_idx], 0
    mov dword [rel platpool_lock], 0

    ; Seed platgen RNG from main rand_seed
    mov eax, [rel rand_seed]
    xor eax, 0xDEADBEEF
    mov [rel platgen_rand_seed], eax

    ; --- Create Events ---
    ; CreateEventA(lpSecurity, bManualReset, bInitialState, lpName)

    ; evt_frame_ready : auto-reset, initial=non-signaled
    xor ecx, ecx
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    call CreateEventA
    mov [rel evt_frame_ready], rax

    ; evt_render_done : auto-reset, initial=SIGNALED (render "ready" at start)
    xor ecx, ecx
    xor edx, edx
    mov r8d, 1
    xor r9d, r9d
    call CreateEventA
    mov [rel evt_render_done], rax

    ; evt_audio_cmd : auto-reset, initial=non-signaled
    xor ecx, ecx
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    call CreateEventA
    mov [rel evt_audio_cmd], rax

    ; evt_platgen_needed : auto-reset, initial=SIGNALED (generate initial pool)
    xor ecx, ecx
    xor edx, edx
    mov r8d, 1
    xor r9d, r9d
    call CreateEventA
    mov [rel evt_platgen_needed], rax

    ; --- Spawn Render Thread ---
    ; CreateThread(lpSecurity, dwStackSize, lpStartAddress, lpParam, dwFlags, lpThreadId)
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

; ============================================================
; threads_shutdown — Signal shutdown, wait, cleanup handles
; Entry: rsp = 8 mod 16.
; 2 pushes (16) + sub 40 = 56. (8-56) mod 16 = 0 mod 16. OK
; ============================================================
threads_shutdown:
    push rbx
    push r12
    sub rsp, 40

    ; Set shutdown flag
    mov dword [rel thread_shutdown], 1
    mfence

    ; Wake all threads
    mov rcx, [rel evt_frame_ready]
    call SetEvent
    mov rcx, [rel evt_audio_cmd]
    call SetEvent
    mov rcx, [rel evt_platgen_needed]
    call SetEvent

    ; Wait for each thread to exit (5s timeout)
    mov rcx, [rel h_render_thread]
    mov edx, 5000
    call WaitForSingleObject

    mov rcx, [rel h_audio_thread]
    mov edx, 5000
    call WaitForSingleObject

    mov rcx, [rel h_platgen_thread]
    mov edx, 5000
    call WaitForSingleObject

    ; Close thread handles
    mov rcx, [rel h_render_thread]
    call CloseHandle
    mov rcx, [rel h_audio_thread]
    call CloseHandle
    mov rcx, [rel h_platgen_thread]
    call CloseHandle

    ; Close event handles
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

; ============================================================
; RENDER THREAD — GetDC + StretchDIBits from front_buffer
; Thread entry: rsp = 8 mod 16.
; 7 pushes (56) + sub 128 = 184. (8-184) mod 16 = 0 mod 16. OK
; 128 bytes stack >= 32 shadow + 9*8 stack params = 104. OK
; ============================================================
render_thread_proc:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rsi
    push rdi
    sub rsp, 128                    ; ← WAS 120, FIXED alignment

.loop:
    ; Wait for main thread to signal a new frame
    mov rcx, [rel evt_frame_ready]
    mov edx, INFINITE
    call WaitForSingleObject

    ; Check shutdown
    cmp dword [rel thread_shutdown], 1
    je .exit

    ; GetDC(hwnd)
    mov rcx, [rel hwnd_main]
    call GetDC
    mov r12, rax                    ; r12 = hDC

    test r12, r12
    jz .signal_done                 ; If GetDC failed, skip

    ; StretchDIBits(hDC, 0, 0, 800, 600, 0, 0, 800, 600, front_buffer, bmi, DIB_RGB_COLORS, SRCCOPY)
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

    ; ReleaseDC(hwnd, hDC)
    mov rcx, [rel hwnd_main]
    mov rdx, r12
    call ReleaseDC

.signal_done:
    ; Signal main thread: render complete
    mov rcx, [rel evt_render_done]
    call SetEvent

    jmp .loop

.exit:
    add rsp, 128                    ; ← match sub
    pop rdi
    pop rsi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    xor ecx, ecx
    call ExitThread

; ============================================================
; AUDIO THREAD — Drain SPSC ring buffer, dispatch commands
; Thread entry: rsp = 8 mod 16.
; 2 pushes (16) + sub 40 = 56. (8-56) mod 16 = 0 mod 16. OK
; ============================================================
audio_thread_proc:
    push rbx
    push r12
    sub rsp, 40

.loop:
    ; Wait with 500ms timeout (periodic wake for housekeeping)
    mov rcx, [rel evt_audio_cmd]
    mov edx, 500
    call WaitForSingleObject

    ; Check shutdown
    cmp dword [rel thread_shutdown], 1
    je .exit

    ; Drain all commands in the ring
.drain:
    mov eax, [rel audio_ring_tail]
    cmp eax, [rel audio_ring_head]
    je .loop                        ; Ring empty → back to wait

    ; Read command at ring[tail & MASK]
    mov edx, eax
    and edx, AUDIO_CMD_MASK
    lea r8, [rel audio_cmd_ring]
    mov ecx, [r8 + rdx*4]

    ; Advance tail
    inc eax
    mov [rel audio_ring_tail], eax

    ; Dispatch
    cmp ecx, CMD_PLAY_JUMP
    je .do_jump
    cmp ecx, CMD_UPDATE_MUSIC
    je .do_update
    cmp ecx, CMD_STOP_MUSIC
    je .do_stop
    jmp .drain                      ; Unknown → skip

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

; ============================================================
; PLATGEN THREAD — Pre-generate platforms into pool
; Thread entry: rsp = 8 mod 16.
; 3 pushes (24) + sub 48 = 72. (8-72) mod 16 = 0 mod 16. OK
; ============================================================
platgen_thread_proc:
    push rbx
    push r12
    push r13
    sub rsp, 48                     ; ← WAS 40, FIXED alignment

.loop:
    ; Wait with 1s timeout
    mov rcx, [rel evt_platgen_needed]
    mov edx, 1000
    call WaitForSingleObject

    ; Check shutdown
    cmp dword [rel thread_shutdown], 1
    je .exit

    ; Generate platforms until pool is full
.gen_loop:
    call platpool_lock_acquire

    mov eax, [rel platpool_count]
    cmp eax, PLATPOOL_SIZE
    jge .release_done

    ; --- Generate one platform (same algo as create_one_platform) ---

    ; Random X offset from last platform
    call platgen_random
    xor edx, edx
    mov ecx, 400
    div ecx
    sub edx, 200
    add edx, [rel highest_platform_x]

    ; Clamp X to [0, 720]
    cmp edx, 0
    jge .chk_max
    xor edx, edx
    jmp .save_x
.chk_max:
    cmp edx, 720
    jle .save_x
    mov edx, 720
.save_x:
    mov r12d, edx                   ; r12d = new X

    ; Random Y gap (30..89 pixels above highest)
    call platgen_random
    xor edx, edx
    mov ecx, 60
    div ecx
    add edx, 30
    mov eax, [rel highest_platform_y]
    sub eax, edx
    mov r13d, eax                   ; r13d = new Y

    ; Write to pool
    mov eax, [rel platpool_write_idx]
    lea rbx, [rel platpool_x]
    mov [rbx + rax*4], r12d
    lea rbx, [rel platpool_y]
    mov [rbx + rax*4], r13d

    ; Advance write index (circular)
    inc eax
    cmp eax, PLATPOOL_SIZE
    jl .no_wrap_w
    xor eax, eax
.no_wrap_w:
    mov [rel platpool_write_idx], eax
    inc dword [rel platpool_count]

    ; Update tracking for next generation
    mov [rel highest_platform_x], r12d
    mov [rel highest_platform_y], r13d

    call platpool_lock_release
    jmp .gen_loop

.release_done:
    call platpool_lock_release
    jmp .loop

.exit:
    add rsp, 48                     ; ← match sub
    pop r13
    pop r12
    pop rbx
    xor ecx, ecx
    call ExitThread

; ============================================================
; audio_post_cmd — Post a command to the audio SPSC ring
; Input: ecx = command ID (CMD_PLAY_JUMP / CMD_UPDATE_MUSIC / CMD_STOP_MUSIC)
; Entry: rsp = 8 mod 16 (called from main thread).
; 1 push (8) + sub 32 = 40. (8-40) mod 16 = 0 mod 16. OK
; ============================================================
audio_post_cmd:
    push rbx
    sub rsp, 32                     ; ← WAS 40, FIXED alignment
    mov ebx, ecx                    ; Save command ID

    ; Check if ring is full: (head + 1) == tail means full
    mov eax, [rel audio_ring_head]
    mov edx, eax
    inc edx
    cmp edx, [rel audio_ring_tail]
    je .full                         ; Full → drop command

    ; Write command at ring[head & MASK]
    mov ecx, eax
    and ecx, AUDIO_CMD_MASK
    lea r8, [rel audio_cmd_ring]
    mov [r8 + rcx*4], ebx

    ; Advance head (store ordering: command visible before head update)
    mfence
    mov [rel audio_ring_head], edx

    ; Wake audio thread
    mov rcx, [rel evt_audio_cmd]
    call SetEvent

.full:
    add rsp, 32                     ; ← match sub
    pop rbx
    ret

; ============================================================
; platpool_consume — Take one platform from the pool
; Returns: eax=x, edx=y, ecx=1 (success) or ecx=0 (empty)
; Entry: rsp = 8 mod 16.
; 3 pushes (24) + sub 32 = 56. (8-56) mod 16 = 0 mod 16. OK
; ============================================================
platpool_consume:
    push rbx
    push r12
    push r13
    sub rsp, 32                     ; ← WAS 40, FIXED alignment

    call platpool_lock_acquire

    cmp dword [rel platpool_count], 0
    je .empty

    ; Read from pool
    mov eax, [rel platpool_read_idx]
    lea rbx, [rel platpool_x]
    mov r12d, [rbx + rax*4]
    lea rbx, [rel platpool_y]
    mov r13d, [rbx + rax*4]

    ; Advance read index (circular)
    inc eax
    cmp eax, PLATPOOL_SIZE
    jl .no_wrap
    xor eax, eax
.no_wrap:
    mov [rel platpool_read_idx], eax
    dec dword [rel platpool_count]

    call platpool_lock_release

    mov eax, r12d                   ; x
    mov edx, r13d                   ; y
    mov ecx, 1                      ; success
    jmp .ret

.empty:
    call platpool_lock_release
    xor ecx, ecx                    ; failure

.ret:
    add rsp, 32                     ; ← match sub
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; platpool_request — Signal platgen thread if pool < 50%
; Entry: rsp = 8 mod 16.
; 0 pushes + sub 40 = 40. (8-40) mod 16 = 0 mod 16. OK
; ============================================================
platpool_request:
    sub rsp, 40
    cmp dword [rel platpool_count], PLATPOOL_SIZE / 2
    jge .enough
    mov rcx, [rel evt_platgen_needed]
    call SetEvent
.enough:
    add rsp, 40
    ret
