#include <cstdio>
#include "stdafx.h"
#include "WeaselIPC.h"
#include "WeaselTSF.h"
#include <KeyEvent.h>
#include "CandidateList.h"
#include "ZephyrKeySettings.h"
#include "ZephyrShortcuts.h"

static weasel::KeyEvent prevKeyEvent;
static GUID ZephyrShiftSpaceGuid() { GUID g=GUID_IME_MODE_PRESERVED_KEY;g.Data1+=1;return g; }
static BOOL prevfEaten = FALSE;
static int keyCountToSimulate = 0;

// ALT chords may be consumed as host system-key messages before ordinary
// OnKeyDown. Register their TSF command path as well. Each slot has its own ID.
static GUID ZephyrCandidateKeyGuid(UINT slot) {
  GUID value = {0x7f26d4b0, 0x317c, 0x47ed,
                {0xb9, 0x56, 0x18, 0xcf, 0x44, 0x90, 0xac, 0x10}};
  value.Data1 += slot;
  return value;
}

void WeaselTSF::_CheckInputContext(ITfContext* context) {
  // Some hosts change their TSF context without changing document managers.
  if (_pEditSessionContext && context != _pEditSessionContext)
    _ClearForContextChange();
}

bool WeaselTSF::_ShouldDeferCandidateKey(weasel::KeyEvent key) {
  if (!_zephyrAiRefreshPending || !_status.composing) return false;
  const auto prefs = zephyr::currentKeyPreferences();
  return zephyr::candidateListKey(key.keycode, key.mask, prefs && prefs->enterOriginal,
                                  prefs && (prefs->spaceOriginal || prefs->wordSegmentation));
}

void WeaselTSF::_ProcessKeyEvent(WPARAM wParam, LPARAM lParam, BOOL* pfEaten) {
  // when _IsKeyboardDisabled don't eat the key,
  // when keyboard closable and keyboard closed, don't eat the key
  if ((_isToOpenClose && !_IsKeyboardOpen()) || _IsKeyboardDisabled()) {
    if(_status.composing)_AbortComposition(true);
    *pfEaten = FALSE;
    return;
  }

  weasel::KeyEvent ke;
  GetKeyboardState(_lpbKeyState);
  const bool converted = ConvertKeyEvent(static_cast<UINT>(wParam), lParam, _lpbKeyState, ke);
  // An echo writes into the response buffer too. Keep the AI snapshot intact
  // when this key will not be sent to the server.
  if (_zephyrAiRefreshPending && (!converted || _ShouldDeferCandidateKey(ke))) {
    *pfEaten = converted;
    return;
  }

  // if server connection is Not OK, don't eat it.
  if (!_EnsureServerConnected()) {
    if(_status.composing)_AbortComposition(true);
    *pfEaten = FALSE;
    return;
  }
  if (!converted) {
    /* Unknown key event */
    *pfEaten = FALSE;
  } else {
    // cheet key code when vertical auto reverse happened, swap up and down
    if (_cand->GetIsReposition()) {
      if (ke.keycode == ibus::Up)
        ke.keycode = ibus::Down;
      else if (ke.keycode == ibus::Down)
        ke.keycode = ibus::Up;
    }
    const bool aiShortcut = (ke.keycode == ibus::F8 || ke.keycode == ibus::F9 || ke.keycode == ibus::F10) &&
        zephyr::shortcutChord(zephyr::currentKeyPreferences().value_or(zephyr::KeyPreferences{}).aiShortcut,
                              ke.keycode, ke.mask);
    if (_status.composing && (lParam & (1LL << 30)) && aiShortcut)
      *pfEaten = TRUE;  // Holding the shortcut must not flood the AI service.
    else if (!keyCountToSimulate) {
      *pfEaten = (BOOL)m_client.ProcessKeyEvent(ke);
      // Retrying can remove the existing AI prefix before the replacement arrives.
      if (*pfEaten && aiShortcut) _zephyrAiRefreshPending = true;
      if (_zephyrAiRefreshPending) _zephyrAiSnapshotRead = false;
    }

    if (ke.keycode == ibus::Caps_Lock) {
      if (prevKeyEvent.keycode == ibus::Caps_Lock && prevfEaten == TRUE &&
          (ke.mask & ibus::RELEASE_MASK) && (!keyCountToSimulate)) {
        if ((GetKeyState(VK_CAPITAL) & 0x01)) {
          if (_committed || (!*pfEaten && _status.composing)) {
            keyCountToSimulate = 2;
            INPUT inputs[2];
            inputs[0].type = INPUT_KEYBOARD;
            inputs[0].ki = {VK_CAPITAL, 0, 0, 0, 0};
            inputs[1].type = INPUT_KEYBOARD;
            inputs[1].ki = {VK_CAPITAL, 0, KEYEVENTF_KEYUP, 0, 0};
            ::SendInput(sizeof(inputs) / sizeof(INPUT), inputs, sizeof(INPUT));
          }
        }
        *pfEaten = TRUE;
      }
      if (keyCountToSimulate)
        keyCountToSimulate--;
    }

    prevfEaten = *pfEaten;
    prevKeyEvent = ke;
  }
}

