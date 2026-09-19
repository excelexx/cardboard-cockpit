; Selected retained-stock instructions from the inspected backup.
; These are analysis excerpts, not a complete restorable image.

; 74HC165 read and START
4200af2a: c.addi       sp, -0x10
4200af2c: c.swsp       ra, 0xc(sp)
4200af2e: c.swsp       s0, 8(sp)
4200af30: c.swsp       s1, 4(sp)
4200af32: c.li         a1, 0
4200af34: c.li         a0, 0x14
4200af36: jal          0xf0c50
4200af3a: c.li         a0, 1
4200af3c: auipc        ra, 0xfdff5
4200af40: jalr         ra, ra, 0x114
4200af44: c.li         a1, 1
4200af46: c.li         a0, 0x14
4200af48: jal          0xf0c3e
4200af4c: c.li         a0, 1
4200af4e: auipc        ra, 0xfdff5
4200af52: jalr         ra, ra, 0x102
4200af56: c.li         s0, 7
4200af58: c.li         s1, 0
4200af5a: c.j          0x28
4200af5c: c.li         a1, 1
4200af5e: c.li         a0, 0x15
4200af60: jal          0xf0c26
4200af64: c.li         a0, 1
4200af66: auipc        ra, 0xfdff5
4200af6a: jalr         ra, ra, 0xea
4200af6e: c.li         a1, 0
4200af70: c.li         a0, 0x15
4200af72: jal          0xf0c14
4200af76: c.li         a0, 1
4200af78: auipc        ra, 0xfdff5
4200af7c: jalr         ra, ra, 0xd8
4200af80: c.addi       s0, -1
4200af82: bltz         s0, 0x1a
4200af86: c.li         a0, 7
4200af88: jal          0xf0c8a
4200af8c: c.beqz       a0, -0x30
4200af8e: c.li         a5, 1
4200af90: sll          a5, a5, s0
4200af94: c.or         s1, a5
4200af96: andi         s1, s1, 0xff
4200af9a: c.j          -0x3e
4200af9c: c.mv         a0, s1
4200af9e: c.lwsp       ra, 0xc(sp)
4200afa0: c.lwsp       s0, 8(sp)
4200afa2: c.lwsp       s1, 4(sp)
4200afa4: c.addi       sp, 0x10
4200afa6: c.jr         ra
4200afa8: c.addi       sp, -0x10
4200afaa: c.swsp       ra, 0xc(sp)
4200afac: c.swsp       s0, 8(sp)
4200afae: jal          -0x84
4200afb2: c.li         a4, 0
4200afb4: c.li         s0, 0
4200afb6: c.j          8
4200afb8: c.addi       a4, 1
4200afba: andi         a4, a4, 0xff
4200afbe: c.li         a5, 7
4200afc0: bltu         a5, a4, 0x1e
4200afc4: c.li         a5, 7
4200afc6: c.sub        a5, a4
4200afc8: srl          a5, a0, a5
4200afcc: c.andi       a5, 1
4200afce: c.bnez       a5, -0x16
4200afd0: c.li         a5, 1
4200afd2: sll          a5, a5, a4
4200afd6: c.or         s0, a5
4200afd8: c.slli       s0, 0x10
4200afda: c.srli       s0, 0x10
4200afdc: c.j          -0x24
4200afde: c.li         a0, 9
4200afe0: jal          0xf0c32
4200afe4: c.bnez       a0, 6
4200afe6: ori          s0, s0, 0x100
4200afea: c.mv         a0, s0
4200afec: c.lwsp       ra, 0xc(sp)
4200afee: c.lwsp       s0, 8(sp)
4200aff0: c.addi       sp, 0x10
4200aff2: c.jr         ra

