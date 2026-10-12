#ifndef HOWL_RENDER_NATIVE_H
#define HOWL_RENDER_NATIVE_H
#include <stdint.h>
#include <stddef.h>
/* Render-owned version-1 payload definitions. No Instance, transport, window or scheduler.
 * RGBA integer low-to-high bytes are R,G,B,A. Rectangles use signed pixel origins.
 * Resource identities/generations are exact opaque numbers, not texture handles. */
#define HRC_NATIVE_VERSION 1u
enum hrc_command_kind { HRC_SOLID=0, HRC_ALPHA_MASK=1, HRC_RGBA=2 };
enum hrc_pixel_format { HRC_ALPHA8=0, HRC_RGBA8=1 };
typedef struct hrc_resource {
    uint64_t resource;
    uint64_t generation;
    uint64_t pixel_count;
    uint64_t stride;
    uint16_t width;
    uint16_t height;
    uint8_t format;
    uint8_t _reserved[3];
} hrc_resource;
typedef struct hrc_removal {
    uint64_t resource;
    uint64_t generation;
} hrc_removal;
typedef struct hrc_command {
    uint64_t resource;
    uint64_t generation;
    uint32_t color_rgba;
    int32_t destination_x;
    int32_t destination_y;
    int32_t clip_x;
    int32_t clip_y;
    uint16_t destination_width;
    uint16_t destination_height;
    uint16_t clip_width;
    uint16_t clip_height;
    uint16_t source_x;
    uint16_t source_y;
    uint16_t source_width;
    uint16_t source_height;
    uint16_t resource_width;
    uint16_t resource_height;
    uint8_t tag;
    uint8_t format;
    uint8_t cursor_component;
    uint8_t _reserved;
} hrc_command;
/* One upload borrows exact immutable pixels from its owning frame lease.
 * The pointer is invalid after lease release; no copying is required for synchronous upload. */
typedef struct hrc_upload {
    hrc_resource info;
    const uint8_t *pixels;
    size_t pixel_len;
} hrc_upload;
typedef struct hrc_residency {
    uint64_t resource, generation;
    uint16_t width, height;
    uint8_t format;
    uint8_t _reserved[3];
} hrc_residency;
#endif
