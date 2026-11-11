int greet(void);

#ifdef GREET_PRIVATE
#error a private compile option reached a consumer
#endif

int main(void) { return greet() + GREET_PUBLIC + HEADERS_OPTION + APP_OWN == 13 ? 0 : 1; }
