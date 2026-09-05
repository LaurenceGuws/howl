/* Exact tag declaration from wasi-libc 06513b9ae0c1b14ca3010924939c007ed27628a1.
 * The pinned Zig libc already contains the real jump runtime but lacks this
 * LLVM-22 tag definition. No jump implementation is replaced or stubbed. */
// The `__builtin_wasm_throw` invocation above will reference this symbol which
// refers to a WebAssembly tag. The tag can't be defined in C but we can define
// it with inline assembly, so do so here.
//
// Note that the means of defining this symbol changed historically, so this
// is only done on LLVM 22+ where it's required.
#if __clang_major__ >= 22
__asm__(".globl __c_longjmp\n"
#if defined(__wasm32__)
        ".tagtype __c_longjmp i32\n"
#elif defined(__wasm64__)
        ".tagtype __c_longjmp i64\n"
#else
#error "Unsupported Wasm architecture"
#endif
        "__c_longjmp:\n");
#endif
