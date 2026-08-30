#include <gtk/gtk.h>
#include <cairo.h>
#include <stdlib.h>
#include <string.h>

typedef void (*HowlActivateFn)(void *application, void *data);
typedef void (*HowlDrawFn)(void *area, void *cairo, int width, int height, void *data);
typedef int (*HowlKeyFn)(void *controller, unsigned int keyval, unsigned int keycode, unsigned int state, void *data);

void *howl_gtk_application_new(void) {
    return gtk_application_new("uk.laurencegouws.HowlGtk", G_APPLICATION_DEFAULT_FLAGS);
}

void howl_gtk_connect_activate(void *application, HowlActivateFn callback, void *data) {
    g_signal_connect(application, "activate", G_CALLBACK(callback), data);
}

int howl_gtk_application_run(void *application) {
    return g_application_run(G_APPLICATION(application), 0, NULL);
}

void howl_gtk_application_unref(void *application) {
    g_object_unref(application);
}

void *howl_gtk_window_new(void *application) {
    return gtk_application_window_new(GTK_APPLICATION(application));
}

void howl_gtk_window_set_title(void *window, const char *title) {
    gtk_window_set_title(GTK_WINDOW(window), title);
}

void howl_gtk_window_set_default_size(void *window, int width, int height) {
    gtk_window_set_default_size(GTK_WINDOW(window), width, height);
}

void *howl_gtk_drawing_area_new(void) {
    return gtk_drawing_area_new();
}

void howl_gtk_drawing_area_set_draw_func(void *area, HowlDrawFn callback, void *data) {
    gtk_drawing_area_set_draw_func(
        GTK_DRAWING_AREA(area),
        (GtkDrawingAreaDrawFunc)callback,
        data,
        NULL
    );
}

void howl_gtk_window_set_child(void *window, void *child) {
    gtk_window_set_child(GTK_WINDOW(window), GTK_WIDGET(child));
}

void howl_gtk_window_present(void *window) {
    gtk_window_present(GTK_WINDOW(window));
}

void howl_gtk_window_add_key_controller(void *window, HowlKeyFn callback, void *data) {
    GtkEventController *controller = gtk_event_controller_key_new();
    g_signal_connect(controller, "key-pressed", G_CALLBACK(callback), data);
    gtk_widget_add_controller(GTK_WIDGET(window), controller);
}

void howl_gtk_drawing_area_ref(void *area) {
    g_object_ref(area);
}

void howl_gtk_drawing_area_unref(void *area) {
    g_object_unref(area);
}

static gboolean howl_queue_draw_once(gpointer data) {
    gtk_widget_queue_draw(GTK_WIDGET(data));
    g_object_unref(data);
    return G_SOURCE_REMOVE;
}

void howl_gtk_queue_draw_async(void *widget) {
    g_main_context_invoke(NULL, howl_queue_draw_once, g_object_ref(widget));
}

int howl_gtk_keyval_bytes(unsigned int keyval, unsigned char output[4]) {
    if (keyval == GDK_KEY_Return || keyval == GDK_KEY_KP_Enter) {
        output[0] = '\r';
        return 1;
    }
    if (keyval == GDK_KEY_BackSpace) {
        output[0] = 0x7f;
        return 1;
    }
    if (keyval == GDK_KEY_Tab) {
        output[0] = '\t';
        return 1;
    }
    if (keyval == GDK_KEY_Escape) {
        output[0] = 0x1b;
        return 1;
    }
    gunichar value = gdk_keyval_to_unicode(keyval);
    if (value == 0) return 0;
    char encoded[7] = {0};
    int count = g_unichar_to_utf8(value, encoded);
    if (count <= 0 || count > 4) return 0;
    memcpy(output, encoded, (size_t)count);
    return count;
}

void howl_cairo_clear(void *cairo, double red, double green, double blue) {
    cairo_t *cr = cairo;
    cairo_set_source_rgb(cr, red, green, blue);
    cairo_paint(cr);
}

void howl_cairo_set_rgb(void *cairo, double red, double green, double blue) {
    cairo_set_source_rgb((cairo_t *)cairo, red, green, blue);
}

void howl_cairo_mask_a8(
    void *cairo,
    const unsigned char *tight_pixels,
    int width,
    int height,
    int x,
    int y
) {
    if (width <= 0 || height <= 0) return;
    int stride = cairo_format_stride_for_width(CAIRO_FORMAT_A8, width);
    if (stride <= 0) return;
    size_t bytes = (size_t)stride * (size_t)height;
    unsigned char *padded = calloc(1, bytes);
    if (!padded) return;
    for (int row = 0; row < height; row++) {
        memcpy(padded + (size_t)row * (size_t)stride,
               tight_pixels + (size_t)row * (size_t)width,
               (size_t)width);
    }
    cairo_surface_t *surface = cairo_image_surface_create_for_data(
        padded, CAIRO_FORMAT_A8, width, height, stride
    );
    if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
        cairo_surface_destroy(surface);
        free(padded);
        return;
    }
    cairo_mask_surface((cairo_t *)cairo, surface, x, y);
    cairo_surface_destroy(surface);
    free(padded);
}
