// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
// The status line of the OrangeCell candidate window, drawn as badges instead of text:
//   [中|EN] [简|繁] (✦ AI status)  hint  error
// The server writes it into ctx.aux as  U+E000 field U+E001 field ...  (see OrangeCellHandler.inc):
//   0 language "zh"/"en", 1 script "simp"/"trad", 2 AI phase "idle|waiting|streaming|done|failed",
//   3 AI label, 4 hint, 5 error.
// Any other aux text is drawn by Weasel as before. Vertical text layouts get a plain-text version.
#include <d2d1_1.h>
#include <dwrite_2.h>
#include <wrl/client.h>

#include <algorithm>
#include <cmath>
#include <string>
#include <vector>

#include "d2d.h"

namespace orangecell {

enum class AiPhase { Idle, Waiting, Streaming, Done, Failed };

struct StatusLine {
  bool valid = false;
  bool chinese = true;
  bool traditional = false;
  AiPhase phase = AiPhase::Idle;
  std::wstring label, hint, error;

  static StatusLine Parse(const std::wstring& aux) {
    StatusLine s;
    const size_t start = aux.find(wchar_t(0xE000));
    if (start == std::wstring::npos) return s;
    std::vector<std::wstring> f;
    size_t from = start + 1;
    for (;;) {
      size_t at = aux.find(wchar_t(0xE001), from);
      f.push_back(aux.substr(from, at == std::wstring::npos ? std::wstring::npos : at - from));
      if (at == std::wstring::npos) break;
      from = at + 1;
    }
    if (f.size() < 6) return s;
    s.valid = true;
    s.chinese = f[0] != L"en";
    s.traditional = f[1] == L"trad";
    s.phase = f[2] == L"waiting"     ? AiPhase::Waiting
              : f[2] == L"streaming" ? AiPhase::Streaming
              : f[2] == L"done"      ? AiPhase::Done
              : f[2] == L"failed"    ? AiPhase::Failed
                                     : AiPhase::Idle;
    s.label = f[3];
    s.hint = f[4];
    s.error = f[5];
    return s;
  }

  std::wstring Plain() const {
    std::wstring t = chinese ? (traditional ? L"繁" : L"简") : L"EN";
    t += L" · AI " + label;
    if (!hint.empty()) t += L" · " + hint;
    if (!error.empty()) t += L" · " + error;
    return t;
  }
};

inline bool IsStatusAux(const std::wstring& aux) {
  return aux.find(wchar_t(0xE000)) != std::wstring::npos;
}

// Text that is not drawn as badges must never show the private-use field markers.
inline std::wstring StripMarkers(std::wstring text) {
  for (auto& c : text)
    if (c == wchar_t(0xE000) || c == wchar_t(0xE001)) c = L' ';
  return text;
}

// Colours are 0xAABBGGRR, as everywhere in Weasel.
constexpr uint32_t kIndigo = 0xFFC65C56, kSlate = 0xFF665952, kAmber = 0xFF0079B8, kGreen = 0xFF487326,
                   kRed = 0xFF1E26B3, kMuted = 0xFF988F8A, kWhite = 0xFFFFFFFF;

inline uint32_t WithAlpha(uint32_t c, uint8_t a) { return (c & 0x00FFFFFF) | (uint32_t(a) << 24); }

struct StatusMetrics {
  float h = 0, gap = 0, chip = 0, pillPad = 0, icon = 0, labelW = 0, hintW = 0, errorW = 0;
  float width() const {
    float w = chip * 2 + gap * 2 + pillPad * 2 + icon + gap * 0.5f + labelW;
    if (hintW > 0) w += gap + hintW;
    if (errorW > 0) w += gap + errorW;
    return w;
  }
};

inline StatusMetrics Measure(weasel::D2D& d2d, const StatusLine& s, weasel::PtTextFormat& format) {
  StatusMetrics m;
  SIZE sz{};
  d2d.GetTextSize(L"中", 1, format, &sz);
  m.h = float(std::max<LONG>(sz.cy, 12));
  m.gap = std::round(m.h * 0.3f);
  m.chip = m.h;
  m.pillPad = std::round(m.h * 0.35f);
  m.icon = m.h * 0.86f;
  d2d.GetTextSize(s.label, s.label.size(), format, &sz);
  m.labelW = float(sz.cx);
  if (!s.hint.empty()) { d2d.GetTextSize(s.hint, s.hint.size(), format, &sz); m.hintW = float(sz.cx) * 0.86f; }
  if (!s.error.empty()) { d2d.GetTextSize(s.error, s.error.size(), format, &sz); m.errorW = float(sz.cx) * 0.86f; }
  return m;
}

inline SIZE MeasureSize(weasel::D2D& d2d, const StatusLine& s, weasel::PtTextFormat& format) {
  auto m = Measure(d2d, s, format);
  return SIZE{LONG(std::ceil(m.width())), LONG(std::ceil(m.h))};
}

/** What the panel remembers between frames to animate changes. */
struct StatusAnimation {
  ULONGLONG start = GetTickCount64();
  AiPhase phase = AiPhase::Idle;
  ULONGLONG phaseAt = 0;
  bool traditional = false, previousTraditional = false, known = false;
  ULONGLONG scriptAt = 0;

