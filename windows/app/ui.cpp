// SPDX-License-Identifier: GPL-3.0-or-later
#include <windows.h>

#include <commctrl.h>
#include <shellapi.h>
#include <windowsx.h>

#include <algorithm>
#include <map>
#include <thread>

#include "dictionary.h"
#include "service.h"
namespace zw {
namespace {
enum Id {
  POLICIES = 100,
  NEW_POLICY,
  COPY_POLICY,
  DELETE_POLICY,
  TABS,
  STATUS,
  ACTIVE,
  SAVE,
  AI_MODE = 200,
  ENTER_ORIGINAL,
  SPACE_ORIGINAL,
  SEGMENTATION,
  DEBOUNCE,
  TIMEOUT,
  LANGUAGE,
  SCRIPT,
  CONTEXT,
  BEFORE,
  AFTER,
  BUDGET,
  SERVICE_STATUS,
  SERVICE_RESTART,
  AI_SHORTCUT,
  NAME = 300,
  ENDPOINT,
  MODEL,
  PROVIDER,
  REASONING,
  SPEED,
  KEY,
  MODELS_UPDATE,
  PROVIDERS_UPDATE,
  TEST_POLICY,
  TEST_RESULT,
  CHINESE_PROMPT,
  ENGLISH_PROMPT,
  KEY_STATE,
  BENCH_LIST = 400,
  BENCH_RUN,
  BENCH_RESULT,
  BENCH_CANCEL,
  DICT_CHOICE = 500,
  GRAMMAR,
  DICT_REDEPLOY,
  WANXIANG_UPDATE,
  ICE_UPDATE,
  MODEL_UPDATE,
  DICT_CANCEL,
  DICT_PROGRESS,
  DICT_STATUS,
  DICT_SOURCE
};
constexpr UINT JOB_DONE = WM_APP + 20, DICT_REPORT = WM_APP + 21,
               FOCUS_ENTER = WM_APP + 22;
const std::vector<std::string> languageValues = {"shift",
                                                 "shift_left",
                                                 "shift_right",
                                                 "ctrl_space",
                                                 "ctrl_shift_space",
                                                 "disabled"},
                               scriptValues = {"ctrl_shift_t", "ctrl_shift_f",
                                               "ctrl_shift_c", "disabled"},
                               aiShortcutValues = {"f8", "f9", "f10", "ctrl_shift_f8", "disabled"},
                               aiModeValues = {u8"无 / None", u8"仅纠错 / Correction only",
                                               u8"AI 助手＋纠错 / Assistant + correction"};
enum AiMode { NoAi, Correction, AssistantAndCorrection };
std::wstring text(HWND h) {
  int n = GetWindowTextLengthW(h);
  std::wstring s(n + 1, 0);
  GetWindowTextW(h, s.data(), n + 1);
  s.resize(n);
  return s;
}
void text(HWND h, const std::wstring& s) {
  std::wstring value;
  value.reserve(s.size());
  for (size_t i = 0; i < s.size(); ++i) {
    if (s[i] == L'\n' && (i == 0 || s[i-1] != L'\r')) value += L'\r';
    value += s[i];
  }
  SetWindowTextW(h, value.c_str());
}
void text(HWND h, const std::string& s) { text(h, wide(s)); }
void choices(HWND h, const std::vector<std::string>& values,
             const std::string& current) {
  SendMessageW(h, CB_RESETCONTENT, 0, 0);
  int index = -1;
  for (size_t i = 0; i < values.size(); i++) {
    auto w = wide(values[i]);
    SendMessageW(h, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(w.c_str()));
    if (values[i] == current) index = int(i);
  }
  if (index >= 0)
    SendMessageW(h, CB_SETCURSEL, index, 0);
  else
    text(h, current);
}
struct Done {
  int kind;
  bool partial = false;
  std::string policy, endpoint, model, error;
  J data;
  std::string output;
};
struct Item {
  HWND window;
  int x, y, width, height;
  bool fill;
  int column;
};
struct Page {
  HWND window = nullptr;
  std::vector<Item> items;
  int content = 0, scroll = 0;
};
class App {
  HINSTANCE instance_;
  Store store_;
  J config_, saved_;
  std::map<std::string, std::pair<std::string, std::string>> pendingKeys_;
  bool dirty_ = false, dictionaryDirty_ = false, benchmarkInitialized_ = false;
  int column_ = -1, flash_ = 0;
  HBRUSH flashBrush_ = nullptr;
  std::vector<int> changed_, highlighted_;
  std::vector<std::string> benchmarkIds_;
  HWND window_ = nullptr;
  std::map<int, HWND> controls_;
  static constexpr int PAGE_COUNT = 5;
  Page pages_[PAGE_COUNT];
  HFONT font_ = nullptr, smallFont_ = nullptr;
  int dpi_ = 96, tab_ = 0;
  bool loading_ = false, closing_ = false, smoke_ = false;
  std::string editing_;
  std::vector<std::thread> workers_;
  std::shared_ptr<Cancel> apiCancel_, dictCancel_;
  bool apiBusy_ = false, dictBusy_ = false, dictCancelable_ = true;
  int px(int x) const { return MulDiv(x, dpi_, 96); }
  HWND control(int id) const { return controls_.at(id); }
  void serviceState() {
    auto dir=appDirectory();
    bool broker=processRunning(dir/L"ZephyrBroker.exe"),server=processRunning(dir/L"ZephyrServer.exe");
    std::string value=std::string(u8"AI 后台：")+(broker?u8"运行":u8"未运行")+u8" · 输入服务："+(server?u8"运行":u8"未运行");
    const auto config = store_.load();
    value+=(config["enabled"].get<bool>() || config["assistantEnabled"].get<bool>())
        ? u8" · 自动请求" : u8" · 手动请求";
    auto path=store_.directory()/L"last-request-status.json";
    if(fs::exists(path)) {auto r=J::parse(readFile(path,4096),nullptr,false);if(r.is_object())value+=u8"\n最近请求："+r.value("state",std::string())+" · "+r.value("time",std::string());}
    else value+=u8"\n尚未收到请求结果（运行不代表 API 已连通）";
    if(utf8(text(control(SERVICE_STATUS)))!=value)text(control(SERVICE_STATUS),value);
  }
  void restartServices() {
    EnableWindow(control(SERVICE_RESTART),FALSE);text(control(SERVICE_STATUS),L"正在重启服务…");
    auto target=window_;auto dir=appDirectory();
    workers_.emplace_back([target,dir] {
      auto d=std::make_unique<Done>();d->kind=SERVICE_RESTART;
      try {stopUserProcess(dir/L"ZephyrServer.exe");stopUserProcess(dir/L"ZephyrBroker.exe");zw::run(dir/L"ZephyrBroker.exe",{});}
      catch(const std::exception& e){d->error=errorText(e);}
      if(PostMessageW(target,JOB_DONE,0,reinterpret_cast<LPARAM>(d.get())))d.release();
    });
  }
  void status(const std::string& s) { text(control(STATUS), s); }
  void modified(int id = 0) {
    if (loading_) return;
    dirty_ = true;
    if (id && std::find(changed_.begin(), changed_.end(), id) == changed_.end())
      changed_.push_back(id);
    status(u8"有未保存的修改 / Unsaved changes");
    text(control(SAVE), L"保存并生效 / Save");
    EnableWindow(control(SAVE), TRUE);
  }
  void savedFeedback() {
    dirty_ = false;
    highlighted_ = std::move(changed_);
    changed_.clear();
    status(u8"✓ 参数已保存并生效 / Changes saved and applied");
    text(control(SAVE), L"✓ 已保存 / Saved");
    EnableWindow(control(SAVE), FALSE);
    flash_ = 24;
    SetTimer(window_, 4, 40, nullptr);
  }
  void wipeKeys() {
    for (auto& entry : pendingKeys_)
      SecureZeroMemory(entry.second.first.data(), entry.second.first.size());
    pendingKeys_.clear();
  }
  void captureKey() {
    auto secret = utf8(text(control(KEY)));
    if (secret.empty()) return;
    auto& draft = pendingKeys_[editing_];
    SecureZeroMemory(draft.first.data(), draft.first.size());
    draft = {secret, utf8(text(control(ENDPOINT)))};
    SecureZeroMemory(secret.data(), secret.size());
  }
  static LRESULT CALLBACK focusProc(HWND h, UINT m, WPARAM w, LPARAM l,
                                    UINT_PTR, DWORD_PTR data) {
    if (m == WM_MOUSEWHEEL) {
      wchar_t cls[32]{};
      GetClassNameW(h, cls, 32);
      // Scrolling a settings page must not silently change the model or routing.
      if (!wcscmp(cls, L"ComboBox") && !SendMessageW(h, CB_GETDROPPEDSTATE, 0, 0)) {
        auto app = reinterpret_cast<App*>(data);
        for (int i = 0; i < PAGE_COUNT; ++i)
          if (GetParent(h) == app->pages_[i].window) {
            app->scroll(i, m, w);
            return 0;
          }
      }
    }
    if (m == WM_SETFOCUS) {
      auto app = reinterpret_cast<App*>(data);
      SendMessageW(app->window_, FOCUS_ENTER, 0, reinterpret_cast<LPARAM>(h));
    }
    return DefSubclassProc(h, m, w, l);
  }
  void reveal(HWND h) {
    for (auto& item : pages_[tab_].items)
      if (item.window == h || IsChild(item.window, h)) {
        auto& page = pages_[tab_];
        RECT r;
        GetClientRect(page.window, &r);
        int top = px(item.y), bottom = top + px(item.height);
        if (top < page.scroll)
          page.scroll = top;
        else if (bottom > page.scroll + r.bottom)
          page.scroll = bottom - r.bottom + px(8);
        layoutPage(tab_);
        break;
      }
  }
  static LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l) {
    auto self = reinterpret_cast<App*>(GetWindowLongPtrW(h, GWLP_USERDATA));
    if (m == WM_NCCREATE) {
      self = static_cast<App*>(
          reinterpret_cast<CREATESTRUCTW*>(l)->lpCreateParams);
      SetWindowLongPtrW(h, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
      self->window_ = h;
    }
    if (!self) return DefWindowProcW(h, m, w, l);
    try {
      return self->message(m, w, l);
    } catch (const std::exception& e) {
      self->loading_ = false; if (self->controls_.count(STATUS)) self->status(errorText(e));
      return 0;
    }
  }
  static LRESULT CALLBACK pageProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    auto self = reinterpret_cast<App*>(GetWindowLongPtrW(h, GWLP_USERDATA));
    if (m == WM_NCCREATE) {
      self = static_cast<App*>(
          reinterpret_cast<CREATESTRUCTW*>(l)->lpCreateParams);
      SetWindowLongPtrW(h, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (!self) return DefWindowProcW(h, m, w, l);
    if (m == WM_CTLCOLOREDIT || m == WM_CTLCOLORSTATIC) {
      if (auto brush = self->colorControl(w, l)) return reinterpret_cast<LRESULT>(brush);
    }
    if (m == WM_COMMAND || m == WM_NOTIFY)
      return SendMessageW(self->window_, m, w, l);
    if (m == WM_VSCROLL || m == WM_MOUSEWHEEL) {
      int index = 0;
      while (index < PAGE_COUNT && self->pages_[index].window != h) index++;
      if (index < PAGE_COUNT) self->scroll(index, m, w);
      return 0;
    }
    return DefWindowProcW(h, m, w, l);
  }
  HBRUSH colorControl(WPARAM w, LPARAM l) {
    int id = GetDlgCtrlID(reinterpret_cast<HWND>(l));
    if (flash_ && (id == STATUS ||
        std::find(highlighted_.begin(), highlighted_.end(), id) != highlighted_.end())) {
      int tint = flash_ * 35 / 24;
      COLORREF color = RGB(255 - tint, 255, 255 - tint);
      if (flashBrush_) DeleteObject(flashBrush_);
      flashBrush_ = CreateSolidBrush(color);
      SetBkColor(reinterpret_cast<HDC>(w), color);
      return flashBrush_;
    }
    return nullptr;
  }
  HWND make(HWND parent, const wchar_t* cls, const std::wstring& label,
            DWORD style, int id) {
    HWND h = CreateWindowExW((style & WS_BORDER) ? WS_EX_CLIENTEDGE : 0, cls,
                             label.c_str(), WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | style, 0, 0,
                             0, 0, parent, reinterpret_cast<HMENU>(INT_PTR(id)),
                             instance_, nullptr);
    require(h != nullptr, "Cannot create settings control");
    SendMessageW(h, WM_SETFONT, reinterpret_cast<WPARAM>(font_), TRUE);
    if (id) controls_[id] = h;
    SetWindowSubclass(h, focusProc, 1, reinterpret_cast<DWORD_PTR>(this));
    return h;
  }
  HWND item(int page, const wchar_t* cls, const std::wstring& label,
            DWORD style, int id, int y, int height = 28, int x = 16,
            int width = 0) {
    auto h = make(pages_[page].window, cls, label, style, id);
    pages_[page].items.push_back({h, x, y, width, height, width == 0, column_});
    pages_[page].content = std::max(pages_[page].content, y + height + 18);
    return h;
  }
  void label(int page, const wchar_t* value, int y, int height = 24) {
    item(page, L"STATIC", value, SS_LEFT, 0, y, height);
  }
  void field(int page, int id, const wchar_t* caption, int y,
             bool combo = false, bool fixed = false) {
    label(page, caption, y);
    auto h =
        item(page, combo ? L"COMBOBOX" : L"EDIT", L"",
             WS_TABSTOP |
                 (combo ? (fixed ? CBS_DROPDOWNLIST : CBS_DROPDOWN) | WS_VSCROLL
                        : WS_BORDER | ES_AUTOHSCROLL),
             id, y + 25, 28);
    if (combo) {
      pages_[page].items.back().height = 28;
      SendMessageW(h, CB_SETMINVISIBLE, 12, 0);
    } else
      SendMessageW(h, EM_SETLIMITTEXT, 8192, 0);
  }
  void check(int page, int id, const wchar_t* caption, int y) {
    item(page, L"BUTTON", caption, WS_TABSTOP | BS_AUTOCHECKBOX, id, y);
  }
  void button(int page, int id, const wchar_t* caption, int y) {
    item(page, L"BUTTON", caption, WS_TABSTOP | BS_PUSHBUTTON, id, y, 30);
  }
  void multiline(int page, int id, int y, int height, bool readOnly = false) {
    auto h = item(page, L"EDIT", L"",
                  WS_TABSTOP | WS_BORDER | WS_VSCROLL | ES_MULTILINE |
                      ES_AUTOVSCROLL | (readOnly ? ES_READONLY : 0),
                  id, y, height);
    SendMessageW(h, EM_SETLIMITTEXT, readOnly ? 65536 : 8192, 0);
  }
  void fonts() {
    if (font_) DeleteObject(font_);
    if (smallFont_) DeleteObject(smallFont_);
    font_ =
        CreateFontW(-px(14), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                    DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                    DEFAULT_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    smallFont_ =
        CreateFontW(-px(12), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                    DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                    DEFAULT_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    for (auto& c : controls_)
      SendMessageW(
          c.second, WM_SETFONT,
          reinterpret_cast<WPARAM>(c.first == POLICIES ? smallFont_ : font_),
          TRUE);
    for (auto& page : pages_)
      for (auto& i : page.items)
        SendMessageW(i.window, WM_SETFONT, reinterpret_cast<WPARAM>(font_),
                     TRUE);
  }
  void create() {
    auto dpiFunction = reinterpret_cast<UINT(WINAPI*)(HWND)>(
        GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow"));
    if (dpiFunction)
      dpi_ = int(dpiFunction(window_));
    else {
      auto dc = GetDC(window_);
      dpi_ = GetDeviceCaps(dc, LOGPIXELSX);
      ReleaseDC(window_, dc);
    }
    fonts();
    make(window_, L"STATIC", L"Zephyr Input", SS_LEFT, ACTIVE);
    auto policies = make(window_, L"LISTBOX", L"",
                         WS_TABSTOP | WS_BORDER | WS_VSCROLL | LBS_NOTIFY |
                             LBS_OWNERDRAWFIXED | LBS_HASSTRINGS,
                         POLICIES);
    SendMessageW(policies, WM_SETFONT, reinterpret_cast<WPARAM>(smallFont_),
                 TRUE);
    SendMessageW(policies, LB_SETITEMHEIGHT, 0, px(23));
    make(window_, L"BUTTON", L"新建 / New", WS_TABSTOP, NEW_POLICY);
    make(window_, L"BUTTON", L"复制含 Key / Copy", WS_TABSTOP, COPY_POLICY);
    make(window_, L"BUTTON", L"删除 / Delete", WS_TABSTOP, DELETE_POLICY);
    auto tabs = make(window_, WC_TABCONTROLW, L"", WS_TABSTOP, TABS);
    for (auto caption : {L"输入 / Input", L"方案 / Policy", L"测速 / Benchmark",
                         L"词库 / Dictionary", L"提示词 / Prompts"}) {
      TCITEMW ti{};
      ti.mask = TCIF_TEXT;
      ti.pszText = const_cast<LPWSTR>(caption);
      TabCtrl_InsertItem(tabs, TabCtrl_GetItemCount(tabs), &ti);
    }
    make(window_, L"STATIC", L"", SS_LEFT, STATUS);
    make(window_, L"BUTTON", L"保存并生效 / Save", WS_TABSTOP | BS_DEFPUSHBUTTON, SAVE);
    for (auto& p : pages_)
      p.window = CreateWindowExW(WS_EX_CONTROLPARENT, L"ZephyrNativePage", L"",
                                 WS_CHILD | WS_VISIBLE | WS_VSCROLL | WS_CLIPCHILDREN | WS_CLIPSIBLINGS, 0, 0, 0, 0,
                                 window_, nullptr, instance_, this);
    column_ = 0;
    field(0, AI_MODE, L"AI 增强（自动）/ Automatic AI", 12, true, true);
    check(0, ENTER_ORIGINAL, L"回车提交原文 / Enter: original", 76);
    check(0, SPACE_ORIGINAL, L"空格提交原文 / Space: original", 108);
    check(0, SEGMENTATION, L"空格分词 / Phrase boundaries", 140);
    field(0, LANGUAGE, L"中英快捷键 / Language shortcut", 176, true, true);
    field(0, SCRIPT, L"繁简快捷键 / Script shortcut", 235, true, true);
    field(0, AI_SHORTCUT, L"AI 重试／召唤助手 / AI shortcut", 294, true, true);
    column_ = 1;
    field(0, DEBOUNCE, L"停顿 / Debounce (50–2000 ms)", 12);
    field(0, TIMEOUT, L"总超时 / Timeout (1000–60000 ms)", 82);
    field(0, BUDGET, L"输出 Token 预算 / Budget (1–65536)", 152);
    check(0, CONTEXT, L"参考前后文 / Surrounding text", 226);
    field(0, BEFORE, L"前文字符 / Before (0–500)", 266);
    field(0, AFTER, L"后文字符 / After (0–500)", 336);
    column_ = 0;
    button(0,SERVICE_RESTART,L"重启服务（取消未上屏文字）",356);
    column_ = -1;
    label(0,L"",396,48);controls_[SERVICE_STATUS]=pages_[0].items.back().window;
    column_ = 0;
    field(1, NAME, L"方案名称 / Policy name", 12);
    field(1, ENDPOINT, L"HTTPS 接口 / API endpoint", 82);
    field(1, MODEL, L"模型（可选或输入）/ Model", 152, true);
    button(1, MODELS_UPDATE, L"更新模型列表 / Update models", 216);
    field(1, PROVIDER, L"OpenRouter 提供商 / Provider", 264, true);
    button(1, PROVIDERS_UPDATE, L"更新提供商 / Update providers", 328);
    column_ = 1;
    field(1, REASONING, L"思考强度 / Reasoning (omit: 默认)", 12, true, true);
    field(1, SPEED, L"速度 / Speed (priority: 快速)", 82, true, true);
    field(1, KEY, L"API Key（留空保留已存 Key）", 152);
    SendMessageW(control(KEY), EM_SETPASSWORDCHAR, L'\x25cf', 0);
    label(1, L"", 216);
    controls_[KEY_STATE] = pages_[1].items.back().window;
    button(1, TEST_POLICY, L"测试此方案 / Test this policy", 264);
    multiline(1, TEST_RESULT, 306, 136, true);
    column_ = -1;
    label(2, L"勾选要测试的方案（最多 5 个），一次运行显示全部结果。", 12);
    item(2, WC_LISTVIEWW, L"", WS_TABSTOP | WS_BORDER | LVS_REPORT |
             LVS_NOCOLUMNHEADER | LVS_SHOWSELALWAYS,
         BENCH_LIST, 44, 144);
    ListView_SetExtendedListViewStyle(control(BENCH_LIST),
        LVS_EX_CHECKBOXES | LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER);
    LVCOLUMNW col{}; col.mask = LVCF_WIDTH; col.cx = px(800);
    ListView_InsertColumn(control(BENCH_LIST), 0, &col);
    column_ = 0;
    button(2, BENCH_RUN, L"一键测试勾选方案 / Run checked", 204);
    column_ = 1;
    button(2, BENCH_CANCEL, L"取消测速 / Cancel", 204);
    column_ = -1;
    label(2, L"使用已保存的参数与 Key；长句样例包含前后文。", 248);
    multiline(2, BENCH_RESULT, 280, 162, true);
    EnableWindow(control(BENCH_CANCEL), FALSE);
    column_ = -1;
    label(3, L"万象、雾凇词表已内置，可离线切换。407 MB 语法模型单独下载。", 12);
    column_ = 0;
    field(3, DICT_CHOICE, L"当前词库 / Dictionary", 52, true, true);
    check(3, GRAMMAR, L"万象语法模型 / Grammar model", 122);
    button(3, DICT_REDEPLOY, L"重新部署 / Redeploy", 174);
    button(3, WANXIANG_UPDATE, L"更新万象词表 / Update Wanxiang", 218);
    button(3, ICE_UPDATE, L"更新雾凇词表 / Update Rime Ice", 262);
    button(3, MODEL_UPDATE, L"下载 / 更新语法模型 / Grammar", 306);
    button(3, DICT_CANCEL, L"暂停下载 / Pause", 350);
    column_ = 1;
    label(3, L"词库状态 / Dictionary status", 52);
    multiline(3, DICT_STATUS, 84, 208, true);
    item(3, PROGRESS_CLASSW, L"", 0, DICT_PROGRESS, 308, 20);
    button(3, DICT_SOURCE, L"来源与许可 / Source and license", 350);
    column_ = -1;
    label(3, L"选择词库或模型开关后点击保存；下载支持续传及 SHA-256 校验。", 396);
    label(3, L"部署失败会恢复原配置；语法模型仅搭配万象词表使用。", 424);
    EnableWindow(control(DICT_CANCEL), FALSE);
    label(4, L"系统提示词自动生成；以下为所选方案的附加提示词，修改后保存。", 12);
    column_ = 0;
    label(4, L"中文附加提示词 / Chinese", 52);
    multiline(4, CHINESE_PROMPT, 84, 350);
    column_ = 1;
    label(4, L"英文附加提示词 / English", 52);
    multiline(4, ENGLISH_PROMPT, 84, 350);
    column_ = -1;
    loadGlobal();
    reload();
    dictionaryState();
    status(u8"修改后请保存 / Save to apply changes");
    EnableWindow(control(SAVE), FALSE);
    layout();
    serviceState();SetTimer(window_,10,2000,nullptr);
    if (smoke_) SetTimer(window_, 9, 300, nullptr);
  }
  void layout() {
    RECT rect; GetClientRect(window_, &rect);
    int width = rect.right, height = rect.bottom;
    MoveWindow(control(ACTIVE), px(12), px(10), width-px(220), px(26), FALSE);
    MoveWindow(control(SAVE), width-px(194), px(6), px(182), px(34), FALSE);
    MoveWindow(control(POLICIES), px(12), px(46), width-px(220), px(88), FALSE);
    for (int i=0; i<3; ++i)
      MoveWindow(control(NEW_POLICY+i), width-px(194), px(46+i*30), px(182), px(27), FALSE);
    MoveWindow(control(TABS), px(8), px(146), width-px(16), px(30), FALSE);
    MoveWindow(control(STATUS), px(12), height-px(30), width-px(24), px(26), FALSE);
    for (int i=0; i<PAGE_COUNT; ++i) {
      MoveWindow(pages_[i].window, px(8), px(182), width-px(16),
                 std::max(1,height-px(222)), FALSE);
      ShowWindow(pages_[i].window, i==tab_ ? SW_SHOW : SW_HIDE);
      layoutPage(i);
    }
    RedrawWindow(window_, nullptr, nullptr, RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN);
  }
  void layoutPage(int i) {
    auto& p=pages_[i]; RECT r; GetClientRect(p.window,&r);
    int content=px(p.content);
    p.scroll=std::clamp(p.scroll,0,std::max(0,content-int(r.bottom)));
    SCROLLINFO si{sizeof(si),SIF_RANGE|SIF_PAGE|SIF_POS,0,content-1,UINT(r.bottom),p.scroll,0};
    SetScrollInfo(p.window,SB_VERT,&si,TRUE);
    GetClientRect(p.window,&r); // account for the scrollbar appearing/disappearing
    auto batch=BeginDeferWindowPos(int(p.items.size()));
    for (auto& item:p.items) {
      int colWidth=(int(r.right)-px(36))/2;
      int x=item.column<0 ? px(item.x) : px(12)+item.column*(colWidth+px(12));
      int w=item.column<0 ? (item.fill ? int(r.right)-px(item.x+16) : px(item.width)) : colWidth;
      wchar_t cls[32]{}; GetClassNameW(item.window,cls,32);
      int h=px(!wcscmp(cls,L"ComboBox")?250:item.height);
      batch=DeferWindowPos(batch,item.window,nullptr,x,px(item.y)-p.scroll,std::max(px(100),w),h,
                          SWP_NOZORDER|SWP_NOACTIVATE|SWP_NOREDRAW);
    }
    if(batch) EndDeferWindowPos(batch);
    if(i==2) ListView_SetColumnWidth(control(BENCH_LIST),0,LVSCW_AUTOSIZE_USEHEADER);
    RedrawWindow(p.window,nullptr,nullptr,RDW_INVALIDATE|RDW_ERASE|RDW_ALLCHILDREN);
  }
  void scroll(int i, UINT m, WPARAM w) {
    auto& p = pages_[i];
    if (m == WM_MOUSEWHEEL)
      p.scroll -= GET_WHEEL_DELTA_WPARAM(w) * px(48) / WHEEL_DELTA;
    else {
      SCROLLINFO si{sizeof(si), SIF_ALL};
      GetScrollInfo(p.window, SB_VERT, &si);
      switch (LOWORD(w)) {
        case SB_LINEUP:
          p.scroll -= px(28);
          break;
        case SB_LINEDOWN:
          p.scroll += px(28);
          break;
        case SB_PAGEUP:
          p.scroll -= int(si.nPage);
          break;
        case SB_PAGEDOWN:
          p.scroll += int(si.nPage);
          break;
        case SB_THUMBTRACK:
          p.scroll = si.nTrackPos;
          break;
        case SB_TOP:
          p.scroll = 0;
          break;
        case SB_BOTTOM:
          p.scroll = si.nMax;
          break;
      }
    }
    layoutPage(i);
  }
  void checkValue(int id, bool value) {
    SendMessageW(control(id), BM_SETCHECK, value ? BST_CHECKED : BST_UNCHECKED,
                 0);
  }
  bool checked(int id) {
    return SendMessageW(control(id), BM_GETCHECK, 0, 0) == BST_CHECKED;
  }
  void loadGlobal() {
    loading_ = true;
    const auto mode = config_["assistantEnabled"].get<bool>() ? AssistantAndCorrection
        : config_["enabled"].get<bool>() ? Correction : NoAi;
    choices(control(AI_MODE), aiModeValues, aiModeValues[mode]);
    for (auto pair : {std::pair<int, const char*>{ENTER_ORIGINAL, "enterOriginal"},
                      {SPACE_ORIGINAL, "spaceOriginal"},
                      {SEGMENTATION, "wordSegmentation"},
                      {CONTEXT, "contextEnabled"}})
      checkValue(pair.first, config_[pair.second]);
    for (auto pair : {std::pair<int, const char*>{DEBOUNCE, "debounceMs"},
                      {TIMEOUT, "timeoutMs"},
                      {BEFORE, "beforeLength"},
                      {AFTER, "afterLength"},
                      {BUDGET, "outputTokenBudget"}})
      text(control(pair.first),
           std::to_string(config_[pair.second].get<int>()));
    choices(control(LANGUAGE), languageValues, config_["languageShortcut"]);
    choices(control(SCRIPT), scriptValues, config_["scriptShortcut"]);
    choices(control(AI_SHORTCUT), aiShortcutValues, config_["aiShortcut"]);
    loading_ = false;
  }
  std::string policyLabel(const J& p) {
    return (p["id"] == config_["selectedPolicy"] ? u8"● " : "  ") +
           p["name"].get<std::string>() + " · " +
           p["model"].get<std::string>() + " · " +
           p["reasoning"].get<std::string>() + " / " +
           p["speed"].get<std::string>() +
           (p["provider"].get<std::string>().empty()
                ? ""
                : " · " + p["provider"].get<std::string>());
  }
  void reload(bool form = true) {
    loading_ = true;
    auto oldSelection = benchmarkSelection();
    SendMessageW(control(POLICIES), LB_RESETCONTENT, 0, 0);
    ListView_DeleteAllItems(control(BENCH_LIST));
    benchmarkIds_.clear();
    int selected = 0;
    for (size_t i = 0; i < config_["policies"].size(); i++) {
      auto& p = config_["policies"][i];
      auto s = wide(policyLabel(p));
      SendMessageW(control(POLICIES), LB_ADDSTRING, 0,
                   reinterpret_cast<LPARAM>(s.c_str()));
      LVITEMW item{}; item.mask=LVIF_TEXT; item.iItem=int(i); item.pszText=s.data();
      ListView_InsertItem(control(BENCH_LIST),&item);
      benchmarkIds_.push_back(p["id"]);
      bool checked = !benchmarkInitialized_ ? i<5 :
          std::find(oldSelection.begin(),oldSelection.end(),p["id"])!=oldSelection.end();
      ListView_SetCheckState(control(BENCH_LIST),int(i),checked);
      if (p["id"] == config_["selectedPolicy"]) selected = int(i);
    }
    benchmarkInitialized_=true;
    SendMessageW(control(POLICIES), LB_SETCURSEL, selected, 0);
    EnableWindow(control(DELETE_POLICY), config_["policies"].size() > 1);
    text(control(ACTIVE),
         u8"正在使用 / Active: " +
             activePolicy(saved_)["name"].get<std::string>() +
             ((saved_["enabled"].get<bool>() || saved_["assistantEnabled"].get<bool>()) ? "" : u8" · AI 手动触发"));
    if (form) loadPolicy();
    loading_ = false;
  }
  void loadPolicy() {
    auto& p = activePolicy(config_);
    editing_ = p["id"];
    for (auto pair : {std::pair<int, const char*>{NAME, "name"},
                      {ENDPOINT, "endpoint"},
                      {CHINESE_PROMPT, "chinesePrompt"},
                      {ENGLISH_PROMPT, "englishPrompt"}})
      text(control(pair.first), p[pair.second].get<std::string>());
    std::vector<std::string> models = {p["model"]};
    auto cache = p.value("modelList", J());
    if (cache.is_object() && cache.value("endpoint", "") == p["endpoint"])
      for (auto& v : cache.value("ids", J::array()))
        if (v != p["model"]) models.push_back(v);
    choices(control(MODEL), models, p["model"]);
    choices(control(PROVIDER), {p["provider"]}, p["provider"]);
    choices(control(REASONING), reasoningOptions(p), p["reasoning"]);
    choices(control(SPEED), {"default", "priority"}, p["speed"]);
    bool router =
        core("routing", {{"endpoint", p["endpoint"]}})["api"] == "openrouter";
    EnableWindow(control(PROVIDER), router);
    EnableWindow(control(PROVIDERS_UPDATE), router && !apiBusy_);
    EnableWindow(
        control(SPEED),
        core("routing", {{"endpoint", p["endpoint"]}})["api"] != "gemini");
    text(control(KEY), pendingKeys_.count(editing_) ? pendingKeys_.at(editing_).first : "");
    text(control(KEY_STATE), pendingKeys_.count(editing_) ? u8"Key 待保存 / Key not saved" : store_.hasKey(editing_)
                                 ? u8"Key 已加密保存 / Encrypted key saved"
                                 : u8"尚未配置 Key / No key saved");
    text(control(TEST_RESULT), L"");

  }
  bool capture(bool quiet = true) {
    if (loading_) return true;
    KillTimer(window_, 2);
    try {
      refreshParameters(false);
      J next = config_;
      auto& p = activePolicy(next);
      require(p["id"] == editing_, "Policy changed");
      for (auto pair : {std::pair<int, const char*>{NAME, "name"},
                        {ENDPOINT, "endpoint"},
                        {MODEL, "model"},
                        {PROVIDER, "provider"},
                        {REASONING, "reasoning"},
                        {SPEED, "speed"},
                        {CHINESE_PROMPT, "chinesePrompt"},
                        {ENGLISH_PROMPT, "englishPrompt"}})
        p[pair.second] = utf8(text(control(pair.first)));
      auto mode = SendMessageW(control(AI_MODE), CB_GETCURSEL, 0, 0);
      require(mode >= NoAi && mode <= AssistantAndCorrection, "Choose an AI mode");
      next["enabled"] = mode != NoAi;
      next["assistantEnabled"] = mode == AssistantAndCorrection;
      for (auto pair : {std::pair<int, const char*>{ENTER_ORIGINAL, "enterOriginal"},
                        {SPACE_ORIGINAL, "spaceOriginal"},
                        {SEGMENTATION, "wordSegmentation"},
                        {CONTEXT, "contextEnabled"}})
        next[pair.second] = checked(pair.first);
      for (auto pair : {std::pair<int, const char*>{DEBOUNCE, "debounceMs"},
                        {TIMEOUT, "timeoutMs"},
                        {BEFORE, "beforeLength"},
                        {AFTER, "afterLength"},
                        {BUDGET, "outputTokenBudget"}}) {
        auto s = text(control(pair.first));
        require(!s.empty() && s.find_first_not_of(L"0123456789") == s.npos &&
                    s.size() < 8,
                "Enter a valid numeric setting");
        next[pair.second] = std::stoi(s);
      }
      next["languageShortcut"] = utf8(text(control(LANGUAGE)));
      next["scriptShortcut"] = utf8(text(control(SCRIPT)));
      next["aiShortcut"] = utf8(text(control(AI_SHORTCUT)));
      validateConfiguration(next);
      captureKey();
      config_ = std::move(next);
      return true;
    } catch (const std::exception& e) {
      status(u8"待完成设置 / Complete setting: " + errorText(e));
      if (!quiet)
        MessageBoxW(window_, wide(errorText(e)).c_str(), L"Zephyr Input",
                    MB_OK | MB_ICONINFORMATION);
      return false;
    }
  }
  bool save(bool quiet = true) {
    if (!capture(quiet)) return false;
    try {
      for (auto& p : config_["policies"]) {
        auto id=p["id"].get<std::string>();
        auto key=pendingKeys_.find(id);
        if (key!=pendingKeys_.end())
          store_.saveKey(id,key->second.first,key->second.second);
      }
      store_.save(config_);
      for (auto& old : saved_["policies"]) {
        bool exists=false;
        for (auto& p:config_["policies"]) if(p["id"]==old["id"]) exists=true;
        if(!exists) store_.eraseKey(old["id"]);
      }
      saved_=config_;
      wipeKeys();
      loading_=true;
      text(control(KEY),L"");
      text(control(KEY_STATE),store_.hasKey(editing_)?u8"Key 已加密保存 / Key saved":u8"尚未配置 Key / No key");
      loading_=false;
      reload(false);
      savedFeedback();
      if(dictionaryDirty_) { dictionaryDirty_=false; startDictionary(DICT_REDEPLOY); }
      return true;
    } catch(const std::exception& e) {
      status(u8"保存失败 / Save failed: "+errorText(e));
      return false;
    }
  }
  void refreshParameters(bool notify = true) {
    if (loading_) return;
    loading_ = true;
    auto p = activePolicy(config_);
    p["endpoint"] = utf8(text(control(ENDPOINT)));
    p["model"] = utf8(text(control(MODEL)));
    auto levels = reasoningOptions(p);
    auto current = utf8(text(control(REASONING)));
    if (std::find(levels.begin(), levels.end(), current) == levels.end())
      current = "omit";
    choices(control(REASONING), levels, current);
    auto routing = core("routing", {{"endpoint", p["endpoint"]}});
    bool router = routing["api"] == "openrouter",
         gemini = routing["api"] == "gemini";
    EnableWindow(control(PROVIDER), router);
    EnableWindow(control(PROVIDERS_UPDATE), router && !apiBusy_);
    EnableWindow(control(SPEED), !gemini);
    if (gemini) choices(control(SPEED), {"default", "priority"}, "default");
    loading_ = false;
    if (notify) modified(MODEL);
  }
  std::vector<std::string> benchmarkSelection() {
    std::vector<std::string> result;
    if (!controls_.count(BENCH_LIST)) return result;
    for(size_t i=0;i<benchmarkIds_.size();++i)
      if(ListView_GetCheckState(control(BENCH_LIST),int(i)))
        result.push_back(benchmarkIds_[i]);
    return result;
  }
  void apiButtons(bool busy) {
    apiBusy_ = busy;
    for (int id : {MODELS_UPDATE, PROVIDERS_UPDATE, TEST_POLICY, BENCH_RUN})
      EnableWindow(
          control(id),
          !busy && (id != PROVIDERS_UPDATE ||
                    core("routing", {{"endpoint",
                                      utf8(text(control(ENDPOINT)))}})["api"] ==
                        "openrouter"));
    EnableWindow(control(BENCH_CANCEL), busy);
  }
  void startApi(int kind) {
    if (apiBusy_) return;
    if (dirty_) {
      if (kind != MODELS_UPDATE) {
        status(u8"请先保存修改，再测速或更新供应商 / Save changes first");
        return;
      }
      if (!capture(false)) return;
    }
    auto snapshot = config_, p = activePolicy(config_);
    auto selected = benchmarkSelection();
    if (kind == BENCH_RUN) {
      std::vector<std::string> available;
      for (auto& policy : config_["policies"])
        available.push_back(policy["id"]);
      core("benchmarkPolicies",
           {{"selected", selected}, {"available", available}});
    }
    apiCancel_ = std::make_shared<Cancel>();
    auto cancel = apiCancel_;
    apiButtons(true);
    auto target = window_;
    auto store = store_;
    status(u8"处理中 / Working…");
    workers_.emplace_back([target, kind, snapshot, p, selected, cancel, store] {
      auto done = std::make_unique<Done>();
      done->kind = kind;
      done->policy = p["id"];
      done->endpoint = p["endpoint"];
      done->model = p["model"];
      try {
        if (kind == MODELS_UPDATE)
          done->data =
              discoverModels(p, store.key(p["id"], p["endpoint"]), cancel);
        else if (kind == PROVIDERS_UPDATE)
          done->data = discoverProviders(p["model"], cancel);
        else {
          auto test = [&](const J& item, bool chinese) {
            auto begin = Clock::now();
            auto heading=item["name"].get<std::string>()+" · "+item["model"].get<std::string>()+
                " · "+item["reasoning"].get<std::string>()+" / "+item["speed"].get<std::string>()+
                (item["provider"].get<std::string>().empty()?"":" · "+item["provider"].get<std::string>());
            try {
              auto result = requestAi(store, snapshot, item,
                                      latencySample(chinese), cancel);
              std::string out = heading + "\r\n" +
                  std::to_string(
                      std::chrono::duration_cast<std::chrono::milliseconds>(
                          Clock::now() - begin)
                          .count()) +
                  " ms · ";
              for (auto& s : result["candidates"])
                out += s.get<std::string>() + " ";
              if (result.contains("usage"))
                out += "\r\n" + result["usage"].dump();
              return out;
            } catch (const Error& e) {
              if (e.code == "cancelled") throw;
              return heading + "\r\n" + errorText(e);
            } catch(const std::exception& e) {
              return heading + "\r\n" + errorText(e);
            }
          };
          if (kind == TEST_POLICY)
            done->output = test(p, true);
          else
            for (auto& id : selected) {
              cancel->check();
              for (auto& item : snapshot["policies"])
                if (item["id"] == id)
                  { done->output += test(item, false) + "\r\n\r\n";
                    auto partial=std::make_unique<Done>(*done); partial->partial=true;
                    if(PostMessageW(target,JOB_DONE,0,reinterpret_cast<LPARAM>(partial.get()))) partial.release(); }
            }
        }
      } catch (const std::exception& e) {
        done->error = errorText(e);
      }
      if (PostMessageW(target, JOB_DONE, 0,
                       reinterpret_cast<LPARAM>(done.get())))
        done.release();
    });
  }
  void done(std::unique_ptr<Done> d) {
    if (closing_) return;
    if(d->kind==SERVICE_RESTART) {EnableWindow(control(SERVICE_RESTART),TRUE);serviceState();status(d->error.empty()?u8"重启已发起 / Restart requested":d->error);return;}
    if(d->partial) { text(control(BENCH_RESULT),d->output); return; }
    if (d->kind >= DICT_REDEPLOY) {
      dictBusy_ = false;
      dictCancelable_ = true;
      dictionaryButtons();
      dictionaryState();
      if (!d->error.empty())
        text(control(DICT_STATUS), d->error);
      else
        text(control(DICT_STATUS), d->output);
      return;
    }
    apiButtons(false);
    if (!d->error.empty()) {
      status(d->error);
      if (d->kind == TEST_POLICY) text(control(TEST_RESULT), d->error);
      if (d->kind == BENCH_RUN) text(control(BENCH_RESULT), d->output + d->error);
      return;
    }
    if (d->kind == TEST_POLICY) {
      if (editing_ == d->policy) text(control(TEST_RESULT), d->output);
    } else if (d->kind == BENCH_RUN)
      text(control(BENCH_RESULT), d->output);
    else if (d->policy == editing_ &&
             d->endpoint == utf8(text(control(ENDPOINT)))) {
      loading_ = true;
      if (d->kind == MODELS_UPDATE) {
        activePolicy(config_)["modelList"] = d->data;
        auto current = utf8(text(control(MODEL)));
        std::vector<std::string> ids = {current};
        for (auto& id : d->data["ids"])
          if (id != current) ids.push_back(id);
        choices(control(MODEL), ids, current);
      } else if (d->model == utf8(text(control(MODEL)))) {
        auto current = utf8(text(control(PROVIDER)));
        std::vector<std::string> ids = {""};
        if (!current.empty()) ids.push_back(current);
        for (auto& v : d->data)
          if (v["id"] != current) ids.push_back(v["id"]);
        choices(control(PROVIDER), ids, current);
      }
      loading_ = false;
      refreshParameters(false);
      if (d->kind == MODELS_UPDATE) modified(REASONING);
    }
    if (d->kind == MODELS_UPDATE && d->policy == editing_ &&
        d->endpoint == utf8(text(control(ENDPOINT))))
      status(u8"模型与思考选项已刷新，请保存 / Models and reasoning refreshed; save changes");
    else if(dirty_) status(u8"列表已更新，请保存 / List updated; save changes");
    else status(u8"已完成 / Finished");
  }
  void dictionaryState() {
    loading_ = true;
    try {
      Dictionary d;
      auto s = d.state();
      choices(
          control(DICT_CHOICE), {u8"万象 / Wanxiang", u8"雾凇 / Rime Ice"},
          s["enabled"].get<bool>() ? u8"万象 / Wanxiang" : u8"雾凇 / Rime Ice");
      checkValue(GRAMMAR, s["grammar"]);
      text(control(DICT_STATUS), d.summary());
    } catch (const std::exception& e) {
      text(control(DICT_STATUS), errorText(e));
    }
    loading_ = false;
    dictionaryButtons();
  }
  void dictionaryButtons() {
    for (int id : {DICT_CHOICE, GRAMMAR, DICT_REDEPLOY, WANXIANG_UPDATE,
                   ICE_UPDATE, MODEL_UPDATE})
      EnableWindow(control(id), !dictBusy_);
    bool wanxiang = SendMessageW(control(DICT_CHOICE), CB_GETCURSEL, 0, 0) == 0;
    EnableWindow(control(GRAMMAR), !dictBusy_ && wanxiang);
    EnableWindow(control(MODEL_UPDATE), !dictBusy_ && wanxiang);
    EnableWindow(control(DICT_CANCEL), dictBusy_ && dictCancelable_);
  }
  void startDictionary(int kind) {
    if (dictBusy_ || loading_) return;
    dictBusy_ = true;
    dictCancelable_ = true;
    dictCancel_ = std::make_shared<Cancel>();
    auto cancel = dictCancel_;
    bool wanxiang = SendMessageW(control(DICT_CHOICE), CB_GETCURSEL, 0, 0) == 0,
         grammar = checked(GRAMMAR);
    dictionaryButtons();
    auto target = window_;
    workers_.emplace_back([target, kind, cancel, wanxiang, grammar] {
      auto done = std::make_unique<Done>();
      done->kind = kind;
      try {
        Dictionary d(
            rimeDirectory(), appDirectory(),
            [target](const Progress& p) {
              auto info = std::make_unique<Progress>(p);
              if (PostMessageW(target, DICT_REPORT, 0,
                               reinterpret_cast<LPARAM>(info.get())))
                info.release();
            },
            cancel);
        if (kind == DICT_REDEPLOY)
          d.select(wanxiang, grammar);
        else
          d.update(kind == WANXIANG_UPDATE ? "wanxiang"
                   : kind == ICE_UPDATE    ? "ice"
                                           : "model");
        done->output = d.summary();
      } catch (const std::exception& e) {
        done->error = errorText(e);
      }
      if (PostMessageW(target, JOB_DONE, 0,
                       reinterpret_cast<LPARAM>(done.get())))
        done.release();
    });
  }
  void command(int id, int notification) {
    if (loading_) return;
    if(id==SAVE) { save(false); return; }
    if(id==SERVICE_RESTART) {restartServices();return;}
    if (id == POLICIES && notification == LBN_SELCHANGE) {
      int i=int(SendMessageW(control(POLICIES),LB_GETCURSEL,0,0));
      if(i>=0 && size_t(i)<config_["policies"].size()) {
        auto selected=config_["policies"][i]["id"];
        if(capture(false)) {
          config_["selectedPolicy"]=selected;
          reload(); modified(POLICIES);
        } else reload(false);
      }
      return;
    }
    if(id==NEW_POLICY || id==COPY_POLICY || id==DELETE_POLICY) {
      if(!capture(false)) return;
      if(id==DELETE_POLICY) {
        if(config_["policies"].size()==1) return;
        if(MessageBoxW(window_,L"删除此方案？点击保存后生效。\nDelete this policy when saved?",
                       L"Zephyr Input",MB_YESNO|MB_ICONQUESTION)!=IDYES) return;
        auto& list=config_["policies"];
        list.erase(std::remove_if(list.begin(),list.end(),[&](const J& p){return p["id"]==editing_;}),list.end());
        auto key=pendingKeys_.find(editing_);
        if(key!=pendingKeys_.end()) { SecureZeroMemory(key->second.first.data(),key->second.first.size()); pendingKeys_.erase(key); }
        config_["selectedPolicy"]=list[0]["id"];
      } else {
        require(config_["policies"].size()<32,"At most 32 policies");
        auto p=id==COPY_POLICY?activePolicy(config_):defaultPolicy();
        std::string idNew=uniqueId();
        if(id==COPY_POLICY) {
          auto secret=pendingKeys_.count(editing_)?pendingKeys_.at(editing_).first:store_.key(editing_,p["endpoint"]);
          if(!secret.empty()) pendingKeys_[idNew]={secret,p["endpoint"]};
          SecureZeroMemory(secret.data(),secret.size());
          p["name"]=p["name"].get<std::string>()+u8" 副本";
        } else p["name"]=u8"新方案 / New policy";
        p["id"]=idNew; config_["policies"].push_back(p); config_["selectedPolicy"]=idNew;
      }
      reload(); modified(POLICIES); return;
    }
    if (id == MODELS_UPDATE || id == PROVIDERS_UPDATE || id == TEST_POLICY ||
        id == BENCH_RUN) {
      startApi(id);
      return;
    }
    if (id == BENCH_CANCEL) {
      if (apiCancel_) apiCancel_->cancelled = true;
      return;
    }
    if (id == DICT_CANCEL) {
      if (dictCancel_ && dictCancelable_) dictCancel_->cancelled = true;
      return;
    }
    if (id == DICT_SOURCE) {
      ShellExecuteW(window_, L"open",
                    L"https://github.com/amzxyz/rime-wanxiang", nullptr,
                    nullptr, SW_SHOWNORMAL);
      return;
    }
    if (id >= DICT_REDEPLOY && id <= MODEL_UPDATE) {
      if(dirty_) { status(u8"请先保存修改 / Save changes first"); return; }
      startDictionary(id);
      return;
    }
    if (id == GRAMMAR || (id == DICT_CHOICE && notification == CBN_SELCHANGE)) {
      dictionaryDirty_=true; modified(id); dictionaryButtons();
      return;
    }
    if (id == KEY) {
      if(notification==EN_CHANGE) modified(id);
      return;
    }
    if (id == MODEL || id == ENDPOINT) {
      if (notification == CBN_SELCHANGE || notification == CBN_EDITCHANGE ||
          notification == EN_CHANGE) {
        modified(id);
        SetTimer(window_, 2, 300, nullptr);
        return;
      }
    }
    if ((id >= AI_MODE && id <= BUDGET) || (id >= NAME && id <= SPEED) ||
        id == CHINESE_PROMPT || id == ENGLISH_PROMPT || id == AI_SHORTCUT) {
      if (notification == EN_CHANGE || notification == CBN_SELCHANGE ||
          notification == CBN_EDITCHANGE || notification == BN_CLICKED)
        modified(id);
    }
  }
  void smoke() {
    KillTimer(window_,9);
    try {
      auto original=store_.load();
      require(fs::absolute(store_.directory())!=fs::absolute(userDirectory()),"UI self-test requires an isolated data directory");
      for(auto& p:original["policies"]) require(!store_.hasKey(p["id"]),"UI self-test requires a directory without credentials");
      require(config_==original,"UI configuration mismatch");
      serviceState();
      require(IsWindow(control(SERVICE_RESTART)) && utf8(text(control(SERVICE_STATUS))).find(u8"AI 后台")!=std::string::npos,"Service indicator or restart button missing");
      require(SendMessageW(control(AI_MODE), CB_GETCOUNT, 0, 0) == 3, "AI modes missing");
      for (auto mode : {Correction, AssistantAndCorrection, NoAi}) {
        const auto previous = store_.load();
        SendMessageW(control(AI_MODE), CB_SETCURSEL, mode, 0);
        command(AI_MODE, CBN_SELCHANGE);
        require(dirty_ && store_.load() == previous, "AI mode saved before Save");
        require(save(false), "AI mode save failed");
        const auto saved = store_.load();
        require(saved["enabled"] == (mode != NoAi) &&
                saved["assistantEnabled"] == (mode == AssistantAndCorrection), "Wrong saved AI mode");
      }
      require(text(control(AI_SHORTCUT))==L"f8","Default AI shortcut missing");
      choices(control(AI_SHORTCUT),aiShortcutValues,"f9");modified(AI_SHORTCUT);
      require(save(false) && store_.load()["aiShortcut"]=="f9","AI shortcut not persisted");
      config_=saved_=original;store_.save(original);reload();dirty_=false;
      require(GetClassLongPtrW(window_,GCLP_HICON)!=0,"Window logo missing");
      SetWindowPos(window_,nullptr,0,0,px(1000),px(740),SWP_NOMOVE|SWP_NOZORDER);
      layout();
      for(int i=0;i<PAGE_COUNT;++i) {
        RECT r;GetClientRect(pages_[i].window,&r);
        require(px(pages_[i].content)<=r.bottom,"Default window requires page scrolling");
      }
      text(control(NAME),L"Manual save regression");
      modified(NAME);
      require(dirty_ && store_.load()==original,"Settings changed before Save");
      require(capture(false),"Capture failed");
      require(store_.load()==original,"Capture persisted settings");
      SendMessageW(control(POLICIES),LB_SETCURSEL,1,0);
      command(POLICIES,LBN_SELCHANGE);
      require(store_.load()==original,"Switch persisted a draft");
      text(control(KEY),L"ui-test-key-never-sent"); modified(KEY);
      command(COPY_POLICY,BN_CLICKED);
      auto copiedId=config_["selectedPolicy"].get<std::string>();
      require(config_["policies"].size()==original["policies"].size()+1 &&
              !store_.hasKey(copiedId) && store_.load()==original,"Copy or key persisted before Save");
      require(save(false) && store_.key(copiedId,activePolicy(config_)["endpoint"])=="ui-test-key-never-sent",
              "Copy key not saved explicitly");
      store_.eraseKey(copiedId); store_.eraseKey(original["policies"][1]["id"]);
      config_=saved_=original; store_.save(original); wipeKeys(); reload();
      text(control(NAME),L"Manual save regression"); modified(NAME);

      for(int i=0;i<3;++i) ListView_SetCheckState(control(BENCH_LIST),i,TRUE);
      require(benchmarkSelection().size()==3,"Checkbox multi-policy selection failed");
      ListView_SetCheckState(control(BENCH_LIST),1,FALSE);
      reload(false);
      require(benchmarkSelection().size()==2,"Checkbox selection not preserved");
      require(save(false),"Explicit save failed");
      require(activePolicy(store_.load())["name"]=="Manual save regression","Save did not persist");
      require(!dirty_ && flash_>0,"Save feedback missing");
      auto& policy = activePolicy(config_);
      policy["endpoint"] = "https://openrouter.ai/api/v1/chat/completions";
      policy["model"] = "fixture/model";
      reload();
      auto refresh = [&](const char* metadata) {
        auto result = std::make_unique<Done>();
        result->kind = MODELS_UPDATE;
        result->policy = editing_;
        result->endpoint = utf8(text(control(ENDPOINT)));
        result->data = {{"endpoint", result->endpoint}, {"ids", {"fixture/model"}},
          {"catalog", {{"version", "models-api"},
            {"models", core("modelsReasoning", J::parse(metadata))}}}};
        done(std::move(result));
      };
      refresh(R"({"data":[{"id":"fixture/model","reasoning":{"supported_efforts":["low","high"]}}]})");
      require(dirty_ && SendMessageW(control(REASONING), CB_GETCOUNT, 0, 0) == 3,
              "Model refresh did not update reasoning options");
      choices(control(REASONING), {"omit", "low", "high"}, "high");
      refresh(R"({"data":[{"id":"fixture/model","reasoning":{"supported_efforts":["low"]}}]})");
      require(text(control(REASONING)) == L"omit" &&
              SendMessageW(control(REASONING), CB_GETCOUNT, 0, 0) == 2,
              "Model refresh retained an unsupported reasoning choice");
      auto modelBefore=text(control(MODEL));
      SetWindowPos(window_,nullptr,0,0,px(800),px(580),SWP_NOMOVE|SWP_NOZORDER);
      layout();
      pages_[1].scroll=0;layoutPage(1);
      SendMessageW(control(MODEL),WM_MOUSEWHEEL,MAKEWPARAM(0,-WHEEL_DELTA),0);
      require(text(control(MODEL))==modelBefore && pages_[1].scroll>0,"Wheel model protection failed");
      text(control(DICT_STATUS),L"line 1\nline 2\r\nline 3");
      require(text(control(DICT_STATUS))==L"line 1\r\nline 2\r\nline 3","Multiline normalization failed");
      config_=saved_=original;store_.save(original);reload();dirty_=false;wipeKeys();
      atomicWrite(store_.directory()/L"ui-smoke.json",J{{"passed",true},{"tabs",PAGE_COUNT},
        {"manualSave",true},{"saveFeedback",true},{"checkboxSelection",true},{"defaultNoScroll",true},
        {"comboWheelSafe",true},{"multiline",true},{"logo",true},{"nativeControls",controls_.size()}}.dump(2));
    } catch(const std::exception& e) {
      dirty_=false;
      atomicWrite(store_.directory()/L"ui-smoke.json",J{{"passed",false},{"error",errorText(e)}}.dump(2));
    }
    PostMessageW(window_,WM_CLOSE,0,0);
  }
  void close() {
    if (dictBusy_) {
      if (dictCancelable_ && dictCancel_) dictCancel_->cancelled = true;
      status(
          u8"正在完成词库操作，请稍后关闭 / Please wait for dictionary "
          u8"operation");
      return;
    }
    if(dirty_) {
      int result=MessageBoxW(window_,L"保存修改后关闭？\nSave changes before closing?",L"Zephyr Input",MB_YESNOCANCEL|MB_ICONQUESTION);
      if(result==IDCANCEL) return;
      if(result==IDYES && !save(false)) return;
      if(dictBusy_) return;
    }
    closing_ = true;
    if (apiCancel_) apiCancel_->cancelled = true;
    if (dictCancel_) dictCancel_->cancelled = true;
    for (auto& worker : workers_)
      if (worker.joinable()) worker.join();
    MSG msg;
    while (PeekMessageW(&msg, window_, JOB_DONE, DICT_REPORT, PM_REMOVE)) {
      if (msg.message == JOB_DONE)
        delete reinterpret_cast<Done*>(msg.lParam);
      else if (msg.message == DICT_REPORT)
        delete reinterpret_cast<Progress*>(msg.lParam);
    }
    DestroyWindow(window_);
  }
  LRESULT message(UINT m, WPARAM w, LPARAM l) {
    switch (m) {
      case WM_CREATE:
        create();
        return 0;
      case WM_SIZE:
        if (controls_.count(STATUS)) layout();
        return 0;
      case WM_GETMINMAXINFO: {
        auto info = reinterpret_cast<MINMAXINFO*>(l);
        info->ptMinTrackSize = {px(800), px(580)};
        return 0;
      }
      case WM_DPICHANGED: {
        dpi_ = HIWORD(w);
        auto r = reinterpret_cast<RECT*>(l);
        fonts();
        SetWindowPos(window_, nullptr, r->left, r->top, r->right - r->left,
                     r->bottom - r->top, SWP_NOZORDER);
        SendMessageW(control(POLICIES), LB_SETITEMHEIGHT, 0, px(23));
        layout();
        return 0;
      }
      case WM_NOTIFY: {
        auto hdr = reinterpret_cast<NMHDR*>(l);
        if (hdr->idFrom == TABS && hdr->code == TCN_SELCHANGE) {
          tab_ = TabCtrl_GetCurSel(control(TABS));
          layout();
        }
        return 0;
      }
      case WM_COMMAND:
        command(LOWORD(w), HIWORD(w));
        return 0;
      case WM_TIMER:
        KillTimer(window_, w);
        if(w==10){serviceState();SetTimer(window_,10,2000,nullptr);return 0;}
        if (w == 4) {
          if(flash_>0) --flash_;
          if(flash_) SetTimer(window_,4,40,nullptr);
          else {
            for(int id:highlighted_) if(controls_.count(id)) InvalidateRect(control(id),nullptr,TRUE);
            highlighted_.clear(); if(!dirty_) text(control(SAVE),L"保存并生效 / Save");
          }
          InvalidateRect(control(STATUS),nullptr,TRUE);
          for(int id:highlighted_) if(controls_.count(id)) InvalidateRect(control(id),nullptr,TRUE);
        }
        if (w == 2) refreshParameters();
        if (w == 9) smoke();
        return 0;
      case WM_CTLCOLOREDIT:
      case WM_CTLCOLORSTATIC:
        if(auto brush=colorControl(w,l)) return reinterpret_cast<LRESULT>(brush);
        break;
      case WM_DRAWITEM: {
        auto d = reinterpret_cast<DRAWITEMSTRUCT*>(l);
        if (d->CtlID != POLICIES || d->itemID >= config_["policies"].size())
          break;
        auto& p = config_["policies"][d->itemID];
        bool selected = d->itemState & ODS_SELECTED;
        HBRUSH brush = CreateSolidBrush(
            GetSysColor(selected ? COLOR_HIGHLIGHT : COLOR_WINDOW));
        FillRect(d->hDC, &d->rcItem, brush);
        DeleteObject(brush);
        SetBkMode(d->hDC, TRANSPARENT);
        SetTextColor(d->hDC, GetSysColor(selected ? COLOR_HIGHLIGHTTEXT
                                                  : COLOR_WINDOWTEXT));
        auto old = SelectObject(d->hDC, smallFont_);
        RECT r = d->rcItem;
        r.left += px(6);
        auto s = wide(policyLabel(p));
        DrawTextW(d->hDC, s.c_str(), -1, &r,
                  DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS);
        SelectObject(d->hDC, old);
        if (d->itemState & ODS_FOCUS) DrawFocusRect(d->hDC, &d->rcItem);
        return TRUE;
      }
      case JOB_DONE:
        done(std::unique_ptr<Done>(reinterpret_cast<Done*>(l)));
        return 0;
      case DICT_REPORT: {
        std::unique_ptr<Progress> p(reinterpret_cast<Progress*>(l));
        dictCancelable_ = p->cancelable;
        dictionaryButtons();
        text(
            control(DICT_STATUS),
            p->message +
                (p->total ? "\r\n" + std::to_string(p->done / 1000000) + " / " +
                                std::to_string(p->total / 1000000) + " MB"
                          : ""));
        SendMessageW(control(DICT_PROGRESS), PBM_SETPOS,
                     p->total ? WPARAM(p->done * 100 / p->total) : 0, 0);
        return 0;
      }
      case FOCUS_ENTER:
        reveal(reinterpret_cast<HWND>(l));
        return 0;
      case WM_MOUSEWHEEL:
        scroll(tab_, m, w);
        return 0;
      case WM_CLOSE:
        close();
        return 0;
      case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(window_, m, w, l);
  }

 public:
  App(HINSTANCE instance, const Store& store, bool smoke)
      : instance_(instance),
        store_(store),
        config_(store.load()),
        saved_(config_),
        smoke_(smoke) {}
  ~App() {
    wipeKeys();
    if(flashBrush_) DeleteObject(flashBrush_);
    if (font_) DeleteObject(font_);
    if (smallFont_) DeleteObject(smallFont_);
  }
  int run() {
    WNDCLASSW wc{};
    wc.lpfnWndProc = proc;
    wc.hInstance = instance_;
    wc.lpszClassName = L"ZephyrNativeSettings";
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hIcon = LoadIconW(instance_, MAKEINTRESOURCEW(101));
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_BTNFACE + 1);
    RegisterClassW(&wc);
    wc.lpfnWndProc = pageProc;
    wc.lpszClassName = L"ZephyrNativePage";
    RegisterClassW(&wc);
    auto h = CreateWindowExW(WS_EX_CONTROLPARENT, L"ZephyrNativeSettings",
                             L"Zephyr Input · 微风输入法", WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
                             CW_USEDEFAULT, CW_USEDEFAULT, px(1000), px(740), nullptr,
                             nullptr, instance_, this);
    require(h != nullptr, "Cannot open settings window");
    RECT work{}; SystemParametersInfoW(SPI_GETWORKAREA,0,&work,0);
    int width=std::min(px(1000),int(work.right-work.left));
    int height=std::min(px(740),int(work.bottom-work.top));
    SetWindowPos(h,nullptr,work.left+(work.right-work.left-width)/2,
                 work.top+(work.bottom-work.top-height)/2,width,height,SWP_NOZORDER);
    SendMessageW(h,WM_SETICON,ICON_BIG,reinterpret_cast<LPARAM>(LoadIconW(instance_,MAKEINTRESOURCEW(101))));
    SendMessageW(h,WM_SETICON,ICON_SMALL,reinterpret_cast<LPARAM>(LoadImageW(instance_,MAKEINTRESOURCEW(101),IMAGE_ICON,
                  GetSystemMetrics(SM_CXSMICON),GetSystemMetrics(SM_CYSMICON),LR_DEFAULTCOLOR|LR_SHARED)));
    ShowWindow(h, SW_SHOW);
    UpdateWindow(h);
    MSG m;
    while (GetMessageW(&m, nullptr, 0, 0) > 0) {
      if (!IsDialogMessageW(h, &m)) {
        TranslateMessage(&m);
        DispatchMessageW(&m);
      }
    }
    return 0;
  }
};
}  // namespace
int settings(HINSTANCE instance, const Store& store, bool smoke) {
  INITCOMMONCONTROLSEX controls{sizeof(controls), ICC_TAB_CLASSES |
                                                      ICC_PROGRESS_CLASS |
                                                      ICC_STANDARD_CLASSES | ICC_LISTVIEW_CLASSES};
  InitCommonControlsEx(&controls);
  App app(instance, store, smoke);
  return app.run();
}
}  // namespace zw
