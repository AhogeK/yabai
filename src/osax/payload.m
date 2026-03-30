#include <Foundation/Foundation.h>

#include <mach-o/getsect.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach/vm_map.h>
#include <mach/vm_page_size.h>
#include <objc/message.h>
#include <objc/runtime.h>

#include <CoreGraphics/CoreGraphics.h>
#include <CoreGraphics/CGDirectDisplay.h>

// CoreGraphics UUID API (works in sandbox)
extern CFUUIDRef CGDisplayCreateUUIDFromDisplayID(uint32_t did);
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <sys/un.h>
#include <unistd.h>
#include <netdb.h>
#include <dlfcn.h>

#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "common.h"

#ifdef __x86_64__
#include "x64_payload.m"
#elif __arm64__
#include "arm64_payload.m"
#include <ptrauth.h>
#endif

#define HASHTABLE_IMPLEMENTATION
#include "../misc/hashtable.h"
#undef HASHTABLE_IMPLEMENTATION

#define page_align(addr) (vm_address_t)((uintptr_t)(addr) & (~(vm_page_size - 1)))
#define unpack(v) memcpy(&v, message, sizeof(v)); message += sizeof(v)
#define lerp(a, t, b) (((1.0-t)*a) + (t*b))

extern int SLSMainConnectionID(void);
extern CGError SLSGetConnectionPSN(int cid, ProcessSerialNumber *psn);
extern CGError SLSGetWindowAlpha(int cid, uint32_t wid, float *alpha);
extern CGError SLSSetWindowAlpha(int cid, uint32_t wid, float alpha);
extern OSStatus SLSMoveWindowWithGroup(int cid, uint32_t wid, CGPoint *point);
extern CGError SLSReassociateWindowsSpacesByGeometry(int cid, CFArrayRef window_list);
extern CGError SLSGetWindowOwner(int cid, uint32_t wid, int *window_cid);
extern CGError SLSSetWindowTags(int cid, uint32_t wid, uint64_t *tags, size_t tag_size);
extern CGError SLSClearWindowTags(int cid, uint32_t wid, uint64_t *tags, size_t tag_size);
extern CGError SLSGetWindowBounds(int cid, uint32_t wid, CGRect *frame);
extern CGError SLSGetWindowTransform(int cid, uint32_t wid, CGAffineTransform *t);
extern CGError SLSSetWindowTransform(int cid, uint32_t wid, CGAffineTransform t);
extern CGError SLSOrderWindow(int cid, uint32_t wid, int order, uint32_t rel_wid);
extern void SLSManagedDisplaySetCurrentSpace(int cid, CFStringRef display_ref, uint64_t sid);
extern uint64_t SLSManagedDisplayGetCurrentSpace(int cid, CFStringRef display_ref);
extern CFStringRef SLSCopyManagedDisplayForSpace(int cid, uint64_t sid);
extern void SLSMoveWindowsToManagedSpace(int cid, CFArrayRef window_list, uint64_t sid);
extern void SLSShowSpaces(int cid, CFArrayRef space_list);
extern void SLSHideSpaces(int cid, CFArrayRef space_list);
extern CFTypeRef SLSTransactionCreate(int cid);
extern CGError SLSTransactionCommit(CFTypeRef transaction, int synchronous);
extern CGError SLSTransactionOrderWindowGroup(CFTypeRef transaction, uint32_t wid, int order, uint32_t rel_wid);
extern CGError SLSTransactionSetWindowSystemAlpha(CFTypeRef transaction, uint32_t wid, float alpha);
extern CGError SLSSetWindowSubLevel(int cid, uint32_t wid, int level);

struct window_fade_context
{
    pthread_t thread;
    uint32_t wid;
    volatile float alpha;
    volatile float duration;
    volatile bool skip;
};

pthread_mutex_t window_fade_lock;
struct table window_fade_table;

static id dock_spaces;
static id dp_desktop_picture_manager;
static uint64_t add_space_fp;
static uint64_t remove_space_fp;
static uint64_t move_space_fp;
static uint64_t set_front_window_fp;
static uint64_t animation_time_addr;
static uint64_t space_create_entry_fp;
static bool macOSSequoia;

static pthread_t daemon_thread;
static int daemon_sockfd;

static void dump_class_info(Class c)
{
    const char *name = class_getName(c);
    unsigned int count = 0;

    Ivar *ivar_list = class_copyIvarList(c, &count);
    for (int i = 0; i < count; i++) {
        Ivar ivar = ivar_list[i];
        const char *ivar_name = ivar_getName(ivar);
        NSLog(@"%s ivar: %s", name, ivar_name);
    }
    if (ivar_list) free(ivar_list);

    objc_property_t *property_list = class_copyPropertyList(c, &count);
    for (int i = 0; i < count; i++) {
        objc_property_t property = property_list[i];
        const char *prop_name = property_getName(property);
        NSLog(@"%s property: %s", name, prop_name);
    }
    if (property_list) free(property_list);

    Method *method_list = class_copyMethodList(c, &count);
    for (int i = 0; i < count; i++) {
        Method method = method_list[i];
        const char *method_name = sel_getName(method_getName(method));
        NSLog(@"%s method: %s", name, method_name);
    }
    if (method_list) free(method_list);
}

static Class dump_class_info_by_name(const char *name)
{
    Class c = objc_getClass(name);
    if (c != nil) {
        dump_class_info(c);
    }
    return c;
}

static uint64_t static_base_address(void)
{
    const struct segment_command_64 *command = getsegbyname("__TEXT");
    uint64_t addr = command->vmaddr;
    return addr;
}

static uint64_t image_slide(void)
{
    char path[1024];
    uint32_t size = sizeof(path);

    if (_NSGetExecutablePath(path, &size) != 0) {
        return -1;
    }

    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if (strcmp(_dyld_get_image_name(i), path) == 0) {
            return _dyld_get_image_vmaddr_slide(i);
        }
    }

    return 0;
}

#if __arm64__
// Decode ADRP + ADD instruction pair to get data address
// Uses correct sign-extension for 21-bit ADRP immediate
static uint64_t decode_adrp_add_pair(uint32_t *pc)
{
    uint32_t adrp_ins = pc[0];
    uint32_t add_ins  = pc[1];

    // ADRP decoding: 21-bit immediate (immlo[2] + immhi[19])
    // immlo: bits 29-30 (2 bits)
    // immhi: bits 5-23 (19 bits, sign-extended)
    int64_t immlo = (adrp_ins >> 29) & 0x3;
    int64_t immhi = (int32_t)((adrp_ins >> 5) & 0x7ffff);  // Sign-extend bit 19

    // Concatenate and sign-extend: bit 20 is sign bit for 21-bit value
    int64_t adrp_imm = ((immhi << 2) | immlo);
    if (adrp_imm & 0x100000) {  // If bit 20 is 1 (negative)
        adrp_imm |= ~0x1fffff;   // Fill upper bits with 1s
    }
    adrp_imm <<= 12;  // Scale by 4KB page

    // ADD decoding: 12-bit immediate (bits 10-21)
    uint64_t add_imm = (add_ins >> 10) & 0xfff;

    // Calculate final address: page base + offsets
    uint64_t adrp_page = (uint64_t)pc & ~0xfffULL;
    return adrp_page + adrp_imm + add_imm;
}

