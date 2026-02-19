BITS 64
DEFAULT REL

; Ces trois fonctions sont des stubs : elles ne font rien.
; Le son réel (boucle musicale) est géré par Audio_Init dans audio.asm.
; Elles existent uniquement pour satisfaire les extern dans
; game.asm, physics.asm et platforms.asm (logique copiée de l'ancien projet).

global audio_play_jump
global audio_update_music
global audio_stop_music

section .text

audio_play_jump:
    ret

audio_update_music:
    ret

audio_stop_music:
    ret