; LCD initialization
4200df1a: c.addi16sp   sp, -0xe0
4200df1c: c.swsp       ra, 0xdc(sp)
4200df1e: c.swsp       s0, 0xd8(sp)
4200df20: c.swsp       s1, 0xd4(sp)
4200df22: c.swsp       zero, 0x94(sp)
4200df24: c.swsp       zero, 0x98(sp)
4200df26: c.swsp       zero, 0x9c(sp)
4200df28: c.swsp       zero, 0xa0(sp)
4200df2a: c.swsp       zero, 0xa4(sp)
4200df2c: c.swsp       zero, 0xa8(sp)
4200df2e: c.swsp       zero, 0xac(sp)
4200df30: c.swsp       zero, 0xb0(sp)
4200df32: c.swsp       zero, 0xb4(sp)
4200df34: c.swsp       zero, 0xb8(sp)
4200df36: c.swsp       zero, 0xbc(sp)
4200df38: c.swsp       zero, 0xc0(sp)
4200df3a: c.swsp       zero, 0xc4(sp)
4200df3c: c.swsp       zero, 0xc8(sp)
4200df3e: c.li         s0, 0xa
4200df40: c.swsp       s0, 0x94(sp)
4200df42: c.li         a5, -1
4200df44: c.swsp       a5, 0x98(sp)
4200df46: c.li         s1, 1
4200df48: c.swsp       s1, 0x9c(sp)
4200df4a: c.lui        a5, 5
4200df4c: addi         a5, a5, -0x500
4200df50: c.swsp       a5, 0xbc(sp)
4200df52: c.li         a2, 3
4200df54: c.addi4spn   a1, sp, 0x94
4200df56: c.mv         a0, s1
4200df58: jal          0xe36da
4200df5c: c.swsp       zero, 0x64(sp)
4200df5e: c.swsp       zero, 0x68(sp)
4200df60: c.swsp       zero, 0x6c(sp)
4200df62: c.swsp       zero, 0x70(sp)
4200df64: c.swsp       zero, 0x74(sp)
4200df66: c.swsp       zero, 0x78(sp)
4200df68: c.swsp       zero, 0x7c(sp)
4200df6a: c.swsp       zero, 0x80(sp)
4200df6c: c.swsp       zero, 0x84(sp)
4200df6e: c.swsp       zero, 0x88(sp)
4200df70: c.swsp       zero, 0x8c(sp)
4200df72: c.li         a5, 2
4200df74: c.swsp       a5, 0x64(sp)
4200df76: lui          a5, 0x2626
4200df7a: addi         a5, a5, -0x600
4200df7e: c.swsp       a5, 0x70(sp)
4200df80: c.swsp       s0, 0x74(sp)
4200df82: c.li         a5, 8
4200df84: c.swsp       a5, 0x80(sp)
4200df86: c.swsp       a5, 0x84(sp)
4200df88: c.addi4spn   a2, sp, 0x90
4200df8a: c.addi4spn   a1, sp, 0x64
4200df8c: c.mv         a0, s1
4200df8e: jal          0x97808
4200df92: c.swsp       zero, 0x4c(sp)
4200df94: c.swsp       zero, 0x50(sp)
4200df96: c.swsp       zero, 0x54(sp)
4200df98: c.swsp       zero, 0x58(sp)
4200df9a: c.swsp       zero, 0x5c(sp)
4200df9c: c.swsp       zero, 0x60(sp)
4200df9e: c.li         a5, 4
4200dfa0: c.swsp       a5, 0x4c(sp)
4200dfa2: c.li         a5, 0x10
4200dfa4: c.swsp       a5, 0x58(sp)
4200dfa6: lui          s0, 0x3fcb6
4200dfaa: addi         a2, s0, -0x2a0
4200dfae: c.addi4spn   a1, sp, 0x4c
4200dfb0: c.lwsp       a0, 0x90(sp)
4200dfb2: jal          0x96920
4200dfb6: c.li         a1, 0
4200dfb8: lw           a0, -0x2a0(s0)
4200dfbc: jal          0x96ece
4200dfc0: lw           a0, -0x2a0(s0)
4200dfc4: jal          0x96b9e
4200dfc8: lw           a0, -0x2a0(s0)
4200dfcc: jal          0x96c18
4200dfd0: c.mv         a1, s1
4200dfd2: lw           a0, -0x2a0(s0)
4200dfd6: jal          0x96e2e
4200dfda: c.mv         a1, s1
4200dfdc: lw           a0, -0x2a0(s0)
4200dfe0: jal          0x96d9e
4200dfe4: c.li         a2, 0
4200dfe6: c.mv         a1, s1
4200dfe8: lw           a0, -0x2a0(s0)
4200dfec: jal          0x96d0c