// Decode ADRP + LDR instruction pair for DPPM singleton
// LDR (unsigned immediate) format: offset is in bits 10-21 (12-bit), scaled by 8 for 64-bit load
// Machine code feature bits: 0xF9400000 (LDR Xn, [Xm, #imm])
// Offset calculation: imm12 = (ldr_ins >> 10) & 0xfff; offset = imm12 << 3
static uint64_t decode_adrp_ldr_pair(uint32_t *pc)
{
    uint32_t adrp_ins = pc[0];
    uint32_t ldr_ins  = pc[1];

    // 1. Decode ADRP (same logic as decode_adrp_add_pair)
    int64_t immlo = (adrp_ins >> 29) & 0x3;
    int64_t immhi = (int32_t)((adrp_ins >> 5) & 0x7ffff);
    int64_t adrp_imm = ((immhi << 2) | immlo);
    if (adrp_imm & 0x100000) adrp_imm |= ~0x1fffff;
    adrp_imm <<= 12;

    // 2. Decode LDR immediate offset (12-bit unsigned, scaled by 8 for 64-bit load)
    // LDR (unsigned immediate) encoding: size=11 (64-bit), opc=01 (signed offset)
    // Bits 10-21 contain the 12-bit unsigned immediate
    uint64_t ldr_imm = ((ldr_ins >> 10) & 0xfff) << 3;

    // 3. Calculate final physical address
    uint64_t adrp_page = (uint64_t)pc & ~0xfffULL;
    return adrp_page + adrp_imm + ldr_imm;
}

// Find callers of addSpace and trace back to their singleton load
// Searches for BL instruction to target_func_addr, then backwards for adrp+add pair
static uint32_t *find_spaces_singleton_instructions(uint64_t baseaddr, uint64_t slide, uint64_t target_func_addr)
{
    // UI logic lives in mid-to-late section
    uint8_t *ptr = (uint8_t *)(baseaddr + slide + 0x100000);
    uint8_t *end = (uint8_t *)(baseaddr + slide + 0x400000);
    
    for (uint8_t *p = ptr; p < end - 100; p += 4) {
        uint32_t *ins = (uint32_t *)p;
        
        // 1. Search for BL instruction (opcode 0x94000000)
        if ((ins[0] & 0xfc000000) == 0x94000000) {
            // 2. Decode BL target address
            // BL encoding: imm26 (26-bit signed offset, scaled by 4)
            int32_t imm26 = (int32_t)((ins[0] & 0x03ffffff) << 6) >> 6;  // Sign-extend
            uint64_t bl_target = (uint64_t)ins + (imm26 << 2);
            
            // 3. If BL target is exactly our addSpace function
            if (bl_target == target_func_addr) {
                // 4. Search BACKWARDS 10 instructions for nearest adrp+add pair
                for (int j = -1; j > -10; j--) {
                    // Check ADRP (feature bits 0x90000000)
                    if ((ins[j] & 0x9f000000) == 0x90000000) {
                        // Check ADD (feature bits 0x91000000)
                        if ((ins[j+1] & 0xff000000) == 0x91000000) {
                            // Validate: ADRP dest register must equal ADD source register
                            int adrp_rd = (ins[j] & 0x1f);
                            int add_rn = (ins[j+1] >> 5) & 0x1f;
                            if (adrp_rd == add_rn) {
                                return &ins[j];  // Success! Found the caller's singleton load
                            }
                        }
                    }
                }
            }
        }
    }
    return NULL;
}

// Find setDesktopPictureManager function and extract DPPM singleton pointer
// Uses behavioral fingerprint (cbnz + str) to eliminate false Setter matches
// First 6 instructions are generic ObjC Setter template, so we validate 10 consecutive
// instructions with complete data flow verification for unique identification
//
// Fingerprint from Ghidra analysis of FUN_10011cd90:
//   ins[6]: adrp x8, 0x100488000
//   ins[7]: ldr x0, [x8, #0xd0]      - Load current singleton to x0
//   ins[8]: cbnz x0, LAB_CRASH       - If not nil, jump to crash logic
//   ins[9]: str x19, [x8, #0xd0]     - If nil, store retained x19 to singleton
//
// The check-nil/crash-if-not-nil/store-if-nil pattern identifies DPPM singleton init
static uint32_t *find_dppm_singleton_instructions(uint64_t baseaddr, uint64_t slide)
{
    uint8_t *ptr = (uint8_t *)(baseaddr + slide + 0x100000);
    uint8_t *end = (uint8_t *)(baseaddr + slide + 0x400000);

    for (uint8_t *p = ptr; p < end - 40; p += 4) {
        uint32_t *ins = (uint32_t *)p;

        // 1. Verify generic Setter prologue (first 6 instructions)
        // These exact values come from Ghidra disassembly of setDesktopPictureManager:
        if (ins[0] != 0xd503237f) continue;  // pacibsp
        if (ins[1] != 0xa9be4ff4) continue;  // stp x20, x19, [sp, #-0x20]!
        if (ins[2] != 0xa9017bfd) continue;  // stp x29, x30, [sp, #0x10]
        if (ins[3] != 0x910043fd) continue;  // add x29, sp, #0x10
        if (ins[4] != 0xaa0003f3) continue;  // mov x19, x0
        if ((ins[5] & 0xfc000000) != 0x94000000) continue; // bl _objc_retain

        // 2. Verify ADRP (load page base address)
        // Machine code: 0x90000000 family (mask 0x9f000000 to ignore register)
        if ((ins[6] & 0x9f000000) != 0x90000000) continue;
        int adrp_rd = ins[6] & 0x1f;  // Extract destination register (e.g., x8)

        // 3. Verify LDR (load current singleton value to x0)
        // Machine code: 0xF9400000 (LDR Xn, [Xm, #imm]) - mask 0xffc00000
        if ((ins[7] & 0xffc00000) != 0xf9400000) continue;
        int ldr_rn = (ins[7] >> 5) & 0x1f;  // Base register (address source)
        int ldr_rt = ins[7] & 0x1f;         // Target register (value destination)

        // Verify CBNZ instruction (behavioral fingerprint 1)
        // Machine code: 0xB5000000 (CBNZ Xn, #imm) - mask 0xff000000
        // Generic setters don't crash on double-set, making this a unique marker
        if ((ins[8] & 0xff000000) != 0xb5000000) continue;
        int cbnz_rt = ins[8] & 0x1f;  // Register being checked for nil

        // Verify STR instruction (behavioral fingerprint 2)
        // Machine code: 0xF9000000 (STR Xt, [Xn, #imm]) - mask 0xffc00000
        if ((ins[9] & 0xffc00000) != 0xf9000000) continue;
        int str_rn = (ins[9] >> 5) & 0x1f;  // Base register (destination address)
        int str_rt = ins[9] & 0x1f;         // Source register (value to store)

        // Validate complete data flow to ensure unique match
        // All instructions must operate on the same variable
        if (adrp_rd == ldr_rn &&      // LDR uses address computed by ADRP
            ldr_rt == 0 &&            // LDR loads value to x0 (standard for nil-check)
            cbnz_rt == 0 &&           // CBNZ checks the value just loaded (x0)
            str_rn == adrp_rd &&      // STR writes back to same memory address (singleton)
            str_rt == 19) {           // STR writes x19 (the retained object we're setting)

            return &ins[6];  // Return adrp instruction address
        }
    }
    return NULL;
}
#endif

