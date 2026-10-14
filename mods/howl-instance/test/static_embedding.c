/* The exact foreign lifecycle proof lives in a host-owned shared object. */
extern int howl_instance_static_shared(void);
int main(void) {
    return howl_instance_static_shared();
}
