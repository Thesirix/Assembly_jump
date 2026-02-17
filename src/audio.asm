BITS 64
DEFAULT REL

extern PlaySoundA
extern midiOutOpen
extern midiOutShortMsg
extern midiOutClose

; --- EXPORTS ---
global audio_init
global audio_cleanup
global audio_play_jump
global audio_update_music
global audio_stop_music     ; <--- INDISPENSABLE POUR LE GAME OVER

%define SND_ASYNC           0x0001
%define SND_MEMORY          0x0004
%define SND_NOSTOP          0x0010
%define SAMPLE_RATE         44100
%define DURATION_SAMPLES    6000     
%define WAV_HEADER_SIZE     44
%define TOTAL_WAV_SIZE      (WAV_HEADER_SIZE + DURATION_SAMPLES)

section .data
music_notes dd 60, 64, 67, 72, 67, 64 
music_len   dd 6

section .bss
align 16
sound_buffer resb TOTAL_WAV_SIZE 
hMidiOut     resq 1              
music_timer  resd 1
note_index   resd 1

section .text

audio_init:
    sub rsp, 40
    lea rdi, [rel sound_buffer]
    mov dword [rdi], 0x46464952
    mov dword [rdi+4], TOTAL_WAV_SIZE - 8
    mov dword [rdi+8], 0x45564157
    mov dword [rdi+12], 0x20746d66
    mov dword [rdi+16], 16
    mov word  [rdi+20], 1
    mov word  [rdi+22], 1
    mov dword [rdi+24], SAMPLE_RATE
    mov dword [rdi+28], SAMPLE_RATE
    mov word  [rdi+32], 1
    mov word  [rdi+34], 8
    mov dword [rdi+36], 0x61746164
    mov dword [rdi+40], DURATION_SAMPLES
    
    lea rdi, [rel sound_buffer + WAV_HEADER_SIZE]
    xor rcx, rcx    
    xor r8, r8      
    mov r9d, 0      
    mov r10d, 150   
.gen:
    cmp rcx, DURATION_SAMPLES
    jge .gen_end
    mov byte [rdi + rcx], r8b
    inc r9d
    cmp r9d, r10d
    jl .no_fl
    not r8b         
    xor r9d, r9d    
    cmp r10d, 30
    jle .no_fl
    test cl, 0x0F 
    jnz .no_fl
    dec r10d      
.no_fl:
    inc rcx
    jmp .gen
.gen_end:
    lea rcx, [rel hMidiOut]
    mov edx, -1             
    xor r8, r8
    xor r9, r9
    xor eax, eax
    mov [rsp+32], eax
    call midiOutOpen
    mov rcx, [rel hMidiOut]
    mov edx, 0x0050C0       
    xor r8, r8
    call midiOutShortMsg
    mov dword [rel music_timer], 0
    mov dword [rel note_index], 0
    add rsp, 40
    ret

audio_cleanup:
    sub rsp, 40
    mov rcx, [rel hMidiOut]
    test rcx, rcx
    jz .done
    call midiOutClose
.done:
    add rsp, 40
    ret

audio_play_jump:
    sub rsp, 40
    lea rcx, [rel sound_buffer]
    xor edx, edx
    mov r8d, SND_ASYNC | SND_MEMORY | SND_NOSTOP
    call PlaySoundA
    add rsp, 40
    ret

audio_update_music:
    push rbx
    sub rsp, 32
    mov eax, [rel music_timer]
    inc eax
    mov [rel music_timer], eax
    cmp eax, 12
    jl .m_done
    mov dword [rel music_timer], 0
    lea rsi, [rel music_notes]
    mov ebx, [rel note_index]   
    mov r8d, [rsi + rbx*4]      
    shl r8d, 8
    or r8d, 0x00000080          
    mov rcx, [rel hMidiOut]
    mov rdx, r8
    xor r8, r8
    call midiOutShortMsg
    inc ebx
    cmp ebx, [rel music_len]
    jl .save
    xor ebx, ebx                
.save:
    mov [rel note_index], ebx   
    mov r8d, [rsi + rbx*4]      
    shl r8d, 8
    or r8d, 0x007F0090          
    mov rcx, [rel hMidiOut]
    mov rdx, r8
    xor r8, r8
    call midiOutShortMsg
.m_done:
    add rsp, 32
    pop rbx
    ret

; --- FONCTION MANQUANTE AJOUTÉE ---
audio_stop_music:
    push rbx
    sub rsp, 32
    mov ebx, [rel note_index]
    lea rsi, [rel music_notes]
    mov r8d, [rsi + rbx*4]
    shl r8d, 8
    or r8d, 0x00000080 
    mov rcx, [rel hMidiOut]
    mov rdx, r8
    xor r8, r8
    call midiOutShortMsg
    mov dword [rel note_index], 0
    mov dword [rel music_timer], 0
    add rsp, 32
    pop rbx
    ret