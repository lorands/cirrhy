#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shobjidl.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

// UTF-8 → UTF-16 for the overlay's accessibility description; utils.h only
// carries the opposite direction.
std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  int length = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                     static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring utf16(length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                        static_cast<int>(utf8.size()), utf16.data(), length);
  return utf16;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // The Windows half of the running-timer badge (TimerBadge on the Dart
  // side): a red-dot overlay in the taskbar icon's corner while a timer runs.
  badge_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.lorands.cirrhy/badge",
          &flutter::StandardMethodCodec::GetInstance());
  badge_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "setTimer") {
          result->NotImplemented();
          return;
        }
        bool running = false;
        std::string title;
        if (const auto* arguments =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          auto entry = arguments->find(flutter::EncodableValue("running"));
          if (entry != arguments->end()) {
            if (const auto* value = std::get_if<bool>(&entry->second)) {
              running = *value;
            }
          }
          entry = arguments->find(flutter::EncodableValue("title"));
          if (entry != arguments->end()) {
            if (const auto* value = std::get_if<std::string>(&entry->second)) {
              title = *value;
            }
          }
        }
        SetTimerOverlay(running, Utf16FromUtf8(title));
        result->Success();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetTimerOverlay(bool running,
                                    const std::wstring& description) {
  ITaskbarList3* taskbar = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_TaskbarList, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&taskbar)))) {
    return;
  }
  if (SUCCEEDED(taskbar->HrInit())) {
    if (running) {
      // Loaded at the small-icon metric — the size the overlay slot is
      // actually drawn at — rather than the 32px icon default.
      HICON overlay = static_cast<HICON>(::LoadImage(
          ::GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_BADGE_ICON),
          IMAGE_ICON, ::GetSystemMetrics(SM_CXSMICON),
          ::GetSystemMetrics(SM_CYSMICON), LR_DEFAULTCOLOR));
      taskbar->SetOverlayIcon(GetHandle(), overlay, description.c_str());
      if (overlay != nullptr) {
        ::DestroyIcon(overlay);
      }
    } else {
      taskbar->SetOverlayIcon(GetHandle(), nullptr, nullptr);
    }
  }
  taskbar->Release();
}
