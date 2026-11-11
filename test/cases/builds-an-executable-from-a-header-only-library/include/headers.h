#ifndef HEADERS_H
#define HEADERS_H

int fixed(void);

static inline int headers_value(void) { return HEADERS_BASE + fixed(); }

#endif
