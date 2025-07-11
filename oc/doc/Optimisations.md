*Identify and remove redundant loads and stores.*

*Recode the register file to size based on the type being stored.*
Since this is a stack this should be possible.

*Modules*
Exported procedures should be called with JSL and RTL. Non-exported can be JSR and RTS.
Runtime linking can fix inter-module addresses.
