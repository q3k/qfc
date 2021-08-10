// Set up 'bsc' for execution by giving it a PATH containing a symlink forest
// of executables it wants to shell out to.

#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <iostream>
#include <filesystem>
#include <map>
#include <string>

int main(int argc, char **argv) {
    auto bsc = std::getenv("BSC");
    if (bsc == nullptr) {
        std::cerr << "BSC must be set\n";
        return 1;
    }
    
    auto tmp = std::getenv("TMPDIR");
    if (tmp == nullptr) {
        std::cerr << "TMPDIR must be set\n";
        return 1;
    }

    auto forest = std::string(tmp) + "/bscwrap";

    std::filesystem::remove_all(forest);
    std::filesystem::create_directory(forest);

    std::map<std::string, std::string> links = {
        {"c++", "CXX"},
        {"strip", "STRIP"},
    };
    for (auto const& [k, v] : links) {
        auto target = std::getenv(v.c_str());
        if (target == nullptr) {
            std::cerr << v << " must be set\n";
            return 1;
        }
        std::filesystem::create_symlink(target, forest + "/" + k);
    }

    auto path = forest + ":" + (std::getenv("PATH") ? std::getenv("PATH") : "");

    char *const envp[] = {
        strdup((std::string("PATH=") + path).c_str()),
        nullptr,
    };

    if (execvpe(bsc, argv, envp) == -1) {
        std::cerr << "execvpe failed\n";
        return 1;
    }
    // Unreachable.
    return 0;
}
