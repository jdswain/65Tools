In Oberon there is an ADBManager.Mod

MODULE ADBManager
VAR
  KeyboardDeviceId, MouseDeviceId: INTEGER;
  
PROCEDURE Init()
  Send TALK Register 3 to 02 and 03 to see if the device is present and get it's device id.
END;

PROCEDURE Poll() (* ISR *)
  Send TALK Register 0 to all active devices.
  
END

END ADBManager.

MODULE EventQueue

PROCEDURE PostEvent()
END

PROCEDURE ReadEvent()
END

END EventQueue.

ADB Commands

Talk - Request a register from a device.
Listen - Send data to a register.
Flush - Flush a register.
SendReset - Actually a 3ms pulse on the bus, but the microcontroller does this.

Command Format:

Bits
7-4  Device Address
3-2  00-Flush, 10-Listen, 11-Talk
1-0  Device register or 01 for Flush

SendReset command is bits 3-0 0000.

# ADB Registers

Register 0 - Keyboard
15   Key status for first key; 0 = down
14-8 Key transition code for first key; a 7-bit ASCII value
7    Key status for second key; 0 = down
6-0  Key transition code for second key; a 7-bit ASCII value

Register 0 - Mouse
Bit	Description
15	 Button status: 1 if released
14–8 Y axis moves (2’s complement, negative up)
7	 Reserved
6–0	 X axis offset (2’s complement, negative left)

Register 2 - Keyboard
Bit	Description (Standard)	Description (Extended)
15	Reserved	Reserved
14	Delete (Backspace)	Delete (Backspace)
13	Caps Lock	Caps Lock
12	Reset	    Reset
11	Control	    Control
10	Shift	    Shift
9	Option (Alt)Option (Alt)
8	Command	    Command
7	Reserved	Num Lock/Clear
6	Reserved	Scroll Lock
5–3	Reserved	Reserved
2	Reserved	Scroll Lock LED
1	Reserved	Caps Lock LED
0	Reserved	Num Lock LED

Register 3 - All Devices
15   0
14   Exceptional Event
13   Service Request
12   0
11-8 Device Address
7-0  Device Handler ID

# Default Addresses
0 - Computer
2 - Keyboard
3 - Mouse
8-E - Used for dynamic reallocation when there is a conflict