static uint64_t hex_find_seq(uint64_t baddr, const char *c_pattern)
{
    if (!baddr || !c_pattern) return 0;

    uint64_t addr = baddr;
    uint64_t pattern_length = (strlen(c_pattern) + 1) / 3;
    char buffer_a[pattern_length];
    char buffer_b[pattern_length];
    memset(buffer_a, 0, sizeof(buffer_a));
    memset(buffer_b, 0, sizeof(buffer_b));

    char *pattern = (char *) c_pattern + 1;
    for (int i = 0; i < pattern_length; ++i) {
        char c = pattern[-1];
        if (c == '?') {
            buffer_b[i] = 1;
        } else {
            int temp = c <= '9' ? 0 : 9;
            temp = (temp + c) << 0x4;
            c = pattern[0];
            int temp2 = c <= '9' ? 0xd0 : 0xc9;
            buffer_a[i] = temp2 + c + temp;
        }
        pattern += 3;
    }

loop:
    for (int counter = 0; counter < pattern_length; ++counter) {
        if ((buffer_b[counter] == 0) && (((char *)addr)[counter] != buffer_a[counter])) {
            addr = (uint64_t)((char *)addr + 1);
            if (addr - baddr < 0x1286a0) {
                goto loop;
            } else {
                return 0;
            }
        }
    }

    return addr;
}

#if __arm64__
uint64_t decode_adrp_add(uint64_t addr, uint64_t offset)
{
    uint32_t adrp_instr = *(uint32_t *) addr;

    uint32_t immlo = (0x60000000 & adrp_instr) >> 29;
    uint32_t immhi = (0xffffe0 & adrp_instr) >> 3;

    int32_t value = (immhi | immlo) << 12;
    int64_t value_64 = value;

    uint32_t add_instr = *(uint32_t *) (addr + 4);
    uint64_t imm12 = (add_instr & 0x3ffc00) >> 10;

    if (add_instr & 0xc00000) {
        imm12 <<= 12;
    }

    return (offset & 0xfffffffffffff000) + value_64 + imm12;
}
#endif

static bool verify_os_version(NSOperatingSystemVersion os_version)
{
    NSLog(@"[yabai-sa] checking for macOS %ld.%ld.%ld compatibility!", os_version.majorVersion, os_version.minorVersion, os_version.patchVersion);

#ifdef __x86_64__
    if (os_version.majorVersion == 11) {
        return true; // Big Sur 11.0
    } else if (os_version.majorVersion == 12) {
        return true; // Monterey 12.0
    } else if (os_version.majorVersion == 13) {
        return true; // Ventura 13.0
    } else if (os_version.majorVersion == 14) {
        return true; // Sonoma 14.0
    } else if (os_version.majorVersion == 15) {
        macOSSequoia = true;
        return true; // Sequoia 15.0
    } else if (os_version.majorVersion == 26) {

        NSLog(@"[yabai-sa] Detected Tahoe Preview... flagging 'macOSSequoia=true.'");
        macOSSequoia = true;
        return true; // Tahoe preview
    }

    NSLog(@"[yabai-sa] spaces functionality is only supported on macOS Big Sur 11.0.0+, Monterey 12.0.0+, Ventura 13.0.0+, Sonoma 14.0.0+, and Sequoia 15.0");
#elif __arm64__
    if (os_version.majorVersion == 12) {
        return true; // Monterey 12.0
    } else if (os_version.majorVersion == 13) {
        return true; // Ventura 13.0
    } else if (os_version.majorVersion == 14) {
        return true; // Sonoma 14.0
    } else if (os_version.majorVersion == 15) {
        macOSSequoia = true;
        return true; // Sequoia 15.0
    } else if (os_version.majorVersion == 26) {

        NSLog(@"[yabai-sa] Detected Tahoe Preview... flagging 'macOSSequoia=true.'");
        macOSSequoia = true;
        return true; // Tahoe preview
    }

    NSLog(@"[yabai-sa] spaces functionality is only supported on macOS Monterey 12.0.0+, and Ventura 13.0.0+, Sonoma 14.0.0+, and Sequoia 15.0");
#endif

    return false;
}

