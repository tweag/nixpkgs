#include <iostream>

extern "C" {
  #include "lib/name.h"
  #include "\@# $<>.h"
  #include <ncurses.h>
}

using namespace std;
int main()
{
  initscr();

  addstr("Hello there, ");
  addstr(name());
  addstr("!\n\n");
  addstr("press any key to exit...");
  refresh();

  getch();

  endwin();

  return 0;
}