STDMETHODIMP WeaselTSF::OnSetFocus(BOOL fForeground) {
  if (fForeground)
    m_client.FocusIn();
  else {
    m_client.FocusOut();
    _AbortComposition();
  }

  return S_OK;
}

/* Some apps sends strange OnTestKeyDown/OnKeyDown combinations:
 *  Some sends OnKeyDown() only. (QQ2012)
 *  Some sends multiple OnTestKeyDown() for a single key event. (MS WORD 2010
 * x64)
 *
 * We assume every key event will eventually cause a OnKeyDown() call.
 * We use _fTestKeyDownPending to omit multiple OnTestKeyDown() calls,
 *  and for OnKeyDown() to check if the key has already been sent to the server.
 */

STDMETHODIMP WeaselTSF::OnTestKeyDown(ITfContext* pContext,
                                      WPARAM wParam,
                                      LPARAM lParam,
                                      BOOL* pfEaten) {
  _CheckInputContext(pContext);
  _fTestKeyUpPending = FALSE;
  if (_fTestKeyDownPending) {
    *pfEaten = TRUE;
    return S_OK;
  }
  _ProcessKeyEvent(wParam, lParam, pfEaten);
  _UpdateComposition(pContext);
  if (*pfEaten)
    _fTestKeyDownPending = TRUE;
  return S_OK;
}

STDMETHODIMP WeaselTSF::OnKeyDown(ITfContext* pContext,
                                  WPARAM wParam,
                                  LPARAM lParam,
                                  BOOL* pfEaten) {
  _CheckInputContext(pContext);
  _fTestKeyUpPending = FALSE;
  if (_fTestKeyDownPending) {
    _fTestKeyDownPending = FALSE;
    *pfEaten = TRUE;
  } else {
    _ProcessKeyEvent(wParam, lParam, pfEaten);
    _UpdateComposition(pContext);
  }
  return S_OK;
}

STDMETHODIMP WeaselTSF::OnTestKeyUp(ITfContext* pContext,
                                    WPARAM wParam,
                                    LPARAM lParam,
                                    BOOL* pfEaten) {
  _CheckInputContext(pContext);
  _fTestKeyDownPending = FALSE;
  if (_fTestKeyUpPending) {
    *pfEaten = TRUE;
    return S_OK;
  }
  _ProcessKeyEvent(wParam, lParam, pfEaten);
  _UpdateComposition(pContext);
  if (*pfEaten)
    _fTestKeyUpPending = TRUE;
  return S_OK;
}

STDMETHODIMP WeaselTSF::OnKeyUp(ITfContext* pContext,
                                WPARAM wParam,
                                LPARAM lParam,
                                BOOL* pfEaten) {
  _CheckInputContext(pContext);
  _fTestKeyDownPending = FALSE;
  if (_fTestKeyUpPending) {
    _fTestKeyUpPending = FALSE;
    *pfEaten = TRUE;
  } else {
    _ProcessKeyEvent(wParam, lParam, pfEaten);
    if (!_async_edit)
      _UpdateComposition(pContext);
  }
  return S_OK;
}