  void Observe(const StatusLine& s) {
    const auto now = GetTickCount64();
    if (!known) { known = true; phase = s.phase; traditional = previousTraditional = s.traditional; return; }
    if (s.phase != phase) { phase = s.phase; phaseAt = now; }
    if (s.traditional != traditional) { previousTraditional = traditional; traditional = s.traditional; scriptAt = now; }
  }
  /** True while something on the line is still moving. */
  bool Running() const {
    const auto now = GetTickCount64();
    return phase == AiPhase::Waiting || phase == AiPhase::Streaming ||
           (phase == AiPhase::Done && now - phaseAt < 1900) || (now - scriptAt < 420);
  }
};

namespace detail {
using Microsoft::WRL::ComPtr;

inline void DrawLabel(weasel::D2D& d2d, const std::wstring& text, weasel::PtTextFormat& format, float x, float y,
                 float w, float h, uint32_t color, float scale = 1.0f, bool bold = false, bool center = false) {
  if (text.empty() || !format) return;
  ComPtr<IDWriteTextLayout> layout;
  if (FAILED(d2d.m_pWriteFactory->CreateTextLayout(text.c_str(), UINT32(text.size()), format.Get(), w, h,
                                                    layout.GetAddressOf())) || !layout)
    return;
  DWRITE_TEXT_RANGE all{0, UINT32(text.size())};
  layout->SetReadingDirection(DWRITE_READING_DIRECTION_LEFT_TO_RIGHT);
  layout->SetFlowDirection(DWRITE_FLOW_DIRECTION_TOP_TO_BOTTOM);
  layout->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
  if (scale != 1.0f) layout->SetFontSize(format->GetFontSize() * scale, all);
  if (bold) layout->SetFontWeight(DWRITE_FONT_WEIGHT_SEMI_BOLD, all);
  layout->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
  if (center) layout->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER);
  d2d.DrawTextLayout(layout, x, y, color);
}

inline ComPtr<ID2D1PathGeometry> Polygons(weasel::D2D& d2d, const std::vector<std::vector<D2D1_POINT_2F>>& shapes,
                                          bool closed = true) {
  ComPtr<ID2D1PathGeometry> path;
  if (FAILED(d2d.d2Factory->CreatePathGeometry(path.GetAddressOf()))) return nullptr;
  ComPtr<ID2D1GeometrySink> sink;
  if (FAILED(path->Open(sink.GetAddressOf()))) return nullptr;
  for (auto& pts : shapes) {
    if (pts.empty()) continue;
    sink->BeginFigure(pts[0], closed ? D2D1_FIGURE_BEGIN_FILLED : D2D1_FIGURE_BEGIN_HOLLOW);
    for (size_t i = 1; i < pts.size(); ++i) sink->AddLine(pts[i]);
    sink->EndFigure(closed ? D2D1_FIGURE_END_CLOSED : D2D1_FIGURE_END_OPEN);
  }
  sink->Close();
  return path;
}

// The AI sparkle from the Android key, on a 24-unit grid, mapped into the box (x, y, size).
inline void Sparkle(weasel::D2D& d2d, float x, float y, float size, float shrink, uint32_t color) {
  static const float big[] = {10, 2.5f, 12.25f, 8.75f, 18.5f, 11, 12.25f, 13.25f, 10, 19.5f, 7.75f, 13.25f, 1.5f, 11, 7.75f, 8.75f};
  static const float a[] = {19.5f, 2, 20.4f, 4.6f, 23, 5.5f, 20.4f, 6.4f, 19.5f, 9, 18.6f, 6.4f, 16, 5.5f, 18.6f, 4.6f};
  static const float b[] = {19, 15, 20, 18, 23, 19, 20, 20, 19, 23, 18, 20, 15, 19, 18, 18};
  const float k = size / 24.0f * shrink, ox = x + size * (1 - shrink) / 2, oy = y + size * (1 - shrink) / 2;
  auto shape = [&](const float* p) {
    std::vector<D2D1_POINT_2F> v;
    for (int i = 0; i < 16; i += 2) v.push_back({ox + p[i] * k, oy + p[i + 1] * k});
    return v;
  };
  auto path = Polygons(d2d, {shape(big), shape(a), shape(b)});
  if (!path) return;
  d2d.SetBrushColor(color);
  d2d.dc->FillGeometry(path.Get(), d2d.m_pBrush.Get());
}

inline void Arc(weasel::D2D& d2d, float cx, float cy, float r, float startDeg, float sweepDeg, float width,
                uint32_t color) {
  std::vector<D2D1_POINT_2F> pts;
  const int n = (std::max)(8, int(sweepDeg / 8));
  for (int i = 0; i <= n; ++i) {
    float t = (startDeg + sweepDeg * i / n) * 3.14159265f / 180.0f;
    pts.push_back({cx + r * std::cos(t), cy + r * std::sin(t)});
  }
  auto path = Polygons(d2d, {pts}, false);
  if (!path) return;
  ComPtr<ID2D1StrokeStyle> round;
  d2d.d2Factory->CreateStrokeStyle(D2D1::StrokeStyleProperties(D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND,
                                                               D2D1_CAP_STYLE_ROUND, D2D1_LINE_JOIN_ROUND),
                                   nullptr, 0, round.GetAddressOf());
  d2d.SetBrushColor(color);
  d2d.dc->DrawGeometry(path.Get(), d2d.m_pBrush.Get(), width, round.Get());
}

inline float Overshoot(float t) {  // 0..1 with a small bounce, like Android's OvershootInterpolator
  const float k = 2.2f;
  t -= 1;
  return t * t * ((k + 1) * t + k) + 1;
}
}  // namespace detail

