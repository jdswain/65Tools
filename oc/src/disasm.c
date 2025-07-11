// disasm.c - 65C816 Disassembler for .816 files
// Disassembles compiled Oberon modules to help with debugging

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "cpu.h"
#include "Files.h"
#include "Oberon.h"

// Code base address - must match ORG.c
#define CODE_ORG 0x2000

// Structure to represent a disassembled instruction
typedef struct {
    uint32_t address;
    uint8_t opcode;
    uint8_t operand1;
    uint8_t operand2;
    uint8_t operand3;
    int length;
    OpCode instruction;
    AddrMode mode;
    int value;
} DisasmInstr;

// Determine addressing mode and operand length from opcode
static void decode_instruction(uint8_t opcode, AddrMode *mode, int *length) {
    switch (opcode) {
        // Implied mode (1 byte)
        case 0x18: // CLC
        case 0x38: // SEC
        case 0xFB: // XCE
        case 0xEA: // NOP
        case 0x00: // BRK
        case 0x40: // RTI
        case 0x60: // RTS
        case 0x6B: // RTL
            *mode = Implied;
            *length = 1;
            break;
            
        // Immediate mode (2-3 bytes depending on A/M flag)
        case 0xA9: // LDA #
        case 0x69: // ADC #
        case 0xE9: // SBC #
            *mode = Immediate;
            *length = 3; // Assuming 16-bit mode
            break;
            
        case 0xC2: // REP #
        case 0xE2: // SEP #
            *mode = Immediate;
            *length = 2; // Always 8-bit operand
            break;
            
        // Direct Page (2 bytes)
        case 0xA5: // LDA dp
        case 0x85: // STA dp
        case 0x65: // ADC dp
        case 0xE5: // SBC dp
            *mode = DirectPage;
            *length = 2;
            break;
            
        // Direct Page,X (2 bytes)
        case 0xB5: // LDA dp,X
        case 0x95: // STA dp,X
        case 0x75: // ADC dp,X
        case 0xF5: // SBC dp,X
            *mode = DirectPageIndexedX;
            *length = 2;
            break;
            
        // Absolute (3 bytes)
        case 0xAD: // LDA abs
        case 0x8D: // STA abs
        case 0x6D: // ADC abs
        case 0xED: // SBC abs
        case 0x20: // JSR abs
            *mode = Absolute;
            *length = 3;
            break;
            
        // Absolute,X (3 bytes)
        case 0xBD: // LDA abs,X
        case 0x9D: // STA abs,X
        case 0x7D: // ADC abs,X
        case 0xFD: // SBC abs,X
            *mode = AbsoluteIndexedX;
            *length = 3;
            break;
            
        // Absolute,Y (3 bytes)
        case 0xB9: // LDA abs,Y
        case 0x99: // STA abs,Y
        case 0x79: // ADC abs,Y
        case 0xF9: // SBC abs,Y
            *mode = AbsoluteIndexedY;
            *length = 3;
            break;
            
        // Stack Relative (2 bytes)
        case 0xA3: // LDA sr,S
        case 0x83: // STA sr,S
            *mode = StackRelative;
            *length = 2;
            break;
            
        default:
            *mode = Implied;
            *length = 1;
            break;
    }
}

// Format operand value based on addressing mode
static char* format_operand(AddrMode mode, int value) {
    static char buffer[32];
    
    switch (mode) {
        case Implied:
            buffer[0] = '\0';
            break;
        case Immediate:
            sprintf(buffer, "#$%04X", value);
            break;
        case DirectPage:
            sprintf(buffer, "$%02X", value & 0xFF);
            break;
        case DirectPageIndexedX:
            sprintf(buffer, "$%02X,X", value & 0xFF);
            break;
        case Absolute:
            sprintf(buffer, "$%04X", value);
            break;
        case AbsoluteIndexedX:
            sprintf(buffer, "$%04X,X", value);
            break;
        case AbsoluteIndexedY:
            sprintf(buffer, "$%04X,Y", value);
            break;
        case StackRelative:
            sprintf(buffer, "$%02X,S", value & 0xFF);
            break;
        default:
            sprintf(buffer, "???");
            break;
    }
    
    return buffer;
}

