/*
 * SPDX-License-Identifier: MIT
 *
 * The LINK65 factory bootloader only starts an application when its initial
 * MSP passes this check:
 *
 *   (initial_msp & 0x2fffb000) == 0x20000000
 *
 * Zephyr normally places z_main_stack late in .noinit, which puts the first
 * vector above the range accepted by that check.  kernel/init.c declares the
 * main, idle, and interrupt stacks in unique .noinit sections.  Collect those
 * sections before normal RAM data so that the main stack remains a real,
 * reserved Zephyr stack while its top is in the bootloader-compatible range.
 */

SECTION_DATA_PROLOGUE(link65_boot_stacks, (NOLOAD), SUBALIGN(8))
{
	__link65_boot_stacks_start = .;
	/* __in_section_unique() quotes __FILE__ inside the ELF section name. */
	KEEP(*(.noinit.*kernel/init.c*))
	__link65_boot_stacks_end = .;
} GROUP_NOLOAD_LINK_IN(RAMABLE_REGION, ROMABLE_REGION)

ASSERT(__link65_boot_stacks_end <= 0x20001000,
       "LINK65 early stacks exceed the factory bootloader-compatible SRAM window")
ASSERT(((z_main_stack + CONFIG_MAIN_STACK_SIZE) & 0x2fffb000) == 0x20000000,
       "LINK65 initial MSP is rejected by the factory bootloader")
