// Sized and aligned operator new/delete: libc++abi exports these only from
// iOS 11. Linked into each WebPorn image with ld64 -hidden-lwpcxxcompat.

#include <cstddef>
#include <cstdlib>
#include <new>

void operator delete(void* p, std::size_t) noexcept { std::free(p); }
void operator delete[](void* p, std::size_t) noexcept { std::free(p); }

static void* alignedAlloc(std::size_t size, std::align_val_t alignment) noexcept
{
    std::size_t a = static_cast<std::size_t>(alignment);
    if (a < sizeof(void*))
        a = sizeof(void*);
    void* p = nullptr;
    if (posix_memalign(&p, a, size ? size : 1))
        return nullptr;
    return p;
}

void* operator new(std::size_t size, std::align_val_t a)
{
    if (void* p = alignedAlloc(size, a))
        return p;
    std::abort(); // WebKit builds with -fno-exceptions.
}
void* operator new[](std::size_t size, std::align_val_t a) { return operator new(size, a); }
void* operator new(std::size_t size, std::align_val_t a, const std::nothrow_t&) noexcept { return alignedAlloc(size, a); }
void* operator new[](std::size_t size, std::align_val_t a, const std::nothrow_t&) noexcept { return alignedAlloc(size, a); }

void operator delete(void* p, std::align_val_t) noexcept { std::free(p); }
void operator delete[](void* p, std::align_val_t) noexcept { std::free(p); }
void operator delete(void* p, std::size_t, std::align_val_t) noexcept { std::free(p); }
void operator delete[](void* p, std::size_t, std::align_val_t) noexcept { std::free(p); }
void operator delete(void* p, std::align_val_t, const std::nothrow_t&) noexcept { std::free(p); }
void operator delete[](void* p, std::align_val_t, const std::nothrow_t&) noexcept { std::free(p); }
