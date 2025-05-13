; T3 - Intro to the MicroKERNEL
; 2024 mcassera
; Using the Directory Calls



.cpu "w65c02"	
.include "api.asm"                                                      ; This is the Kernel API for communication
Start:

*=$c0								        ; Set up buffer for Kernel communication
	.dsection zp						        ; Define position for zp (zero page)
	.cerror * > $cf, "Too many Zero page variables"

* = $7f00
        .dsection code
        .cerror *> $7fff, "Into SuperBASIC code"
        		                                

SetupKernel:							        ; Set up the API to work with

	.section zp						        ; Zero page section $c0 to $c6
event:	.dstruct	kernel.event.event_t
        .send


        .section code

clearBuffer:                                                            ; need to clear 2024 bytes for the buffer
        lda buff                                                        ; using zero pager for indirect y indexing
        sta $c8                                                         ; buff was poked into memory from the basic program
        lda buff+1                                                      ; pokew after using an alloc() command to secure the memory
        sta $c9
        ldx #$09                                                        ; we're going to use eight loops of 255 bytes.
loopx:
        ldy #$00                                                        ; we need to clear the memory because we'll be looking for
        lda #$00                                                        ; $00 as a file separator
loopy:
        sta ($c8),y                                                     ; index y from 0 to 255
        iny
        bne loopy                                                       ; no, keep looping Y
                                                           
        inc $c9                                                         ; yes - so now we need to add $100 to our zero page indirect addres (inc hi byte)

        dex                                                             ; now we countown X to zero. If we're not there yet
        bne loopx                                                       ; let's loop again.

init_events:

        lda #<event                                                     ; we're setting up the kernel telling it where our memory will be
        sta kernel.args.events                                          ; this was setup above is th ZP section - we're using $c0 to $c6
        lda #>event                                                     ; as SuperBASIC does not use this memory
        sta kernel.args.events+1

openDir:
        stz kernel.args.directory.open.drive                            ; 0 = SD Card
        lda #<dirPath                                                   ; setting the director path by storing the path in a buffer at the end of the program
        sta kernel.args.directory.open.path                             ; the path argument needs 2 byte to store the location of the path buffer
        lda #>dirPath
        sta kernel.args.directory.open.path+1
        lda pathLen                                                     ; you also need to set the length of the path so the kernel knows how long the string is
        sta kernel.args.directory.open.path_len
        lda #$01                                                        ; setting up an arbitrary number for the cookie - this is for the users use
        sta kernel.args.directory.open.cookie
        sta cookie
        jsr kernel.directory.open                                       ; Once the arguments are set, this is the jsr to open the directory
        bcc oktogo                                                      ; carry is clear if everything went well.       
        brk                                                             ; just a bad stop of there is a problems
oktogo:                                                                 ; if all went well, A will have the stream identifier for this open "file"
        sta stream                                                      ; we need to save that to do any work with this file
        sta kernel.args.directory.read.stream                           ; we save it to the read.stream argument for the next kernel call
        jsr kernel.directory.read                                       ; which is the directory read call
        jsr handle_events                                               ; and then we jsr to the handle_event routine
        rts                                                             ; once everything is down, this will return us to SuperBASIC

handle_events:
        lda kernel.args.events.pending		                        ; Peek at the queue to see if anything is pending
        bpl _done       			                        ; Nothing to do
        jsr kernel.NextEvent			                        ; Get the next event.
        bcs _done       		                                ; Check for pending
        jsr _dispatch                                                   ; if we have an event, let's check it out in dispatch
        bra handle_events
_done:
        rts             			                        ; go and check for another event        

_dispatch:
        lda event.type				                        ; get the event type from Kernel - we are only looking for directory events here.
        cmp #kernel.event.directory.VOLUME                              ; We should hit this first as it will be the first thing on the directory read
        beq _getVolume                                                  ; go and get the drive volume name
        cmp #kernel.event.directory.FILE                                ; this is the meat of what we'll be doing - this pulls each file entry from the directory
        beq _getFile                                                    ; this subroutine will store it in our allocated memory
        cmp #kernel.event.directory.FREE                                ; at the end of the directory will be a memory free event to let you know how much space is left
        beq _getFree	                                                ; although we don't use it, it's still important because it the last thing before the EOF event
        cmp #kernel.event.directory.EOF	                                ; once we hit the end of file, we'll close the directory and give control back to SuperBASIC
        beq _eof                         
        rts

_getVolume:
        lda event.directory.volume.len                                  ; we need to pull the length of the Volume so we know how much data the readdate call needs to pass
        jsr _readData
        rts

_getFile:
        lda event.directory.file.len                                    ; same with the file length - the buffer can be up to 255 bytes
        jsr _readData
        rts

_getFree:
        bra _nextRead                                                   ; we're not pulling from memory with out free event, but we still nee to do another 
        rts                                                             ; directory read call

_eof:   
        lda stream                                                      ; here's the EOF routine. We need to set the close.stream argument with the stream id
        sta kernel.args.directory.close.stream                          ; before we can close the directory
        jsr kernel.directory.close                                      ; once we return, we should run out of events and return us back to SuperBASIC
        rts

_readData:                                                              ; our read data routine.
        sta buffLen                                                     ; first we store the buffer length the kernel told us from the event
        sta kernel.args.buflen                                          ; and we store that in the arg.buflen control for the readdata call
        lda buff                                                        ; then we need to tell the kernel where our buffer is located. this is a
        sta kernel.args.buf                                             ; two byte number
        lda buff+1
        sta kernel.args.buf+1                                           
        jsr kernel.readdata                                             ; next we call the readdata routine to transfer the data from the kernel's buffer to
        jsr moveBufferPointer                                           ; our buffer. So we don't overwrite the buffer with the next entry, we need to move the
_nextRead:                                                              ; pointer in our buffer forward.
        lda stream                                                      ; before we do another directory read command here.
        sta kernel.args.directory.read.stream
        jsr kernel.directory.read
        rts

MoveBufferPointer:                              
        inc buffLen                                                     ; to move the pointer, we're going to first increase the buffer size by one to leave us
        clc                                                             ; a zero byte as a spacer between file names.
        lda buff                                                        ; then just a regular adding routine to move the buffer pointer forward in out buffer
        adc buffLen
        sta buff
        lda buff+1
        adc #$00
        sta buff+1
        rts



cookie:         .byte $00                                               ; the cookie byte - we don't really use this in this situation
stream:         .byte $00                                               ; the steam number which is assigned by the kernel. needed to manipulate the directory
buffLen:        .byte $00                                               ; this is the buffer length for each director.read we do that is needed for the readdata call.

buff:           .word $7700                                             ; this is the location of our buffer as designated in BASIC with a pokew command
pathLen:        .byte $00                                               ; this is the length of the path
dirPath:        .text " "                                               ; this is the path where my files are

        .endsection