#include "stdafx.h"
#include "WeaselTSF.h"
#include "CandidateList.h"
#include "ResponseParser.h"
#include "ZephyrKeySettings.h"

STDMETHODIMP WeaselTSF::DoEditSession(TfEditCookie ec) {
  com_ptr<ITfDocumentMgr> focused;
  com_ptr<ITfContext> top;
  if (!_pThreadMgr || FAILED(_pThreadMgr->GetFocus(&focused)) || !focused ||
      FAILED(focused->GetTop(&top)) || top != _pEditSessionContext) {
    _zephyrRefreshPending = false;
    return S_OK;
  }
  // get commit string from server
  std::wstring commit;
  weasel::Config config;
  auto context = std::make_shared<weasel::Context>();
  weasel::ResponseParser parser(&commit, context.get(), &_status, &config,
                                &_cand->style());

  bool ok = m_client.GetResponseData(std::ref(parser));

  _UpdateLanguageBar(_status);

  bool compositionEnded = false;
  if (ok && _status.composing) {
    _pendingUIContext = context;
    _pendingUIStatus = _status;
    _hasPendingUI = true;
  }
  if (ok) {
    compositionEnded = false;
    if (!commit.empty()) {
      // For auto-selecting, commit and preedit can both exist.
      // Commit the old TSF composition. If Rime immediately has a new
      // preedit (top-word input), _EndComposition() drops the local pointer
      // synchronously, so the following state check starts a new TSF
      // composition instead of observing the old one.
      if (!_IsComposing()) {
        _StartComposition(_pEditSessionContext,
                          _fCUASWorkaroundEnabled && !config.inline_preedit);
      }
      _InsertText(_pEditSessionContext, commit);
      // Keep the candidate UI alive while the replacement composition is
      // being created; otherwise the key-down path destroys the old window
      // and the new one cannot be positioned until key-up.
      _EndComposition(_pEditSessionContext, false, !_status.composing);
      compositionEnded = true;
      _committed = TRUE;
    } else {
      _committed = FALSE;
    }
    if (_status.composing && (compositionEnded || !_IsComposing())) {
      _StartComposition(_pEditSessionContext,
                        _fCUASWorkaroundEnabled && !config.inline_preedit);
    } else if (!_status.composing && _IsComposing()) {
      _EndComposition(_pEditSessionContext, true);
    }
    if (_IsComposing() && config.inline_preedit) {
      _ShowInlinePreedit(_pEditSessionContext, context);
    }
  }

  // For a normal update, position the panel before publishing new candidates.
  // After a commit, the replacement composition's extent session flushes the
  // pending UI from _SetCompositionPosition().
  if (ok && _IsComposing() && !compositionEnded)
    _UpdateCompositionWindow(_pEditSessionContext);

  // Wait for the current composition's real text extent before painting new
  // candidates. This avoids one frame at the previous caret position.
  if (!(_status.composing && _IsComposing())) {
    _UpdateUI(*context, _status);
  }

  // Read under the existing TSF edit lock. Exclude the composition range, and
  // never ask the editor for surrounding text while cloud/context is disabled.
  try {
    auto prefs=zephyr::currentKeyPreferences().value_or(zephyr::KeyPreferences{});
    std::wstring before,after;
    if(prefs.aiEnabled && prefs.contextEnabled && !_IsKeyboardDisabled()) {
      com_ptr<ITfRange> anchor;
      if(_pComposition)_pComposition->GetRange(&anchor);
      if(!anchor) { TF_SELECTION selection{};ULONG fetched=0;
        if(SUCCEEDED(_pEditSessionContext->GetSelection(ec,TF_DEFAULT_SELECTION,1,&selection,&fetched))&&fetched&&selection.range){selection.range->Clone(&anchor);selection.range->Release();}
      }
      if(anchor) {
        auto read=[&](bool preceding,int count){std::wstring text;if(!count)return text;com_ptr<ITfRange> range;if(FAILED(anchor->Clone(&range)))return text;
          if(FAILED(range->Collapse(ec,preceding?TF_ANCHOR_START:TF_ANCHOR_END)))return text;LONG moved=0;
          HRESULT hr=preceding?range->ShiftStart(ec,-count*2,&moved,nullptr):range->ShiftEnd(ec,count*2,&moved,nullptr);
          if(FAILED(hr))return text;wchar_t buf[1001]{};ULONG actual=0;
          if(SUCCEEDED(range->GetText(ec,0,buf,1000,&actual)))text.assign(buf,actual);
          // A shifted UTF-16 boundary can split an emoji; omit the isolated half.
          if(!text.empty()&&text.front()>=0xdc00&&text.front()<=0xdfff)text.erase(text.begin());
          if(!text.empty()&&text.back()>=0xd800&&text.back()<=0xdbff)text.pop_back();return text;
        };
        before=read(true,prefs.beforeLength);after=read(false,prefs.afterLength);
      }
    }
    m_client.UpdateTextContext(before,after);
  } catch(...) { /* Context is optional. Never unwind through the host editor. */ }

  _zephyrRefreshPending=false;
  return TRUE;
}