static void init_instances()
{
    NSOperatingSystemVersion os_version = [[NSProcessInfo processInfo] operatingSystemVersion];
    if (!verify_os_version(os_version)) return;

    uint64_t baseaddr = static_base_address() + image_slide();

    uint64_t dock_spaces_addr = hex_find_seq(baseaddr + get_dock_spaces_offset(os_version), get_dock_spaces_pattern(os_version));
    if (dock_spaces_addr == 0) {
        dock_spaces = nil;
        NSLog(@"[yabai-sa] could not locate pointer to dock.spaces! spaces functionality will not work!");
    } else {
#ifdef __x86_64__
        uint32_t dock_spaces_offset = *(int32_t *)dock_spaces_addr;
        NSLog(@"[yabai-sa] (0x%llx) dock.spaces found at address 0x%llX (0x%llx)", baseaddr, dock_spaces_addr, dock_spaces_addr - baseaddr);
        dock_spaces = [(*(id *)(dock_spaces_addr + dock_spaces_offset + 0x4)) retain];
#elif __arm64__
        uint64_t dock_spaces_offset = decode_adrp_add(dock_spaces_addr, dock_spaces_addr - baseaddr);
        NSLog(@"[yabai-sa] (0x%llx) dock.spaces found at address 0x%llX (0x%llx)", baseaddr, dock_spaces_offset, dock_spaces_offset - baseaddr);
        dock_spaces = [(*(id *)(baseaddr + dock_spaces_offset)) retain];
#endif
    }

#ifdef __arm64__
    // macOS 26: Try control-flow fingerprint FIRST
    if (macOSSequoia) {
        uint32_t *dppm_pattern = find_dppm_singleton_instructions(baseaddr, 0);
        if (dppm_pattern) {
            uintptr_t dppm_global_ptr = (uintptr_t)decode_adrp_ldr_pair(dppm_pattern);
            id dppm_singleton = *(id *)dppm_global_ptr;

            NSLog(@"[yabai-sa][DPPM] Located via control-flow fingerprint: ptr=0x%llx (offset 0x%llx), instance=%p",
                  (uint64_t)dppm_global_ptr,
                  (uint64_t)(dppm_global_ptr - baseaddr),
                  (void *)dppm_singleton);

            if (dppm_singleton) {
                dp_desktop_picture_manager = [dppm_singleton retain];
                goto dppm_done;  // Skip asmvik's entire dppm block
            }
        }
        NSLog(@"[yabai-sa][DPPM] Control-flow fingerprint failed, falling back to pattern scan");
    }
#endif

    {  // Wrap asmvik's dppm block
    uint64_t dppm_addr = hex_find_seq(baseaddr + get_dppm_offset(os_version), get_dppm_pattern(os_version));
    if (dppm_addr == 0) {
        NSLog(@"[yabai-sa] could not locate pointer to dppm! moving spaces will not work!");
    } else {
#ifdef __x86_64__
        uint32_t dppm_offset = *(int32_t *)dppm_addr;
        NSLog(@"[yabai-sa] (0x%llx) dppm found at address 0x%llX (0x%llx)", baseaddr, dppm_addr, dppm_addr - baseaddr);
        dp_desktop_picture_manager = [(*(id *)(dppm_addr + dppm_offset + 0x4)) retain];
#elif __arm64__
        uint64_t dppm_offset = decode_adrp_add(dppm_addr, dppm_addr - baseaddr);
        NSLog(@"[yabai-sa] (0x%llx) dppm found at address 0x%llX (0x%llx)", baseaddr, dppm_offset, dppm_offset - baseaddr);
        dp_desktop_picture_manager = [(*(id *)(baseaddr + dppm_offset)) retain];
#endif

        //
        // @hack
        //
        // NOTE(asmvik): For whatever reason, in Sonoma, DPDesktopPictureManager is initialized and swapped
        // to an alternate storage location instead of where it used to be stored in previous macOS versions..
        //
        // This alternate storage location resides 8-bytes before the usual location, so we simply do
        // the subtract to arrive at the correct location in cases where the usual location is null.
        //

#ifdef __x86_64__
        if (dp_desktop_picture_manager == nil) {
            dp_desktop_picture_manager = [(*(id *)(dppm_addr + dppm_offset + 0x4 - 0x8)) retain];
        }
#elif __arm64__
        if (dp_desktop_picture_manager == nil) {
            dp_desktop_picture_manager = [(*(id *)(baseaddr + dppm_offset - 0x8)) retain];
        }
#endif
    }
    }  // End wrap of asmvik's dppm block
    dppm_done: ;  // Empty statement required after label in C

    uint64_t add_space_addr = hex_find_seq(baseaddr + get_add_space_offset(os_version), get_add_space_pattern(os_version));
    if (add_space_addr == 0x0) {
        NSLog(@"[yabai-sa] failed to get pointer to addSpace function..");
        add_space_fp = 0;
    } else {
        NSLog(@"[yabai-sa] (0x%llx) addSpace found at address 0x%llX (0x%llx)", baseaddr, add_space_addr, add_space_addr - baseaddr);
#ifdef __x86_64__
        add_space_fp = add_space_addr;
#elif __arm64__
        add_space_fp = (uint64_t) ptrauth_sign_unauthenticated((void *) add_space_addr, ptrauth_key_asia, 0);
#endif
    }

    uint64_t remove_space_addr = hex_find_seq(baseaddr + get_remove_space_offset(os_version), get_remove_space_pattern(os_version));
    if (remove_space_addr == 0x0) {
        NSLog(@"[yabai-sa] failed to get pointer to removeSpace function..");
        remove_space_fp = 0;
    } else {
        NSLog(@"[yabai-sa] (0x%llx) removeSpace found at address 0x%llX (0x%llx)", baseaddr, remove_space_addr, remove_space_addr - baseaddr);
#ifdef __x86_64__
        remove_space_fp = remove_space_addr;
#elif __arm64__
        remove_space_fp = (uint64_t) ptrauth_sign_unauthenticated((void *) remove_space_addr, ptrauth_key_asia, 0);
#endif
    }

    uint64_t move_space_addr = hex_find_seq(baseaddr + get_move_space_offset(os_version), get_move_space_pattern(os_version));
    if (move_space_addr == 0x0) {
        NSLog(@"[yabai-sa] failed to get pointer to moveSpace function..");
        move_space_fp = 0;
    } else {
        NSLog(@"[yabai-sa] (0x%llx) moveSpace found at address 0x%llX (0x%llx)", baseaddr, move_space_addr, move_space_addr - baseaddr);
#ifdef __x86_64__
        move_space_fp = move_space_addr;
#elif __arm64__
        move_space_fp = (uint64_t) ptrauth_sign_unauthenticated((void *) move_space_addr, ptrauth_key_asia, 0);
#endif
    }

    uint64_t set_front_window_addr = hex_find_seq(baseaddr + get_set_front_window_offset(os_version), get_set_front_window_pattern(os_version));
    if (set_front_window_addr == 0x0) {
        NSLog(@"[yabai-sa] failed to get pointer to setFrontWindow function..");
        set_front_window_fp = 0;
    } else {
        NSLog(@"[yabai-sa] (0x%llx) setFrontWindow found at address 0x%llX (0x%llx)", baseaddr, set_front_window_addr, set_front_window_addr - baseaddr);
#ifdef __x86_64__
        set_front_window_fp = set_front_window_addr;
#elif __arm64__
        set_front_window_fp = (uint64_t) ptrauth_sign_unauthenticated((void *) set_front_window_addr, ptrauth_key_asia, 0);
#endif
    }

    animation_time_addr = hex_find_seq(baseaddr + get_fix_animation_offset(os_version), get_fix_animation_pattern(os_version));
    if (animation_time_addr == 0x0) {
        NSLog(@"[yabai-sa] failed to get pointer to animation-time..");
    } else {
        NSLog(@"[yabai-sa] (0x%llx) animation_time_addr found at address 0x%llX (0x%llx)", baseaddr, animation_time_addr, animation_time_addr - baseaddr);
        if (vm_protect(mach_task_self(), page_align(animation_time_addr), vm_page_size, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) == KERN_SUCCESS) {
#ifdef __x86_64__
            *(uint64_t *) animation_time_addr = 0x660fefc0660fefc0;
#elif __arm64__
            *(uint32_t *) animation_time_addr = 0x2f00e400;
#endif
            vm_protect(mach_task_self(), page_align(animation_time_addr), vm_page_size, 0, VM_PROT_READ | VM_PROT_EXECUTE);
        } else {
            NSLog(@"[yabai-sa] animation_time_addr vm_protect failed; unable to patch instruction!");
        }
    }

#ifdef __arm64__
    // macOS 26: Initialize space_create_entry_fp for direct call to 0x1f07d8
    if (os_version.majorVersion >= 26) {
        uint64_t space_create_offset = get_space_create_entry_offset(os_version);
        if (space_create_offset != 0) {
            uint64_t space_create_addr = baseaddr + space_create_offset;
            NSLog(@"[yabai-sa] (0x%llx) space_create_entry found at 0x%llX (offset 0x%llx)",
                  baseaddr, space_create_addr, space_create_offset);
            space_create_entry_fp = space_create_addr;
        } else {
            space_create_entry_fp = 0;
            NSLog(@"[yabai-sa] No space_create_entry offset for macOS %ld", (long)os_version.majorVersion);
        }
    }

    // macOS 26: Dynamic address decoding for DPPM singleton
    // Uses ADRP+LDR pattern from setDesktopPictureManager function (FUN_10011cd90)
    if (os_version.majorVersion >= 26) {
        uint32_t *dppm_pattern = find_dppm_singleton_instructions(baseaddr, 0);
        if (dppm_pattern) {
            uintptr_t dppm_global_ptr = (uintptr_t)decode_adrp_ldr_pair(dppm_pattern);
            id dppm_singleton = *(id *)dppm_global_ptr;

            NSLog(@"[yabai-sa][DPPM] SUCCESS: Decoded dppm ptr=0x%llx (offset 0x%llx), instance=%p",
                  (uint64_t)dppm_global_ptr,
                  (uint64_t)(dppm_global_ptr - baseaddr),
                  (void *)dppm_singleton);

            // Override the hex_find_seq result with dynamically decoded address
            if (dppm_singleton) {
                dp_desktop_picture_manager = [dppm_singleton retain];
            } else {
                NSLog(@"[yabai-sa][DPPM] WARNING: DPPM singleton is nil at decoded address");
            }
        } else {
            NSLog(@"[yabai-sa][DPPM] ERROR: Could not find DPPM instructions");
        }
    }
#endif
}

