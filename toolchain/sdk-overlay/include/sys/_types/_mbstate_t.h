/* WebPorn SDK overlay: pre-iOS 11 SDKs expect <sys/_types.h> to be included
   before this header; libc++ 21 includes it directly. */
#include <sys/_types.h>
#include_next <sys/_types/_mbstate_t.h>
