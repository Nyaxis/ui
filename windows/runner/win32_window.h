#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // origin and size are logical; they are scaled for the default monitor since
  // the os takes physical pixels. the window stays hidden until Show is called
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  bool Show();

  void Destroy();

  void SetChildContent(HWND content);

  // nullptr once the window has been destroyed
  HWND GetHandle();

  // closing this window quits the application
  void SetQuitOnClose(bool quit_on_close);

  RECT GetClientArea();

 protected:
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // subclasses return false if their setup fails
  virtual bool OnCreate();

  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // enables non-client dpi scaling on WM_NCCREATE and forwards everything else
  // to MessageHandler
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  HWND window_handle_ = nullptr;

  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