static inline id get_ivar_value(id instance, const char *name)
{
    id result = nil;
    object_getInstanceVariable(instance, name, (void **) &result);
    return result;
}

static inline void set_ivar_value(id instance, const char *name, id value)
{
    object_setInstanceVariable(instance, name, value);
}

static inline uint64_t get_space_id(id space)
{
    return ((uint64_t (*)(id, SEL)) objc_msgSend)(space, @selector(spid));
}

static inline id space_for_display_with_id(CFStringRef display_uuid, uint64_t space_id)
{
    NSArray *spaces_for_display = ((NSArray *(*)(id, SEL, CFStringRef)) objc_msgSend)(dock_spaces, @selector(spacesForDisplay:), display_uuid);
    for (id space in spaces_for_display) {
        if (space_id == get_space_id(space)) {
            return space;
        }
    }
    return nil;
}

static inline id display_space_for_display_uuid(CFStringRef display_uuid)
{
    id result = nil;

    NSArray *display_spaces = get_ivar_value(dock_spaces, "_displaySpaces");
    if (display_spaces != nil) {
        for (id display_space in display_spaces) {
            id display_source_space = get_ivar_value(display_space, "_currentSpace");
            uint64_t sid = get_space_id(display_source_space);
            CFStringRef uuid = SLSCopyManagedDisplayForSpace(SLSMainConnectionID(), sid);
            bool match = CFEqual(uuid, display_uuid);
            CFRelease(uuid);
            if (match) {
                result = display_space;
                break;
            }
        }
    }

    return result;
}

static inline id display_space_for_space_with_id(uint64_t space_id)
{
    NSArray *display_spaces = get_ivar_value(dock_spaces, "_displaySpaces");
    if (display_spaces != nil) {
        for (id display_space in display_spaces) {
            id display_source_space = get_ivar_value(display_space, "_currentSpace");
            if (get_space_id(display_source_space) == space_id) {
                return display_space;
            }
        }
    }
    return nil;
}

static void do_space_move(char *message)
{
    if (dock_spaces == nil || dp_desktop_picture_manager == nil || move_space_fp == 0) return;

    uint64_t source_space_id, dest_space_id, source_prev_space_id;
    unpack(source_space_id);
    unpack(dest_space_id);
    unpack(source_prev_space_id);

    bool focus_dest_space;
    unpack(focus_dest_space);

    CFStringRef source_display_uuid = SLSCopyManagedDisplayForSpace(SLSMainConnectionID(), source_space_id);
    id source_space = space_for_display_with_id(source_display_uuid, source_space_id);
    id source_display_space = display_space_for_display_uuid(source_display_uuid);

    CFStringRef dest_display_uuid = SLSCopyManagedDisplayForSpace(SLSMainConnectionID(), dest_space_id);
    id dest_space = space_for_display_with_id(dest_display_uuid, dest_space_id);
    unsigned dest_display_id = ((unsigned (*)(id, SEL, id)) objc_msgSend)(dock_spaces, @selector(displayIDForSpace:), dest_space);
    id dest_display_space = display_space_for_display_uuid(dest_display_uuid);

    if (source_prev_space_id) {
        NSArray *ns_source_space = @[ @(source_space_id) ];
        NSArray *ns_dest_space = @[ @(source_prev_space_id) ];
        id new_source_space = space_for_display_with_id(source_display_uuid, source_prev_space_id);
        SLSShowSpaces(SLSMainConnectionID(), (__bridge CFArrayRef) ns_dest_space);
        SLSHideSpaces(SLSMainConnectionID(), (__bridge CFArrayRef) ns_source_space);
        SLSManagedDisplaySetCurrentSpace(SLSMainConnectionID(), source_display_uuid, source_prev_space_id);
        set_ivar_value(source_display_space, "_currentSpace", [new_source_space retain]);
        [ns_dest_space release];
        [ns_source_space release];
    }

    asm__call_move_space(source_space, dest_space, dest_display_uuid, dock_spaces, move_space_fp);

    dispatch_sync(dispatch_get_main_queue(), ^{
        ((void (*)(id, SEL, id, unsigned, CFStringRef)) objc_msgSend)(dp_desktop_picture_manager, @selector(moveSpace:toDisplay:displayUUID:), source_space, dest_display_id, dest_display_uuid);
    });

    if (focus_dest_space) {
        uint64_t new_source_space_id = SLSManagedDisplayGetCurrentSpace(SLSMainConnectionID(), source_display_uuid);
        id new_source_space = space_for_display_with_id(source_display_uuid, new_source_space_id);
        set_ivar_value(source_display_space, "_currentSpace", [new_source_space retain]);

        NSArray *ns_dest_monitor_space = @[ @(dest_space_id) ];
        SLSHideSpaces(SLSMainConnectionID(), (__bridge CFArrayRef) ns_dest_monitor_space);
        SLSManagedDisplaySetCurrentSpace(SLSMainConnectionID(), dest_display_uuid, source_space_id);
        set_ivar_value(dest_display_space, "_currentSpace", [source_space retain]);
        [ns_dest_monitor_space release];
    }

    CFRelease(source_display_uuid);
    CFRelease(dest_display_uuid);
}

typedef void (*remove_space_call)(id space, id display_space, id dock_spaces, uint64_t space_id1, uint64_t space_id2);
static void do_space_destroy(char *message)
{
    if (dock_spaces == nil || remove_space_fp == 0) return;

    uint64_t space_id;
    unpack(space_id);

    CFStringRef display_uuid = SLSCopyManagedDisplayForSpace(SLSMainConnectionID(), space_id);
    uint64_t active_space_id = SLSManagedDisplayGetCurrentSpace(SLSMainConnectionID(), display_uuid);

    id space = space_for_display_with_id(display_uuid, space_id);
    id display_space = display_space_for_display_uuid(display_uuid);

    dispatch_sync(dispatch_get_main_queue(), ^{
        ((remove_space_call) remove_space_fp)(space, display_space, dock_spaces, space_id, space_id);
    });

    if (active_space_id == space_id) {
        uint64_t dest_space_id = SLSManagedDisplayGetCurrentSpace(SLSMainConnectionID(), display_uuid);
        id dest_space = space_for_display_with_id(display_uuid, dest_space_id);
        set_ivar_value(display_space, "_currentSpace", [dest_space retain]);
    }

    CFRelease(display_uuid);
}

