// jscrun: run a list of JSC tests on a device that has no timeout(1).
//   jscrun <jsc> <list> <timeout-sec> [extra jsc args...]
// <list>: one test per line, "file<TAB>opt<TAB>opt...". Runs each in the list's
// directory, prints "PASS|FAIL|TIME|SIG<n> <ms> <file>" per test, and appends the
// output of failing tests to <list>.fail.log.

#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>

static double now(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}

int main(int argc, char** argv)
{
    if (argc < 4) {
        fprintf(stderr, "usage: %s <jsc> <list> <timeout-sec> [jsc args...]\n", argv[0]);
        return 2;
    }
    const char* jsc = argv[1];
    int timeout = atoi(argv[3]);
    FILE* list = fopen(argv[2], "r");
    if (!list) {
        perror(argv[2]);
        return 2;
    }
    char failLogPath[1024], outPath[1024], listDir[1024];
    snprintf(failLogPath, sizeof(failLogPath), "%s.fail.log", argv[2]);
    snprintf(outPath, sizeof(outPath), "%s.out", argv[2]);
    snprintf(listDir, sizeof(listDir), "%s", argv[2]);
    if (chdir(dirname(listDir))) {
        perror("chdir");
        return 2;
    }
    FILE* failLog = fopen(failLogPath, "a");

    char line[8192];
    int counts[4] = { 0 };
    while (fgets(line, sizeof(line), list)) {
        line[strcspn(line, "\n")] = 0;
        if (!*line)
            continue;
        char* args[256];
        int n = 0;
        args[n++] = (char*)jsc;
        for (int i = 4; i < argc && n < 200; ++i)
            args[n++] = argv[i];
        char* file = strtok(line, "\t");
        for (char* o = strtok(NULL, "\t"); o && n < 250; o = strtok(NULL, "\t"))
            args[n++] = o;
        args[n++] = file;
        args[n] = NULL;

        double start = now();
        pid_t pid = fork();
        if (!pid) {
            int fd = open(outPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            dup2(fd, 1);
            dup2(fd, 2);
            alarm(timeout);
            setenv("TZ", "America/Los_Angeles", 1); // as run-jsc-stress-tests does
            execv(jsc, args);
            _exit(127);
        }
        int status = 0;
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) { }
        double ms = now() - start;

        char verdict[16];
        int bucket;
        if (WIFEXITED(status) && !WEXITSTATUS(status)) {
            strcpy(verdict, "PASS");
            bucket = 0;
        } else if (WIFEXITED(status)) {
            snprintf(verdict, sizeof(verdict), "FAIL%d", WEXITSTATUS(status));
            bucket = 1;
        } else if (WTERMSIG(status) == SIGALRM) {
            strcpy(verdict, "TIME");
            bucket = 2;
        } else {
            snprintf(verdict, sizeof(verdict), "SIG%d", WTERMSIG(status));
            bucket = 3;
        }
        counts[bucket]++;
        printf("%s %.0f %s\n", verdict, ms, file);
        fflush(stdout);
        if (bucket && failLog) {
            fprintf(failLog, "===== %s %s\n", verdict, file);
            FILE* out = fopen(outPath, "r");
            if (out) {
                char buf[4096];
                size_t total = 0, got;
                while ((got = fread(buf, 1, sizeof(buf), out)) && total < 16384) {
                    fwrite(buf, 1, got, failLog);
                    total += got;
                }
                fclose(out);
            }
            fflush(failLog);
        }
    }
    printf("# pass %d fail %d timeout %d crash %d\n", counts[0], counts[1], counts[2], counts[3]);
    return 0;
}
