/* Invoke the same copied-font/frame proof through the embedder's shared object. */
extern int howl_render_static_shared(int, char **);
int main(int argc, char **argv) {
    return howl_render_static_shared(argc, argv);
}
