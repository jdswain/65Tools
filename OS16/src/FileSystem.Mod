MODULE FileSystem; (* A file system on a block device (model:
   FileSystem). FatFS extends it. *)

  IMPORT BlockDriver;

  TYPE
    FileSystem* = POINTER TO FileSystemDesc;
    FileSystemDesc* = RECORD
      dev*: BlockDriver.BlockDriver   (* the device it lives on *)
    END;

  (* Write an empty file system to the device. *)
  PROCEDURE (fs: FileSystem) Format*(): BOOLEAN;
  BEGIN RETURN FALSE
  END Format;

  (* Read the device's file system and make it the one in use. *)
  PROCEDURE (fs: FileSystem) Mount*(): BOOLEAN;
  BEGIN RETURN FALSE
  END Mount;

  (* Write back what is held in memory. *)
  PROCEDURE (fs: FileSystem) Sync*(): BOOLEAN;
  BEGIN RETURN TRUE
  END Sync;

END FileSystem.