// Disassemble a single instruction from the code array
static int disassemble_instruction(uint8_t *code, int pc, DisasmInstr *instr) {
    instr->address = CODE_ORG + pc;  // Add code base to show actual memory address
    instr->opcode = code[pc];
    instr->instruction = byte_to_opcode(instr->opcode);
    
    decode_instruction(instr->opcode, &instr->mode, &instr->length);
    
    // Read operands based on instruction length
    instr->operand1 = (instr->length > 1) ? code[pc + 1] : 0;
    instr->operand2 = (instr->length > 2) ? code[pc + 2] : 0;
    instr->operand3 = (instr->length > 3) ? code[pc + 3] : 0;
    
    // Combine operands into value
    switch (instr->length) {
        case 1:
            instr->value = 0;
            break;
        case 2:
            instr->value = instr->operand1;
            break;
        case 3:
            instr->value = instr->operand1 | (instr->operand2 << 8);
            break;
        case 4:
            instr->value = instr->operand1 | (instr->operand2 << 8) | (instr->operand3 << 16);
            break;
    }
    
    return instr->length;
}

// Print a disassembled instruction
static void print_instruction(DisasmInstr *instr) {
    const char *mnemonic = opcode_to_string(instr->instruction);
    char *operand = format_operand(instr->mode, instr->value);
    
    // Print address and raw bytes
    printf("%04X: ", instr->address);
    
    // Print raw bytes (up to 4 bytes, padded)
    for (int i = 0; i < 4; i++) {
        if (i < instr->length) {
            switch (i) {
                case 0: printf("%02X ", instr->opcode); break;
                case 1: printf("%02X ", instr->operand1); break;
                case 2: printf("%02X ", instr->operand2); break;
                case 3: printf("%02X ", instr->operand3); break;
            }
        } else {
            printf("   ");
        }
    }
    
    // Print mnemonic and operand
    printf("%-4s %s", mnemonic, operand);
    
    // Add comments for special cases
    if (instr->instruction == sREP && instr->value == 0x30) {
        printf("  ; 16-bit A/X/Y");
    } else if (instr->instruction == sSEP && instr->value == 0x30) {
        printf("  ; 8-bit A/X/Y");
    } else if (instr->instruction == sXCE) {
        printf("  ; Native mode");
    } else if (instr->mode == Absolute && instr->value >= 0x1000 && instr->value < 0x2000) {
        printf("  ; Module variable");
    } else if (instr->mode == DirectPage) {
        printf("  ; Register $%02X", instr->value);
    }
    
    printf("\n");
}