// Convert display UUID string to CGDirectDisplayID
// Uses CoreGraphics UUID API (works in Dock sandbox)
static CGDirectDisplayID display_id_for_uuid(CFStringRef display_uuid)
{
    uint32_t display_count = 0;
    CGGetActiveDisplayList(0, NULL, &display_count);
    if (display_count == 0) return CGMainDisplayID();

    CGDirectDisplayID displays[display_count];
    CGGetActiveDisplayList(display_count, displays, &display_count);

    for (uint32_t i = 0; i < display_count; i++) {
        CFUUIDRef uuid_ref = CGDisplayCreateUUIDFromDisplayID(displays[i]);
        if (!uuid_ref) continue;

        CFStringRef uuid_str = CFUUIDCreateString(kCFAllocatorDefault, uuid_ref);
        CFRelease(uuid_ref);
        if (!uuid_str) continue;

        bool match = CFEqual(uuid_str, display_uuid);
        CFRelease(uuid_str);

        if (match) return displays[i];
    }

    NSLog(@"[yabai-sa][SPACE] WARNING: no display matched UUID, falling back to main display");
    return CGMainDisplayID();
}

static void do_space_create(char *message)
{
    if (dock_spaces == nil) return;

    uint64_t space_id;
    unpack(space_id);

    CFStringRef __block display_uuid = SLSCopyManagedDisplayForSpace(SLSMainConnectionID(), space_id);
    if (!display_uuid) return;

#ifdef __arm64__
    // macOS 26 Tahoe: direct call to space_create_entry
    // Swift calling convention: x0 = display_id (int32_t), x20 = Spaces singleton (self)
    if (macOSSequoia && space_create_entry_fp != 0) {
        // Use pre-computed function pointer from init_instances
        uint64_t space_create_addr = space_create_entry_fp;

        // Dynamically decode Spaces singleton address using ADRP+ADD pattern matching
        // Anchor: pacibsp + stp sequence in HotCorners::_handleEvents function prologue
        uint64_t baseaddr = static_base_address() + image_slide();
        uint32_t *pattern = find_spaces_singleton_instructions(baseaddr, 0, space_create_entry_fp);
        if (!pattern) {
            NSLog(@"[yabai-sa][SPACE] ERROR: Could not find Spaces singleton instructions");
            CFRelease(display_uuid);
            return;
        }

        // Log the matched instructions for verification against Ghidra output
        NSLog(@"[yabai-sa][SPACE] Found instructions: 0x%08x 0x%08x at %p",
              pattern[0], pattern[1], (void *)pattern);

        uintptr_t spaces_global_ptr = (uintptr_t)decode_adrp_add_pair(pattern);
        NSLog(@"[yabai-sa][SPACE] Decoded Spaces singleton ptr=0x%llx from instructions at %p",
              (uint64_t)spaces_global_ptr, (void *)pattern);

        id spaces_singleton = *(id *)spaces_global_ptr;

        NSLog(@"[yabai-sa][SPACE] singleton=%p func=0x%llx",
              (void *)spaces_singleton, space_create_addr);

        if (!spaces_singleton) {
            NSLog(@"[yabai-sa][SPACE] ERROR: Spaces singleton is nil, aborting");
            CFRelease(display_uuid);
            return;
        }

        // Mirror what Frame1 does: retain before call, release after
        // Native: <+84>: bl objc_retain  <+88>: mov x20, x0
        id retained = [spaces_singleton retain];
        CGDirectDisplayID display_id = display_id_for_uuid(display_uuid);

        NSLog(@"[yabai-sa][SPACE] calling space_create_entry(display_id=%u) retained=%p",
              display_id, (void *)retained);

        dispatch_sync(dispatch_get_main_queue(), ^{
            asm__call_space_create_tahoe((uint32_t)display_id, retained, space_create_addr);
        });

        [retained release];

        NSLog(@"[yabai-sa][SPACE] space_create_entry returned");
        CFRelease(display_uuid);
        return;
    }
#endif

    // Original path (macOS 15 and below)
    if (add_space_fp == 0) {
        CFRelease(display_uuid);
        return;
    }

    dispatch_sync(dispatch_get_main_queue(), ^{
        id new_space = macOSSequoia
                     ? [[objc_getClass("ManagedSpace") alloc] init]
                     : [[objc_getClass("Dock.ManagedSpace") alloc] init];
        id display_space = display_space_for_display_uuid(display_uuid);
        asm__call_add_space(new_space, display_space, add_space_fp);
        CFRelease(display_uuid);
    });
}

static void do_space_focus(char *message)
{
    if (dock_spaces == nil) return;

    uint64_t dest_space_id;
    unpack(dest_space_id);

    if (dest_space_id) {
        CFStringRef dest_display = SLSCopyManagedDisplayForSpace(SLSMainConnectionID(), dest_space_id);
        id source_space = macOSSequoia
                        ? ((id (*)(id, SEL, CFStringRef)) objc_msgSend)(dock_spaces, @selector(currentSpaceForDisplayUUID:), dest_display)
                        : ((id (*)(id, SEL, CFStringRef)) objc_msgSend)(dock_spaces, @selector(currentSpaceforDisplayUUID:), dest_display);
        uint64_t source_space_id = get_space_id(source_space);

        if (source_space_id != dest_space_id) {
            id dest_space = space_for_display_with_id(dest_display, dest_space_id);
            if (dest_space != nil) {
                id display_space = display_space_for_space_with_id(source_space_id);
                if (display_space != nil) {
                    NSArray *ns_source_space = @[ @(source_space_id) ];
                    NSArray *ns_dest_space = @[ @(dest_space_id) ];
                    SLSShowSpaces(SLSMainConnectionID(), (__bridge CFArrayRef) ns_dest_space);
                    SLSHideSpaces(SLSMainConnectionID(), (__bridge CFArrayRef) ns_source_space);
                    SLSManagedDisplaySetCurrentSpace(SLSMainConnectionID(), dest_display, dest_space_id);
                    set_ivar_value(display_space, "_currentSpace", [dest_space retain]);
                    [ns_dest_space release];
                    [ns_source_space release];
                }
            }
        }

        CFRelease(dest_display);
    }
}

static void do_window_scale(char *message)
{
    uint32_t wid;
    unpack(wid);
    if (!wid) return;

    CGRect frame = {};
    SLSGetWindowBounds(SLSMainConnectionID(), wid, &frame);
    CGAffineTransform original_transform = CGAffineTransformMakeTranslation(-frame.origin.x, -frame.origin.y);

    CGAffineTransform current_transform;
    SLSGetWindowTransform(SLSMainConnectionID(), wid, &current_transform);

    if (CGAffineTransformEqualToTransform(current_transform, original_transform)) {
        float dx, dy, dw, dh;
        unpack(dx);
        unpack(dy);
        unpack(dw);
        unpack(dh);

        int target_width  = dw / 4;
        int target_height = target_width / (frame.size.width/frame.size.height);

        float x_scale = frame.size.width/target_width;
        float y_scale = frame.size.height/target_height;

        CGFloat transformed_x = -(dx+dw) + (frame.size.width * (1/x_scale));
        CGFloat transformed_y = -dy;

        CGAffineTransform scale = CGAffineTransformConcat(CGAffineTransformIdentity, CGAffineTransformMakeScale(x_scale, y_scale));
        CGAffineTransform transform = CGAffineTransformTranslate(scale, transformed_x, transformed_y);
        SLSSetWindowTransform(SLSMainConnectionID(), wid, transform);
    } else {
        SLSSetWindowTransform(SLSMainConnectionID(), wid, original_transform);
    }
}

