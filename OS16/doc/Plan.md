# Issues
Module globals are accessed through SB which is a word, extend this to long so we can escape bank 0.
Make the stack bigger.
Volume Naming
Data needs to be in any bank
Could process full video bytes at once when 4 consecutive glyph pixels align

# Operating System
Module loader from disk
HeapManager

# UI
## Images
Like font data, byte array in module.
## Postscript Interface
Possibly add a graphics context like interface.
## UIKit
Full UI controls
## Change to 640x400x16

# Device
Module that defines the device. Sets up drivers.

# ROM

## ROMTool

# Applications

## Editor

## as

## oc

## Files

## DiskTool

## Terminal

## Business Basic

# Networking

## telnet

## wget

## NFS

## git?

# Modules

## Volumes

TYPE

  volume = RECORD
    name  
// Browse and list volumes


# Filesystem layout

/Library
  /Module
  /Font
