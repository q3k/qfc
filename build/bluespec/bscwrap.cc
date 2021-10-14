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
    char **new_argv = new char*[argc];
    int new_argv_ix = 0;

    char *bsc = nullptr;
    char *cxx = nullptr;
    char *strip = nullptr;

    for (int i = 1; i < argc; i++) {
        if (new_argv_ix > 0) {
            new_argv[new_argv_ix++] = argv[i];
        } else {
            if (std::string(argv[i]) == "--") {
                new_argv_ix = 1;
            } else {
                switch (i) {
                    case 1:
                        bsc = argv[1];
                        break;
                    case 2:
                        cxx = argv[i];
                        break;
                    case 3:
                        strip = argv[i];
                        break;
                }
            }
        }
    }
    if (bsc == nullptr || cxx == nullptr || strip == nullptr) {
        std::cerr << "Usage: " << argv[0] << " bsc cxx strip -- bsc args\n";
        return 1;
    }
    new_argv[0] = bsc;
    new_argv[new_argv_ix] = nullptr;
    
    auto tmp = std::getenv("TMPDIR");
    if (tmp == nullptr) {
        std::cerr << "TMPDIR must be set\n";
        return 1;
    }

    auto forest = std::string(tmp) + "/bscwrap";

    std::filesystem::remove_all(forest);
    std::filesystem::create_directory(forest);

    std::filesystem::create_symlink(cxx, forest + "/c++");
    std::filesystem::create_symlink(strip, forest + "/strip");

    auto path = forest + ":" + (std::getenv("PATH") ? std::getenv("PATH") : "");

    char *const envp[] = {
        strdup((std::string("PATH=") + path).c_str()),
        nullptr,
    };

    if (execvpe(bsc, new_argv, envp) == -1) {
        std::cerr << "execvpe failed\n";
        return 1;
    }
    // Unreachable.
    return 0;
}