static void do_window_move(char *message)
{
    uint32_t wid;
    unpack(wid);
    if (!wid) return;

    int x, y;
    unpack(x);
    unpack(y);

    CGPoint point = CGPointMake(x, y);
    SLSMoveWindowWithGroup(SLSMainConnectionID(), wid, &point);

    NSArray *window_list = @[ @(wid) ];
    SLSReassociateWindowsSpacesByGeometry(SLSMainConnectionID(), (__bridge CFArrayRef) window_list);
    [window_list release];
}

static void do_window_opacity(char *message)
{
    uint32_t wid;
    unpack(wid);
    if (!wid) return;

    float alpha;
    unpack(alpha);

    pthread_mutex_lock(&window_fade_lock);
    struct window_fade_context *context = table_find(&window_fade_table, &wid);

    if (context) {
        context->alpha = alpha;
        context->duration = 0.0f;
        __asm__ __volatile__ ("" ::: "memory");

        context->skip = true;
        pthread_mutex_unlock(&window_fade_lock);
    } else {
        SLSSetWindowAlpha(SLSMainConnectionID(), wid, alpha);
        pthread_mutex_unlock(&window_fade_lock);
    }
}

static void *window_fade_thread_proc(void *data)
{
entry:;
    struct window_fade_context *context = (struct window_fade_context *) data;
    context->skip  = false;

    float start_alpha;
    float end_alpha = context->alpha;
    SLSGetWindowAlpha(SLSMainConnectionID(), context->wid, &start_alpha);

    int frame_duration = 8;
    int total_duration = (int)(context->duration * 1000.0f);
    int frame_count = (int)(((float) total_duration / (float) frame_duration) + 1.0f);

    for (int frame_index = 1; frame_index <= frame_count; ++frame_index) {
        if (context->skip) goto entry;

        float t = (float) frame_index / (float) frame_count;
        if (t < 0.0f) t = 0.0f;
        if (t > 1.0f) t = 1.0f;

        float alpha = lerp(start_alpha, t, end_alpha);
        SLSSetWindowAlpha(SLSMainConnectionID(), context->wid, alpha);

        usleep(frame_duration*1000);
    }

    pthread_mutex_lock(&window_fade_lock);
    if (!context->skip) {
        table_remove(&window_fade_table, &context->wid);
        pthread_mutex_unlock(&window_fade_lock);
        free(context);
        return NULL;
    }
    pthread_mutex_unlock(&window_fade_lock);

    goto entry;
}

static void do_window_opacity_fade(char *message)
{
    uint32_t wid;
    unpack(wid);
    if (!wid) return;

    float alpha, duration;
    unpack(alpha);
    unpack(duration);

    pthread_mutex_lock(&window_fade_lock);
    struct window_fade_context *context = table_find(&window_fade_table, &wid);

    if (context) {
        context->alpha = alpha;
        context->duration = duration;
        __asm__ __volatile__ ("" ::: "memory");

        context->skip = true;
        pthread_mutex_unlock(&window_fade_lock);
    } else {
        context = malloc(sizeof(struct window_fade_context));
        context->wid = wid;
        context->alpha = alpha;
        context->duration = duration;
        context->skip = false;
        __asm__ __volatile__ ("" ::: "memory");

        table_add(&window_fade_table, &wid, context);
        pthread_mutex_unlock(&window_fade_lock);
        pthread_create(&context->thread, NULL, &window_fade_thread_proc, context);
        pthread_detach(context->thread);
    }
}

static void do_window_layer(char *message)
{
    uint32_t wid;
    unpack(wid);
    if (!wid) return;

    int layer;
    unpack(layer);

    SLSSetWindowSubLevel(SLSMainConnectionID(), wid, CGWindowLevelForKey(layer));
}

static void do_window_sticky(char *message)
{
    uint32_t wid;
    unpack(wid);
    if (!wid) return;

    bool value;
    unpack(value);

    uint64_t tags = (1 << 11);
    if (value == 1) {
        SLSSetWindowTags(SLSMainConnectionID(), wid, &tags, 64);
    } else {
        SLSClearWindowTags(SLSMainConnectionID(), wid, &tags, 64);
    }
}

typedef void (*focus_window_call)(ProcessSerialNumber psn, uint32_t wid);
static void do_window_focus(char *message)
{
    if (set_front_window_fp == 0) return;

    int window_connection;
    ProcessSerialNumber window_psn;

    uint32_t wid;
    unpack(wid);

    SLSGetWindowOwner(SLSMainConnectionID(), wid, &window_connection);
    SLSGetConnectionPSN(SLSMainConnectionID(), &window_psn);

    ((focus_window_call) set_front_window_fp)(window_psn, wid);
}

static void do_window_shadow(char *message)
{
    uint32_t wid;
    unpack(wid);
    if (!wid) return;

    bool value;
    unpack(value);

    uint64_t tags = (1 << 3);
    if (value == 1) {
        SLSClearWindowTags(SLSMainConnectionID(), wid, &tags, 64);
    } else {
        SLSSetWindowTags(SLSMainConnectionID(), wid, &tags, 64);
    }
}

static void do_window_swap_proxy_in(char *message)
{
    int count = 0;
    unpack(count);
    if (!count) return;

    CFTypeRef transaction = SLSTransactionCreate(SLSMainConnectionID());
    for (int i = 0; i < count; ++i) {
        uint32_t wid;
        unpack(wid);
        if (!wid) continue;

        uint32_t proxy_wid;
        unpack(proxy_wid);

        SLSTransactionOrderWindowGroup(transaction, proxy_wid, 1, wid);
        SLSTransactionSetWindowSystemAlpha(transaction, wid, 0);
    }
    SLSTransactionCommit(transaction, 0);
    CFRelease(transaction);
}

static void do_window_swap_proxy_out(char *message)
{
    int count = 0;
    unpack(count);
    if (!count) return;

    CFTypeRef transaction = SLSTransactionCreate(SLSMainConnectionID());
    for (int i = 0; i < count; ++i) {
        uint32_t wid;
        unpack(wid);
        if (!wid) continue;

        uint32_t proxy_wid;
        unpack(proxy_wid);

        SLSTransactionSetWindowSystemAlpha(transaction, wid, 1.0f);
        SLSTransactionOrderWindowGroup(transaction, proxy_wid, 0, wid);
    }
    SLSTransactionCommit(transaction, 0);
    CFRelease(transaction);
}

static void do_window_order(char *message)
{
    uint32_t a_wid;
    unpack(a_wid);
    if (!a_wid) return;

    int order;
    unpack(order);

    uint32_t b_wid;
    unpack(b_wid);

    SLSOrderWindow(SLSMainConnectionID(), a_wid, order, b_wid);
}

static void do_window_order_in(char *message)
{
    int count = 0;
    unpack(count);
    if (!count) return;

    CFTypeRef transaction = SLSTransactionCreate(SLSMainConnectionID());
    for (int i = 0; i < count; ++i) {
        uint32_t wid;
        unpack(wid);
        if (!wid) continue;

        SLSTransactionOrderWindowGroup(transaction, wid, 1, 0);
    }
    SLSTransactionCommit(transaction, 0);
    CFRelease(transaction);
}

static inline CFArrayRef cfarray_of_cfnumbers(void *values, size_t size, int count, CFNumberType type)
{
    CFNumberRef temp[count];

    for (int i = 0; i < count; ++i) {
        temp[i] = CFNumberCreate(NULL, type, ((char *)values) + (size * i));
    }

    CFArrayRef result = CFArrayCreate(NULL, (const void **)temp, count, &kCFTypeArrayCallBacks);

    for (int i = 0; i < count; ++i) {
        CFRelease(temp[i]);
    }

    return result;
}