/** Draws the badges inside rc. [anim] supplies the timing of the last changes. */
inline void Draw(weasel::D2D& d2d, const StatusLine& s, const RECT& rc, weasel::PtTextFormat& format,
                 const StatusAnimation& anim) {
  using namespace detail;
  if (!d2d.dc || !d2d.m_pBrush || !d2d.d2Factory || !d2d.m_pWriteFactory) return;
  const auto m = Measure(d2d, s, format);
  // Lighter accents on a dark candidate window (color_scheme_dark).
  const uint32_t back = d2d.m_style.back_color;
  const float luminance = 0.299f * (back & 0xFF) + 0.587f * ((back >> 8) & 0xFF) + 0.114f * ((back >> 16) & 0xFF);
  const bool dark = luminance < 110;
  const uint32_t indigo = dark ? 0xFFE0807B : kIndigo, slate = dark ? 0xFFD9D2CC : kSlate,
                 muted = dark ? 0xFFA8A09A : kMuted;
  const ULONGLONG now = GetTickCount64();
  const float seconds = float(now - anim.start) / 1000.0f;
  float x = float(rc.left);
  const float y = float(rc.top) + (std::max)(0.0f, (float(rc.bottom - rc.top) - m.h) / 2);
  const float h = m.h, r = std::round(h * 0.28f), stroke = (std::max)(1.0f, h / 16);
  auto rounded = [&](float l, float t, float w, float hh, float rad) {
    return D2D1::RoundedRect(D2D1::RectF(l, t, l + w, t + hh), rad, rad);
  };

  // Language: 中 filled, EN outlined.
  if (s.chinese) {
    d2d.SetBrushColor(indigo);
    d2d.dc->FillRoundedRectangle(rounded(x, y, m.chip, h, r), d2d.m_pBrush.Get());
    DrawLabel(d2d, L"中", format, x, y, m.chip, h, kWhite, 0.72f, true, true);
  } else {
    d2d.SetBrushColor(slate);
    d2d.dc->DrawRoundedRectangle(rounded(x + stroke / 2, y + stroke / 2, m.chip - stroke, h - stroke, r),
                                 d2d.m_pBrush.Get(), stroke);
    DrawLabel(d2d, L"EN", format, x, y, m.chip, h, slate, 0.5f, true, true);
  }
  x += m.chip + m.gap;

  // Script: a card that turns over when 简 and 繁 switch.
  {
    float p = anim.scriptAt ? (std::min)(1.0f, float(now - anim.scriptAt) / 380.0f) : 1.0f;
    float eased = p < 0.5f ? 2 * p * p : 1 - std::pow(-2 * p + 2, 2.0f) / 2;
    float sx = (std::max)(0.04f, std::fabs(std::cos(3.14159265f * eased)));
    bool trad = eased < 0.5f ? anim.previousTraditional : s.traditional;
    if (!anim.scriptAt) trad = s.traditional;
    D2D1_MATRIX_3X2_F old;
    d2d.dc->GetTransform(&old);
    d2d.dc->SetTransform(D2D1::Matrix3x2F::Scale(sx, 1, D2D1::Point2F(x + m.chip / 2, y + h / 2)) * old);
    if (trad) {
      d2d.SetBrushColor(indigo);
      d2d.dc->FillRoundedRectangle(rounded(x, y, m.chip, h, r), d2d.m_pBrush.Get());
      DrawLabel(d2d, L"繁", format, x, y, m.chip, h, kWhite, 0.72f, true, true);
    } else {
      d2d.SetBrushColor(indigo);
      d2d.dc->DrawRoundedRectangle(rounded(x + stroke / 2, y + stroke / 2, m.chip - stroke, h - stroke, r),
                                   d2d.m_pBrush.Get(), stroke);
      DrawLabel(d2d, L"简", format, x, y, m.chip, h, indigo, 0.72f, true, true);
    }
    d2d.dc->SetTransform(old);
  }
  x += m.chip + m.gap;

  // AI pill: sparkle with a spinning ring while it waits, a check when done, a badge on failure.
  const uint32_t tone = s.phase == AiPhase::Waiting  ? kAmber
                        : s.phase == AiPhase::Done   ? kGreen
                        : s.phase == AiPhase::Failed ? kRed
                                                     : indigo;
  const float pillW = m.pillPad * 2 + m.icon + m.gap * 0.5f + m.labelW;
  d2d.SetBrushColor(WithAlpha(tone, 0x22));
  d2d.dc->FillRoundedRectangle(rounded(x, y, pillW, h, h / 2), d2d.m_pBrush.Get());
  const float ix = x + m.pillPad, iy = y + (h - m.icon) / 2, cx = ix + m.icon / 2, cy = iy + m.icon / 2;
  const bool spinning = s.phase == AiPhase::Waiting || s.phase == AiPhase::Streaming;
  if (spinning) {
    const float period = s.phase == AiPhase::Waiting ? 1.1f : 0.7f;
    const float spin = std::fmod(seconds / period, 1.0f);
    const float pulse = 0.5f + 0.5f * std::sin(2 * 3.14159265f * spin);
    Arc(d2d, cx, cy, m.icon / 2 - stroke, 0, 360, stroke * 1.1f, WithAlpha(tone, 0x40));
    Arc(d2d, cx, cy, m.icon / 2 - stroke, spin * 360 - 90, s.phase == AiPhase::Waiting ? 110.0f : 250.0f,
        stroke * 1.3f, tone);
    Sparkle(d2d, ix, iy, m.icon, 0.6f, WithAlpha(tone, uint8_t(140 + 115 * pulse)));
  } else if (s.phase == AiPhase::Done && now - anim.phaseAt < 1900) {
    const float t = float(now - anim.phaseAt) / 1000.0f;
    const float grow = Overshoot((std::min)(1.0f, t / 0.36f));
    const float fade = t < 1.6f ? 1.0f : (std::max)(0.0f, 1 - (t - 1.6f) / 0.28f);
    d2d.SetBrushColor(WithAlpha(kGreen, uint8_t(255 * fade)));
    d2d.dc->FillEllipse(D2D1::Ellipse(D2D1::Point2F(cx, cy), m.icon / 2 * grow, m.icon / 2 * grow),
                        d2d.m_pBrush.Get());
    if (t > 0.12f) {
      const float k = m.icon / 24.0f;
      auto check = Polygons(d2d, {{{ix + 7.2f * k, iy + 12.4f * k}, {ix + 10.6f * k, iy + 15.8f * k},
                                   {ix + 16.8f * k, iy + 8.6f * k}}}, false);
      if (check) {
        d2d.SetBrushColor(WithAlpha(kWhite, uint8_t(255 * fade)));
        d2d.dc->DrawGeometry(check.Get(), d2d.m_pBrush.Get(), stroke * 1.4f);
      }
    }
    if (fade < 1.0f) Sparkle(d2d, ix, iy, m.icon, 1.0f, WithAlpha(indigo, uint8_t(255 * (1 - fade))));
  } else {
    Sparkle(d2d, ix, iy, m.icon, 1.0f, s.phase == AiPhase::Failed ? kRed : indigo);
    if (s.phase == AiPhase::Failed) {
      const float br = m.icon * 0.22f, bx = ix + m.icon - br, by = iy + m.icon - br;
      d2d.SetBrushColor(kWhite);
      d2d.dc->FillEllipse(D2D1::Ellipse(D2D1::Point2F(bx, by), br + stroke, br + stroke), d2d.m_pBrush.Get());
      d2d.SetBrushColor(kRed);
      d2d.dc->FillEllipse(D2D1::Ellipse(D2D1::Point2F(bx, by), br, br), d2d.m_pBrush.Get());
    }
  }
  const uint32_t labelColor = s.phase == AiPhase::Idle ? slate : tone;
  DrawLabel(d2d, s.label, format, ix + m.icon + m.gap * 0.5f, y, m.labelW + 2, h, labelColor);
  x += pillW;

  if (m.hintW > 0) {
    x += m.gap;
    DrawLabel(d2d, s.hint, format, x, y, m.hintW + 2, h, muted, 0.86f);
    x += m.hintW;
  }
  if (m.errorW > 0) {
    x += m.gap;
    DrawLabel(d2d, s.error, format, x, y, m.errorW + 2, h, kRed, 0.86f);
  }
}

}  // namespace orangecell