; I2C configuration
4200e408: c.addi16sp   sp, -0x30
4200e40a: c.swsp       ra, 0x2c(sp)
4200e40c: c.swsp       s0, 0x28(sp)
4200e40e: c.swsp       s1, 0x24(sp)
4200e410: lui          a5, 0x3fcb6
4200e414: lw           a5, -0x298(a5)
4200e418: c.beqz       a5, 0x10
4200e41a: c.li         s0, 0
4200e41c: c.mv         a0, s0
4200e41e: c.lwsp       ra, 0x2c(sp)
4200e420: c.lwsp       s0, 0x28(sp)
4200e422: c.lwsp       s1, 0x24(sp)
4200e424: c.addi16sp   sp, 0x30
4200e426: c.jr         ra
4200e428: c.swsp       zero, 0(sp)
4200e42a: c.swsp       zero, 4(sp)
4200e42c: c.swsp       zero, 8(sp)
4200e42e: c.swsp       zero, 0xc(sp)
4200e430: c.swsp       zero, 0x10(sp)
4200e432: c.swsp       zero, 0x14(sp)
4200e434: c.swsp       zero, 0x18(sp)
4200e436: c.swsp       zero, 0x1c(sp)
4200e438: c.li         a5, 5
4200e43a: c.swsp       a5, 4(sp)
4200e43c: c.li         a5, 6
4200e43e: c.swsp       a5, 8(sp)
4200e440: c.li         a5, 0xa
4200e442: c.swsp       a5, 0xc(sp)
4200e444: c.li         a5, 7
4200e446: sb           a5, 0x10(sp)
4200e44a: lbu          a5, 0x1c(sp)
4200e44e: ori          a5, a5, 1
4200e452: sb           a5, 0x1c(sp)
4200e456: lui          a1, 0x3fcb6
4200e45a: addi         a1, a1, -0x298
4200e45e: c.mv         a0, sp
4200e460: auipc        ra, 0x118
4200e464: jalr         ra, ra, -0x4d0

; NFC address setup
4200fbd6: lui          a1, 0x3fcb6
4200fbda: addi         a1, a1, -0x264
4200fbde: addi         a0, zero, 0x26
4200fbe2: jal          0x29d4
4200fbe6: c.mv         s0, a0
4200fbe8: c.bnez       a0, 0x8c
4200fbea: lui          a0, 0x3c137
4200fbee: addi         a0, a0, -0x6e8
4200fbf2: jal          -0xae
4200fbf6: lui          a5, 0x3fcb6
4200fbfa: lw           a0, -0x264(a5)
4200fbfe: jal          0x92c96
4200fc02: c.mv         s0, a0
4200fc04: c.bnez       a0, 0xae

; LED initialization; constant pool overwritten
4200f424: c.addi16sp   sp, -0x40
4200f426: c.swsp       ra, 0x3c(sp)
4200f428: c.swsp       s0, 0x38(sp)
4200f42a: c.swsp       s1, 0x34(sp)
4200f42c: lui          a5, 0x3c155
4200f430: addi         a5, a5, -0x420
4200f434: c.lw         a1, 0(a5)
4200f436: c.lw         a2, 4(a5)
4200f438: c.lw         a3, 8(a5)
4200f43a: c.lw         a4, 0xc(a5)
4200f43c: c.lw         a5, 0x10(a5)
4200f43e: c.swsp       a1, 0x1c(sp)
4200f440: c.swsp       a2, 0x20(sp)
4200f442: c.swsp       a3, 0x24(sp)
4200f444: c.swsp       a4, 0x28(sp)
4200f446: c.swsp       a5, 0x2c(sp)
4200f448: c.swsp       zero, 0xc(sp)
4200f44a: c.swsp       zero, 0x10(sp)
4200f44c: c.swsp       zero, 0x14(sp)
4200f44e: c.swsp       zero, 0x18(sp)
4200f450: c.li         a5, 4
4200f452: c.swsp       a5, 0xc(sp)
4200f454: lui          a5, 0x989
4200f458: addi         a5, a5, 0x680
4200f45c: c.swsp       a5, 0x10(sp)
4200f45e: addi         a5, zero, 0x40
4200f462: c.swsp       a5, 0x14(sp)
4200f464: lui          a2, 0x3fcb6
4200f468: addi         a2, a2, -0x27c
4200f46c: c.addi4spn   a1, sp, 0xc
4200f46e: c.addi4spn   a0, sp, 0x1c
4200f470: jal          0xe0956
4200f474: c.mv         s0, a0
4200f476: c.bnez       a0, 0x20
4200f478: lui          s0, 0x3fcb6
4200f47c: lw           a0, -0x27c(s0)
4200f480: jal          0xe04fc
4200f484: lw           a0, -0x27c(s0)
4200f488: jal          0xe04aa
4200f48c: c.lwsp       ra, 0x3c(sp)
4200f48e: c.lwsp       s0, 0x38(sp)
4200f490: c.lwsp       s1, 0x34(sp)
4200f492: c.addi16sp   sp, 0x40
