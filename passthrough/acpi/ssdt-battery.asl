/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20250807 (64-bit version)
 * Copyright (c) 2000 - 2025 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of ssdt-battery.aml
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x0000008B (139)
 *     Revision         0x01
 *     Checksum         0xDA
 *     OEM ID           "CORP"
 *     OEM Table ID     "BATT"
 *     OEM Revision     0x00000001 (1)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20250807 (539297799)
 */
DefinitionBlock ("", "SSDT", 1, "CORP", "BATT", 0x00000001)
{
    Scope (\_SB)
    {
        Device (BATT)
        {
            Name (_HID, EisaId ("PNP0C0A") /* Control Method Battery */)  // _HID: Hardware ID
            Name (_UID, One)  // _UID: Unique ID
            Name (_STA, 0x1F)  // _STA: Status
            Method (_BIF, 0, NotSerialized)  // _BIF: Battery Information
            {
                Return (Package (0x0D)
                {
                    One, 
                    Ones, 
                    Ones, 
                    One, 
                    0x2A30, 
                    Zero, 
                    Zero, 
                    One, 
                    One, 
                    "CRB Battery 0", 
                    "", 
                    "LION", 
                    ""
                })
            }

            Method (_BST, 0, NotSerialized)  // _BST: Battery Status
            {
                Return (Package (0x04)
                {
                    Zero, 
                    Ones, 
                    Ones, 
                    0x2A30
                })
            }
        }
    }
}

