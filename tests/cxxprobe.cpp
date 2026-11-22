// Runs on the device to check that the hermetic libc++ and libwpcxxcompat work
// against the target OS's libSystem/libc++abi.

#include <chrono>
#include <cstdio>
#include <filesystem>
#include <format>
#include <memory>
#include <optional>
#include <string>
#include <thread>
#include <vector>

struct alignas(64) Aligned {
    char bytes[64];
};

int main()
{
    std::optional<int> answer = 42;
    auto path = std::filesystem::path("/var/wkd/WebCore.framework/WebCore");
    std::string line = std::format("optional={} filename={} parent={}", *answer, path.filename().string(), path.parent_path().string());
    std::puts(line.c_str());

    auto t0 = std::chrono::steady_clock::now();
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
    auto now = std::chrono::system_clock::now().time_since_epoch();
    std::puts(std::format("steady sleep ~{}ms, system epoch {}s", ms, std::chrono::duration_cast<std::chrono::seconds>(now).count()).c_str());

    auto aligned = std::make_unique<Aligned[]>(4);
    std::puts(std::format("aligned new: {}", reinterpret_cast<uintptr_t>(aligned.get()) % 64 == 0 ? "ok" : "MISALIGNED").c_str());

    std::vector<std::string> v;
    for (int i = 0; i < 1000; ++i)
        v.push_back(std::to_string(i));
    v.shrink_to_fit();
    std::puts(std::format("vector: {} items, last={}", v.size(), v.back()).c_str());

    std::error_code ec;
    bool exists = std::filesystem::exists("/System/Library/Frameworks/UIKit.framework", ec);
    std::puts(std::format("filesystem exists(UIKit)={} ec={}", exists, ec.value()).c_str());
    return 0;
}