static void do_window_list_move_to_space(char *message)
{
    uint64_t sid;
    unpack(sid);

    int count = 0;
    unpack(count);

    CFArrayRef window_list_ref = cfarray_of_cfnumbers((uint32_t*)message, sizeof(uint32_t), count, kCFNumberSInt32Type);
    SLSMoveWindowsToManagedSpace(SLSMainConnectionID(), window_list_ref, sid);
    CFRelease(window_list_ref);
}

static void do_window_move_to_space(char *message)
{
    uint64_t sid;
    unpack(sid);

    uint32_t wid;
    unpack(wid);

    CFArrayRef window_list_ref = cfarray_of_cfnumbers(&wid, sizeof(uint32_t), 1, kCFNumberSInt32Type);
    SLSMoveWindowsToManagedSpace(SLSMainConnectionID(), window_list_ref, sid);
    CFRelease(window_list_ref);
}

static void do_handshake(int sockfd)
{
    uint32_t attrib = 0;

    if (dock_spaces != nil)                attrib |= OSAX_ATTRIB_DOCK_SPACES;
    if (dp_desktop_picture_manager != nil) attrib |= OSAX_ATTRIB_DPPM;
    if (add_space_fp)                      attrib |= OSAX_ATTRIB_ADD_SPACE;
    if (remove_space_fp)                   attrib |= OSAX_ATTRIB_REM_SPACE;
    if (move_space_fp)                     attrib |= OSAX_ATTRIB_MOV_SPACE;
    if (set_front_window_fp)               attrib |= OSAX_ATTRIB_SET_WINDOW;
    if (animation_time_addr)               attrib |= OSAX_ATTRIB_ANIM_TIME;

    char bytes[BUFSIZ] = {};
    int version_length = strlen(OSAX_VERSION);
    int attrib_length = sizeof(uint32_t);
    int bytes_length = version_length + 1 + attrib_length;

    memcpy(bytes, OSAX_VERSION, version_length);
    memcpy(bytes + version_length + 1, &attrib, attrib_length);
    bytes[version_length] = '\0';
    bytes[bytes_length] = '\n';

    send(sockfd, bytes, bytes_length+1, 0);
}

static void handle_message(int sockfd, char *message)
{
    enum sa_opcode op = *message++;
    switch (op) {
    case SA_OPCODE_HANDSHAKE: {
        do_handshake(sockfd);
    } break;
    case SA_OPCODE_SPACE_FOCUS: {
        do_space_focus(message);
    } break;
    case SA_OPCODE_SPACE_CREATE: {
        do_space_create(message);
    } break;
    case SA_OPCODE_SPACE_DESTROY: {
        do_space_destroy(message);
    } break;
    case SA_OPCODE_SPACE_MOVE: {
        do_space_move(message);
    } break;
    case SA_OPCODE_WINDOW_MOVE: {
        do_window_move(message);
    } break;
    case SA_OPCODE_WINDOW_OPACITY: {
        do_window_opacity(message);
    } break;
    case SA_OPCODE_WINDOW_OPACITY_FADE: {
        do_window_opacity_fade(message);
    } break;
    case SA_OPCODE_WINDOW_LAYER: {
        do_window_layer(message);
    } break;
    case SA_OPCODE_WINDOW_STICKY: {
        do_window_sticky(message);
    } break;
    case SA_OPCODE_WINDOW_SHADOW: {
        do_window_shadow(message);
    } break;
    case SA_OPCODE_WINDOW_FOCUS: {
        do_window_focus(message);
    } break;
    case SA_OPCODE_WINDOW_SCALE: {
        do_window_scale(message);
    } break;
    case SA_OPCODE_WINDOW_SWAP_PROXY_IN: {
        do_window_swap_proxy_in(message);
    } break;
    case SA_OPCODE_WINDOW_SWAP_PROXY_OUT: {
        do_window_swap_proxy_out(message);
    } break;
    case SA_OPCODE_WINDOW_ORDER: {
        do_window_order(message);
    } break;
    case SA_OPCODE_WINDOW_ORDER_IN: {
        do_window_order_in(message);
    } break;
    case SA_OPCODE_WINDOW_LIST_TO_SPACE: {
        do_window_list_move_to_space(message);
    } break;
    case SA_OPCODE_WINDOW_TO_SPACE: {
        do_window_move_to_space(message);
    } break;
    }
}

static inline bool read_message(int sockfd, char *message)
{
    int bytes_read    = 0;
    int bytes_to_read = 0;

    if (read(sockfd, &bytes_to_read, sizeof(int16_t)) == sizeof(int16_t)) {
        if (bytes_to_read >= SA_SOCKET_BUFF_LEN) return false;
        if (bytes_to_read <= 0)                  return false;

        do {
            int cur_read = read(sockfd, message+bytes_read, bytes_to_read-bytes_read);
            if (cur_read <= 0) break;

            bytes_read += cur_read;
        } while (bytes_read < bytes_to_read);

        return bytes_read == bytes_to_read;
    }

    return false;
}

static void *handle_connection(void *unused)
{
    for (;;) {
        int sockfd = accept(daemon_sockfd, NULL, 0);
        if (sockfd == -1) continue;

        char message[SA_SOCKET_BUFF_LEN];
        if (read_message(sockfd, message)) {
            handle_message(sockfd, message);
        }

        shutdown(sockfd, SHUT_RDWR);
        close(sockfd);
    }

    return NULL;
}

static TABLE_HASH_FUNC(hash_wid)
{
    return *(uint32_t *) key;
}

static TABLE_COMPARE_FUNC(compare_wid)
{
    return *(uint32_t *) key_a == *(uint32_t *) key_b;
}

static bool start_daemon(char *socket_path)
{
    struct sockaddr_un socket_address;
    socket_address.sun_family = AF_UNIX;
    snprintf(socket_address.sun_path, sizeof(socket_address.sun_path), "%s", socket_path);
    unlink(socket_path);

    if ((daemon_sockfd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
        return false;
    }

    if (bind(daemon_sockfd, (struct sockaddr *) &socket_address, sizeof(socket_address)) == -1) {
        return false;
    }

    if (chmod(socket_path, 0600) != 0) {
        return false;
    }

    if (listen(daemon_sockfd, SOMAXCONN) == -1) {
        return false;
    }

    init_instances();
    pthread_mutex_init(&window_fade_lock, NULL);
    table_init(&window_fade_table, 150, hash_wid, compare_wid);
    pthread_create(&daemon_thread, NULL, &handle_connection, NULL);

    return true;
}

__attribute__((constructor))
void load_payload(void)
{
    NSLog(@"[yabai-sa] loaded payload..");

    const char *user = getenv("USER");
    if (!user) {
        NSLog(@"[yabai-sa] could not get 'env USER'! abort..");
        return;
    }

    char socket_file[255];
    snprintf(socket_file, sizeof(socket_file), SA_SOCKET_PATH_FMT, user);

    if (start_daemon(socket_file)) {
        NSLog(@"[yabai-sa] now listening..");
    } else {
        NSLog(@"[yabai-sa] failed to spawn thread..");
    }
}
