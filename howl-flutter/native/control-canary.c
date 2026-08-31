#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef void *(*create_fn)(const uint8_t *, size_t);
typedef void (*destroy_fn)(void *);
typedef int32_t (*bytes_fn)(void *, const uint8_t *, size_t);
typedef int32_t (*named_fn)(void *, uint8_t, uint8_t, uint8_t);
typedef int32_t (*unicode_fn)(void *, uint32_t, uint8_t, uint8_t);
typedef int32_t (*focus_fn)(void *, uint8_t);
typedef int32_t (*resize_fn)(void *, uint16_t, uint16_t);
typedef int32_t (*mouse_fn)(void *, uint8_t, uint8_t, uint8_t, uint8_t, int32_t, uint16_t, uint8_t, uint32_t, uint32_t);

static void *symbol(void *lib, const char *name) {
    void *value = dlsym(lib, name);
    if (!value) {
        fprintf(stderr, "missing symbol %s: %s\n", name, dlerror());
        exit(2);
    }
    return value;
}

static void require_ok(const char *name, int32_t rc) {
    printf("%s=%d\n", name, rc);
    if (rc != 0) exit(3);
}

static void send_ascii(bytes_fn committed, void *control, const char *name, const char *value) {
    require_ok(name, committed(control, (const uint8_t *)value, strlen(value)));
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s LIB ENDPOINT\n", argv[0]);
        return 64;
    }

    void *lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!lib) {
        fprintf(stderr, "dlopen: %s\n", dlerror());
        return 2;
    }

    create_fn create = (create_fn)symbol(lib, "howl_native_control_create");
    destroy_fn destroy = (destroy_fn)symbol(lib, "howl_native_control_destroy");
    bytes_fn committed = (bytes_fn)symbol(lib, "howl_native_control_committed_text");
    bytes_fn paste = (bytes_fn)symbol(lib, "howl_native_control_paste");
    named_fn named = (named_fn)symbol(lib, "howl_native_control_named_key");
    unicode_fn unicode_key = (unicode_fn)symbol(lib, "howl_native_control_unicode_key");
    focus_fn focus = (focus_fn)symbol(lib, "howl_native_control_focus");
    resize_fn resize = (resize_fn)symbol(lib, "howl_native_control_resize");
    mouse_fn mouse = (mouse_fn)symbol(lib, "howl_native_control_mouse");

    const uint8_t *endpoint = (const uint8_t *)argv[2];
    void *control = create(endpoint, strlen(argv[2]));
    if (!control) {
        fprintf(stderr, "control create failed\n");
        return 4;
    }

    require_ok("focus_in", focus(control, 1));
    require_ok("focus_out", focus(control, 2));

    send_ascii(committed, control, "text", "echo HOWL_CANARY_TEXT_λ");
    require_ok("enter_text", named(control, 1, 1, 0));

    send_ascii(committed, control, "backspace_text", "echo HOWL_CANARY_BACKX");
    require_ok("backspace", named(control, 3, 1, 0));
    send_ascii(committed, control, "backspace_suffix", "OK");
    require_ok("enter_backspace", named(control, 1, 1, 0));

    send_ascii(committed, control, "delete_text", "echo HOWL_CANARY_DEL_XYZ");
    require_ok("left_1", named(control, 7, 1, 0));
    require_ok("left_2", named(control, 7, 1, 0));
    require_ok("delete", named(control, 10, 1, 0));
    require_ok("enter_delete", named(control, 1, 1, 0));

    send_ascii(committed, control, "unicode_prefix", "echo HOWL_CANARY_UNICODE_");
    require_ok("unicode_Z", unicode_key(control, 'Z', 1, 0));
    require_ok("enter_unicode", named(control, 1, 1, 0));

    send_ascii(paste, control, "paste", "echo HOWL_CANARY_PASTE");
    require_ok("enter_paste", named(control, 1, 1, 0));

    // Mouse tracking is deliberately off in the shell fixture. Canonical VT must
    // suppress this semantic move rather than the host inventing escape bytes.
    require_ok("mouse_tracking_off", mouse(control, 3, 0, 0, 0, 2, 3, 1, 30, 40));
    send_ascii(committed, control, "mouse_guard", "echo HOWL_CANARY_MOUSE_OK");
    require_ok("enter_mouse_guard", named(control, 1, 1, 0));

    require_ok("resize_41x53", resize(control, 41, 53));
    destroy(control);
    dlclose(lib);
    return 0;
}