STDMETHODIMP WeaselTSF::OnPreservedKey(ITfContext* pContext,
                                       REFGUID rguid,
                                       BOOL* pfEaten) {
  _CheckInputContext(pContext);
  *pfEaten = FALSE;
  for (UINT slot = 0; slot < 5; ++slot) {
    if (IsEqualGUID(rguid, ZephyrCandidateKeyGuid(slot))) {
      if (_status.composing && !_IsKeyboardDisabled()) {
        const weasel::KeyEvent key('1' + slot, ibus::ALT_MASK);
        if (_ShouldDeferCandidateKey(key)) {
          *pfEaten = TRUE;
          _UpdateComposition(pContext);
        } else if (_EnsureServerConnected()) {
          *pfEaten = m_client.ProcessKeyEvent(key);
          _UpdateComposition(pContext);
        }
      }
      return S_OK;
    }
  }
  if ((IsEqualGUID(rguid, GUID_IME_MODE_PRESERVED_KEY)||IsEqualGUID(rguid,ZephyrShiftSpaceGuid())) && !_IsKeyboardDisabled() && _EnsureServerConnected()) {
    int mask=ibus::CONTROL_MASK|(IsEqualGUID(rguid,ZephyrShiftSpaceGuid())?ibus::SHIFT_MASK:0);
    auto prefs=zephyr::currentKeyPreferences().value_or(zephyr::KeyPreferences{});
    if(!zephyr::shortcutChord(prefs.languageShortcut,' ',mask))return S_OK;
    *pfEaten = m_client.ProcessKeyEvent(weasel::KeyEvent(' ', mask));
    _UpdateComposition(pContext);
  }
  return S_OK;
}

BOOL WeaselTSF::_InitKeyEventSink() {
  com_ptr<ITfKeystrokeMgr> pKeystrokeMgr;
  HRESULT hr;

  if (_pThreadMgr->QueryInterface(&pKeystrokeMgr) != S_OK)
    return FALSE;

  hr = pKeystrokeMgr->AdviseKeyEventSink(_tfClientId, (ITfKeyEventSink*)this,
                                         TRUE);

  if (FAILED(hr)) std::fprintf(stderr, "AdviseKeyEventSink: 0x%08lx, client=%lu\n", hr, _tfClientId);
  return (hr == S_OK);
}

void WeaselTSF::_UninitKeyEventSink() {
  com_ptr<ITfKeystrokeMgr> pKeystrokeMgr;

  if (_pThreadMgr->QueryInterface(&pKeystrokeMgr) != S_OK)
    return;

  pKeystrokeMgr->UnadviseKeyEventSink(_tfClientId);
}

BOOL WeaselTSF::_InitPreservedKey() {
  com_ptr<ITfKeystrokeMgr> manager;
  if (FAILED(_pThreadMgr->QueryInterface(&manager))) return FALSE;
  TF_PRESERVEDKEY key{VK_SPACE, TF_MOD_CONTROL};
  HRESULT language = manager->PreserveKey(_tfClientId, GUID_IME_MODE_PRESERVED_KEY,
                                          &key, L"Zephyr language", 15);
  TF_PRESERVEDKEY shiftSpace{VK_SPACE, TF_MOD_CONTROL|TF_MOD_SHIFT};
  manager->PreserveKey(_tfClientId,ZephyrShiftSpaceGuid(),&shiftSpace,L"Zephyr language",15);
  for (UINT slot = 0; slot < 5; ++slot) {
    TF_PRESERVEDKEY candidate{'1' + slot, TF_MOD_ALT};
    manager->PreserveKey(_tfClientId, ZephyrCandidateKeyGuid(slot),
                        &candidate, L"Zephyr candidate", 16);
  }
  return SUCCEEDED(language);
}

void WeaselTSF::_UninitPreservedKey() {
  com_ptr<ITfKeystrokeMgr> manager;
  if (_pThreadMgr && SUCCEEDED(_pThreadMgr->QueryInterface(&manager))) {
    TF_PRESERVEDKEY key{VK_SPACE, TF_MOD_CONTROL};
    manager->UnpreserveKey(GUID_IME_MODE_PRESERVED_KEY, &key);
    TF_PRESERVEDKEY shiftSpace{VK_SPACE,TF_MOD_CONTROL|TF_MOD_SHIFT};
    manager->UnpreserveKey(ZephyrShiftSpaceGuid(),&shiftSpace);
    for (UINT slot = 0; slot < 5; ++slot) {
      TF_PRESERVEDKEY candidate{'1' + slot, TF_MOD_ALT};
      manager->UnpreserveKey(ZephyrCandidateKeyGuid(slot), &candidate);
    }
  }
}
