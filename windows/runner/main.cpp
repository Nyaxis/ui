#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// whether a message is to be turned into a character message before it is
// delivered. windows hides the mouse pointer while the user types, which it
// does when a key press makes a character message, and the escape key makes one
// (the character 0x1b) though it types nothing, so the pointer went away when
// it was pressed. the key press is delivered as it is, and the pointer stays
static bool MakesCharacter(const ::MSG &msg) {
  return !(msg.message == WM_KEYDOWN && msg.wParam == VK_ESCAPE);
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // attach to the parent console (e.g. 'flutter run'), or create one under a
  // debugger
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // the engine and plugins expect com to be initialized
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(940, 620);
  if (!window.Create(L"ui", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    if (MakesCharacter(msg)) {
      ::TranslateMessage(&msg);
    }
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
