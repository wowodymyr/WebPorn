/* WebPorn overlay: iOS ships libedit but no readline headers; just what jsc.cpp uses. */
#pragma once
#ifdef __cplusplus
extern "C" {
#endif
char *readline(const char *);
#ifdef __cplusplus
}
#endif
