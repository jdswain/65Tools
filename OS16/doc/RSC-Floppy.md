# Rockwell Floppy Interface

wd1773 at base.

00 Status/Cmd
01 Track
02 Sector
03 Data
04 Not used
05 Not used
06 Drive Stat/Ctl

Bit  Stat (Read)
7    /INTRQ from 1793
6    /(INTRQ+DRQ) from 1793
5    Motor on = 1, off = 1
4    Not used
3    Not used
2    Not used
1    Not used
0    Not used

Bit  Ctl (Write)
7    Density 0 = Double, 1 = Single
6    Not used
5    Motor control 0 = off, 1 = on
4    Drive Select 3
3    Drive Select 2
2    Drive Select 1
1    Drive Select 0
0    Side Select 0 = side 0, 1 = side 1
