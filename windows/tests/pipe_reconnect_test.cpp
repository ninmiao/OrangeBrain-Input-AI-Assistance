// Regression test: a client write that fails because the server dropped the
// pipe must reconnect and retry with a valid handle. Strict handle checking
// is enabled the way SearchHost / UWP hosts run, so passing a bad handle to
// WriteFile raises STATUS_INVALID_HANDLE and terminates this process.
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <PipeChannel.h>
#include <atomic>
#include <iostream>
#include <stdexcept>
#include <thread>

namespace {
struct Msg { DWORD command, wparam, lparam; };
int checks = 0;
void check(bool value, const char* message) { ++checks; if (!value) throw std::runtime_error(message); }

const wchar_t* kPipe = L"\\\\.\\pipe\\ZephyrPipeReconnectTest";

class TestClient : public weasel::PipeChannel<Msg, DWORD> {
 public:
  TestClient() : PipeChannel(std::wstring(kPipe)) {}
  // Server-side style send: must not reconnect after a write failure.
  void SendWithoutReconnect(Msg m) { _Send(*_GetPipeHandle(), m, false); }
};

std::atomic<int> connections{0};

// Each instance answers `replies` requests (echoing wparam+1), then closes
// its end so the client's next write fails.
void Serve(int replies) {
  HANDLE pipe = CreateNamedPipeW(kPipe, PIPE_ACCESS_DUPLEX,
                                 PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
                                 PIPE_UNLIMITED_INSTANCES, 4096, 4096, 0, nullptr);
  if (pipe == INVALID_HANDLE_VALUE) return;
  if (ConnectNamedPipe(pipe, nullptr) || GetLastError() == ERROR_PIPE_CONNECTED) {
    ++connections;
    for (int i = 0; i < replies; ++i) {
      char buffer[4096]; DWORD read = 0;
      if (!ReadFile(pipe, buffer, sizeof(buffer), &read, nullptr) || read < sizeof(Msg)) break;
      DWORD reply = reinterpret_cast<Msg*>(buffer)->wparam + 1, written = 0;
      WriteFile(pipe, &reply, sizeof(reply), &written, nullptr);
    }
    FlushFileBuffers(pipe);
    DisconnectNamedPipe(pipe);
  }
  CloseHandle(pipe);
}
}  // namespace

int main() {
  PROCESS_MITIGATION_STRICT_HANDLE_CHECK_POLICY strict{};
  strict.RaiseExceptionOnInvalidHandleReference = 1;
  strict.HandleExceptionsPermanentlyEnabled = 1;
  if (!SetProcessMitigationPolicy(ProcessStrictHandleCheckPolicy, &strict, sizeof(strict))) {
    std::cerr << "cannot enable strict handle checks\n";
    return 1;
  }
  try {
    // 1. First server instance answers once, then drops the client.
    std::thread first(Serve, 1);
    Sleep(100);
    TestClient client;
    Msg m{1, 10, 0};
    check(client.Transact(m) == 11, "first transaction is answered");
    first.join();

    // 2. Next write fails on the dropped pipe; the client must reconnect to
    //    the second instance and deliver the same request there.
    std::thread second(Serve, 1);
    Sleep(100);
    m.wparam = 20;
    check(client.Transact(m) == 21, "request is retried on the reconnected pipe");
    check(connections == 2, "client reconnected exactly once");
    second.join();

    // 3. Without reconnect (server-side use), a failed write throws and does
    //    not open a new connection.
    bool threw = false;
    try { client.SendWithoutReconnect(Msg{1, 30, 0}); } catch (DWORD) { threw = true; }
    check(threw, "send without reconnect reports the broken pipe");
    check(connections == 2, "no extra reconnect from a server-style send");

    // 4. No server at all: Transact must fail cleanly instead of writing to
    //    an invalid handle.
    TestClient orphan;
    threw = false;
    try { Msg o{1, 40, 0}; orphan.Transact(o); } catch (DWORD) { threw = true; }
    check(threw, "transact without a server throws instead of writing");
  } catch (const std::exception& e) {
    std::cerr << "FAIL after " << checks << " checks: " << e.what() << "\n";
    return 1;
  }
  std::cout << "pipe reconnect checks passed: " << checks << "\n";
  return 0;
}
