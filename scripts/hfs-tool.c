/*
 * Small helper for scripts/package-dmg.py on Linux.
 *
 * Build against libdmg-hfsplus:
 *   cc -fno-strict-aliasing -I/path/to/libdmg-hfsplus/includes \
 *     -o hfs-tool scripts/hfs-tool.c \
 *     -L/path/to/build/hfs -L/path/to/build/common -lhfs -lcommon -lz
 *
 * Commands:
 *   hfs-tool rename <image> <volume-name>
 *   hfs-tool stat <image> <path>
 *   hfs-tool bless <image>
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <hfs/hfsplus.h>

char endianness;

static void set_endian(void) {
  short word = 0x0001;
  char *byte = (char *)&word;
  endianness = byte[0] ? IS_LITTLE_ENDIAN : IS_BIG_ENDIAN;
}

static Volume *open_image(const char *path, io_func **io_out) {
  io_func *io = openFlatFile(path);
  Volume *volume;
  if (io == NULL) {
    fprintf(stderr, "cannot open %s\n", path);
    exit(1);
  }
  volume = openVolume(io);
  if (volume == NULL) {
    fprintf(stderr, "cannot open HFS volume in %s\n", path);
    exit(1);
  }
  *io_out = io;
  return volume;
}

static void close_image(Volume *volume, io_func *io) {
  closeVolume(volume);
  CLOSE(io);
}

static int rename_volume(Volume *volume, const char *new_name) {
  HFSPlusCatalogKey thread_key;
  HFSPlusCatalogKey folder_key;
  HFSPlusCatalogThread *thread;
  HFSPlusCatalogFolder *folder_ptr;
  HFSPlusCatalogFolder folder;
  HFSPlusCatalogThread new_thread;
  int exact;
  int thread_length;

  memset(&thread_key, 0, sizeof(thread_key));
  thread_key.keyLength = sizeof(thread_key.parentID) + sizeof(thread_key.nodeName.length);
  thread_key.parentID = kHFSRootFolderID;
  thread_key.nodeName.length = 0;

  thread = (HFSPlusCatalogThread *)search(volume->catalogTree, (BTKey *)&thread_key, &exact, NULL, NULL);
  if (thread == NULL || thread->recordType != kHFSPlusFolderThreadRecord) {
    fprintf(stderr, "root thread not found\n");
    free(thread);
    return 1;
  }

  folder_key.parentID = thread->parentID;
  folder_key.nodeName = thread->nodeName;
  folder_key.keyLength = sizeof(folder_key.parentID) + STR_SIZE(folder_key.nodeName);

  folder_ptr = (HFSPlusCatalogFolder *)search(volume->catalogTree, (BTKey *)&folder_key, &exact, NULL, NULL);
  if (folder_ptr == NULL || folder_ptr->recordType != kHFSPlusFolderRecord) {
    fprintf(stderr, "root folder record not found\n");
    free(thread);
    free(folder_ptr);
    return 1;
  }
  folder = *folder_ptr;
  free(folder_ptr);

  if (!removeFromBTree(volume->catalogTree, (BTKey *)&folder_key)) {
    fprintf(stderr, "could not remove old volume name\n");
    free(thread);
    return 1;
  }
  if (!removeFromBTree(volume->catalogTree, (BTKey *)&thread_key)) {
    fprintf(stderr, "could not remove root thread\n");
    free(thread);
    return 1;
  }
  free(thread);

  ASCIIToUnicode(new_name, &folder_key.nodeName);
  folder_key.parentID = kHFSRootParentID;
  folder_key.keyLength = sizeof(folder_key.parentID) + STR_SIZE(folder_key.nodeName);

  memset(&new_thread, 0, sizeof(new_thread));
  new_thread.recordType = kHFSPlusFolderThreadRecord;
  new_thread.reserved = 0;
  new_thread.parentID = kHFSRootParentID;
  ASCIIToUnicode(new_name, &new_thread.nodeName);
  thread_length = sizeof(new_thread.recordType) + sizeof(new_thread.reserved) +
                  sizeof(new_thread.parentID) + STR_SIZE(new_thread.nodeName);

  flipCatalogFolder(&folder);
  flipCatalogThread(&new_thread, 1);

  if (!addToBTree(volume->catalogTree, (BTKey *)&folder_key, sizeof(folder), (unsigned char *)&folder)) {
    fprintf(stderr, "could not write new volume name\n");
    return 1;
  }

  memset(&thread_key, 0, sizeof(thread_key));
  thread_key.parentID = kHFSRootFolderID;
  thread_key.nodeName.length = 0;
  thread_key.keyLength = sizeof(thread_key.parentID) + sizeof(thread_key.nodeName.length);
  if (!addToBTree(volume->catalogTree, (BTKey *)&thread_key, thread_length, (unsigned char *)&new_thread)) {
    fprintf(stderr, "could not write root thread\n");
    return 1;
  }

  updateVolume(volume);
  return 0;
}

static void print_name(const HFSUniStr255 *name) {
  uint16_t i;
  for (i = 0; i < name->length; i++) {
    uint16_t ch = name->unicode[i];
    if (ch >= 32 && ch < 127) {
      fputc((int)ch, stdout);
    }
  }
}

static int stat_path(Volume *volume, const char *path) {
  HFSPlusCatalogKey key;
  HFSPlusCatalogRecord *record;
  HFSPlusCatalogKey thread_key;
  HFSPlusCatalogThread *thread;
  int exact;

  memset(&thread_key, 0, sizeof(thread_key));
  thread_key.keyLength = sizeof(thread_key.parentID) + sizeof(thread_key.nodeName.length);
  thread_key.parentID = kHFSRootFolderID;
  thread = (HFSPlusCatalogThread *)search(volume->catalogTree, (BTKey *)&thread_key, &exact, NULL, NULL);
  if (thread == NULL) {
    fprintf(stderr, "root thread not found\n");
    return 1;
  }

  printf("volume_name=");
  print_name(&thread->nodeName);
  printf("\n");
  printf("volume_create=%u\n", volume->volumeHeader->createDate);
  printf("signature=%c%c\n",
         (char)((volume->volumeHeader->signature >> 8) & 0xff),
         (char)(volume->volumeHeader->signature & 0xff));
  free(thread);

  memset(&key, 0, sizeof(key));
  record = getRecordFromPath3(path, volume, NULL, &key, 1, 1, kHFSRootFolderID);
  if (record == NULL) {
    fprintf(stderr, "no such path: %s\n", path);
    return 1;
  }
  if (record->recordType == kHFSPlusFolderRecord) {
    HFSPlusCatalogFolder *folder = (HFSPlusCatalogFolder *)record;
    printf("kind=folder\n");
    printf("cnid=%u\n", folder->folderID);
    printf("parent=%u\n", key.parentID);
    printf("create=%u\n", folder->createDate);
  } else if (record->recordType == kHFSPlusFileRecord) {
    HFSPlusCatalogFile *file = (HFSPlusCatalogFile *)record;
    printf("kind=file\n");
    printf("cnid=%u\n", file->fileID);
    printf("parent=%u\n", key.parentID);
    printf("create=%u\n", file->createDate);
  } else {
    fprintf(stderr, "unexpected record type\n");
    free(record);
    return 1;
  }
  free(record);
  return 0;
}

static int bless_root(Volume *volume) {
  uint32_t root_id = kHFSRootFolderID;
  short word = 0x0001;
  if (*((char *)&word)) {
    root_id = __builtin_bswap32(root_id);
  }
  /* finderInfo is stored big-endian and the library does not swap it. */
  volume->volumeHeader->finderInfo[0] = root_id;
  updateVolume(volume);
  return 0;
}

int main(int argc, char **argv) {
  io_func *io = NULL;
  Volume *volume;
  int status;

  set_endian();
  if (argc < 3) {
    fprintf(stderr, "usage: %s rename|stat|bless <image> [arg]\n", argv[0]);
    return 2;
  }

  volume = open_image(argv[2], &io);
  if (strcmp(argv[1], "rename") == 0) {
    if (argc < 4) {
      fprintf(stderr, "usage: %s rename <image> <name>\n", argv[0]);
      status = 2;
    } else {
      status = rename_volume(volume, argv[3]);
    }
  } else if (strcmp(argv[1], "stat") == 0) {
    if (argc < 4) {
      fprintf(stderr, "usage: %s stat <image> <path>\n", argv[0]);
      status = 2;
    } else {
      status = stat_path(volume, argv[3]);
    }
  } else if (strcmp(argv[1], "bless") == 0) {
    status = bless_root(volume);
  } else {
    fprintf(stderr, "unknown command %s\n", argv[1]);
    status = 2;
  }
  close_image(volume, io);
  return status;
}
