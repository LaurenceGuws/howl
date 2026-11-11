/* The exact foreign lifecycle proof lives in a host-owned shared object. */
extern int howl_instance_static_shared(int argc, char **argv);
int main(int argc, char **argv) {
    return howl_instance_static_shared(argc, argv);
}
