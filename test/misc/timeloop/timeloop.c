#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>

void use_localtime() {
  time_t tp;
  time(&tp);
  localtime(&tp);
}

void use_gettimeofday() {
  struct timeval tv;
  gettimeofday(&tv, NULL);
}

void use_none() {
  //empty
}

int main(int argc, char *argv[]) {

  //default settings
  int n = 1000000;
  char DEF_TIME_FUNCTION_NAME[] = "none";
  char *pTimeFuncName = DEF_TIME_FUNCTION_NAME;
  void (*pTimeFunc)() = &use_none;

  //parse args
  long nArg = 0;
  char *pEnd;
  int errno;
  if (argc == 1) {
    //defaults apply
  }
  else if (2 >= argc <= 3) {
    //function?
    if (strcmp(argv[1], DEF_TIME_FUNCTION_NAME) == 0) {
      pTimeFunc = &use_none;
    }
    else if (strcmp(argv[1], "localtime") == 0) {
      pTimeFunc = &use_localtime;
    }
    else if (strcmp(argv[1], "gettimeofday") == 0) {
      pTimeFunc = &use_gettimeofday;
    }
    else {
      fprintf(stderr, "1st argument does not match an expected value of either '%s', 'localtime' or 'gettimeofday'.\n", DEF_TIME_FUNCTION_NAME);
      return 1;
    }
    pTimeFuncName = argv[1];
    //itterations?
    if (argc == 3) {
      errno = 0;
      nArg = strtol(argv[2], &pEnd, 10);
      if (errno != 0 || pEnd == '\0' || nArg < 0 || nArg > INT_MAX) {
        fprintf (stderr, "2nd argument, \"%s\", was not a whole number or overflowed? error=%d, number found=%li, non-number string part='%s'\n", argv[2], errno, nArg, pEnd);
        return 1;
      }
      else {
        n = nArg;
      }
    }
  }
  else {
    fprintf(stderr, "Invalid number of arguments\n");
    return 1;
  }

  int i = 0;
  printf("Begin time loop func %s() calls with with %i itterations!\n", pTimeFuncName, n);
  for(i=0; i<n; i++) {
    pTimeFunc();
  }
  printf("Ended the time loop\n");
  return 0;

}