// Parse .816 file structure and extract code section
static int parse_816_file(const char *filename, uint8_t **code_data, int *code_size) {
    FILE *file = fopen(filename, "rb");
    if (!file) {
        printf("Error: Cannot open file %s\n", filename);
        return 0;
    }
    
    // Read module name (null-terminated string)
    char module_name[64];
    int name_len = 0;
    while (name_len < 63) {
        if (fread(&module_name[name_len], 1, 1, file) != 1) {
            printf("Error: Unexpected end of file reading module name\n");
            fclose(file);
            return 0;
        }
        if (module_name[name_len] == 0) break;
        name_len++;
    }
    module_name[name_len] = 0;
    
    printf("Module: %s\n", module_name);
    
    // Read key (4 bytes)
    uint32_t key;
    if (fread(&key, 4, 1, file) != 1) {
        printf("Error: Cannot read key\n");
        fclose(file);
        return 0;
    }
    
    // Read version (1 byte)
    uint8_t version;
    if (fread(&version, 1, 1, file) != 1) {
        printf("Error: Cannot read version\n");
        fclose(file);
        return 0;
    }
    
    // Read size (4 bytes)
    uint32_t size;
    if (fread(&size, 4, 1, file) != 1) {
        printf("Error: Cannot read size\n");
        fclose(file);
        return 0;
    }
    
    printf("Key: %08X, Version: %d, Size: %d bytes\n", key, version, size);
    
    // Read entry point from end of file
    long current_pos = ftell(file);
    fseek(file, -5, SEEK_END);  // Entry point is 4 bytes before the final 'O'
    uint32_t entry_point;
    if (fread(&entry_point, 4, 1, file) == 1) {
        printf("Entry point: $%04X (%d)\n", entry_point, entry_point);
    }
    fseek(file, current_pos, SEEK_SET);  // Restore position
    
    // Parse the file format step by step:
    // 1. Module name, key, version, size already read
    // 2. Skip import section
    while (1) {
        char ch;
        if (fread(&ch, 1, 1, file) != 1) break;
        if (ch == 0) break; // End of imports
        // Skip module name
        while (ch != 0) {
            if (fread(&ch, 1, 1, file) != 1) break;
        }
        // Skip module key (4 bytes)
        fseek(file, 4, SEEK_CUR);
    }
    
    // 3. Skip type descriptors
    uint32_t td_size;
    if (fread(&td_size, 4, 1, file) != 1) {
        printf("Error: Cannot read type descriptor size\n");
        fclose(file);
        return 0;
    }
    fseek(file, td_size, SEEK_CUR);
    
    // 4. Skip variable section
    uint32_t var_size;
    if (fread(&var_size, 4, 1, file) != 1) {
        printf("Error: Cannot read variable size\n");
        fclose(file);
        return 0;
    }
    
    // 5. Skip string section
    uint32_t str_size;
    if (fread(&str_size, 4, 1, file) != 1) {
        printf("Error: Cannot read string size\n");
        fclose(file);
        return 0;
    }
    fseek(file, str_size, SEEK_CUR);
    
    // 6. Read code section length
    uint32_t code_length;
    if (fread(&code_length, 4, 1, file) != 1) {
        printf("Error: Cannot read code length\n");
        fclose(file);
        return 0;
    }
    *code_size = code_length;
    *code_data = (uint8_t*)malloc(*code_size);
    if (!*code_data) {
        printf("Error: Cannot allocate memory for code\n");
        fclose(file);
        return 0;
    }
    
    printf("Code length: %d bytes\n", *code_size);
    
    if (fread(*code_data, 1, *code_size, file) != *code_size) {
        printf("Error: Cannot read code section\n");
        free(*code_data);
        fclose(file);
        return 0;
    }
    
    fclose(file);
    printf("Code section: %d bytes\n\n", *code_size);
    return 1;
}

// Main disassembler function
static void disassemble_code(uint8_t *code, int code_size) {
    int pc = 0;
    DisasmInstr instr;
    
    printf("Disassembly:\n");
    printf("Addr: Bytes        Instruction\n");
    printf("-----------------------------\n");
    
    while (pc < code_size) {
        int advance = disassemble_instruction(code, pc, &instr);
        print_instruction(&instr);
        pc += advance;
        
        // Safety check to prevent infinite loops
        if (advance == 0) {
            printf("Error: Zero-length instruction at PC %04X\n", pc);
            break;
        }
    }
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <file.816>\n", argv[0]);
        printf("Disassembles 65C816 compiled Oberon modules\n");
        return 1;
    }
    
    const char *filename = argv[1];
    uint8_t *code_data;
    int code_size;
    
    printf("65C816 Oberon Module Disassembler\n");
    printf("==================================\n\n");
    
    if (!parse_816_file(filename, &code_data, &code_size)) {
        return 1;
    }
    
    disassemble_code(code_data, code_size);
    
    free(code_data);
    return 0;
}