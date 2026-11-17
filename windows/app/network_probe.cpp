// SPDX-License-Identifier: GPL-3.0-or-later
#include "dictionary.h"
#include <iostream>
using namespace zw;
int main(){try{HttpOptions options;options.url="https://api.github.com/repos/amzxyz/rime-wanxiang/releases/latest";options.timeoutMs=20000;options.limit=2000000;auto response=http(options);require(response.status==200,"GitHub HTTPS metadata failed");auto release=parseRelease(response.body,"wanxiang");require(!release["asset"]["sha256"].get<std::string>().empty(),"Release checksum missing");std::cout<<"PASS: native WinHTTP HTTPS + official release metadata\n";return 0;}catch(const std::exception& e){std::cerr<<errorText(e)<<"\n";return 1;}}
