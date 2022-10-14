#include <iostream>

extern "C" {
  #include "name.h"
}

using namespace std;
int main()
{
  cout << "hello, " << name() << "!\n";
  return 0;
}
