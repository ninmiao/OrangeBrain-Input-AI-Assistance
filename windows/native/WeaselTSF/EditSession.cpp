#include "stdafx.h"
#include "WeaselTSF.h"
#include "CandidateList.h"
#include "ResponseParser.h"
#include "OrangeCellKeySettings.h"

bool WeaselTSF::_HasFocusedEditContext(ITfContext* context) {
  com_ptr<ITfDocumentMgr> focused;
  com_ptr<ITfContext> top;
  return context && _pThreadMgr &&
         SUCCEEDED(_pThreadMgr->GetFocus(&focused)) && focused &&
         SUCCEEDED(focused->GetTop(&top)) && top == context;
}

HRESULT WeaselTSF::_DoCompositionEditSession(TfEditCookie ec, ITfContext* editor,
                                             uint64_t epoch, uint64_t serial) {
  if (epoch != _compositionRefreshEpoch || editor != _pEditSessionContext)
    return S_OK;
  const bool focused = _HasFocusedEditContext(editor);
  if (epoch != _compositionRefreshEpoch || editor != _pEditSessionContext)
    return S_OK;
  if (!focused) {
    if (serial == _compositionRefreshSerial) {
      _orangecellRefreshPending = false;
      _orangecellAiRefreshPending = false;
      _orangecellAiSnapshotRead = false;
    }
    return S_OK;
  }
  // get commit string from server
  std::wstring commit;
  weasel::Config config;
  auto context = std::make_shared<weasel::Context>();
  weasel::ResponseParser parser(&commit, context.get(), &_status, &config,
                                &_cand->style());

  bool ok = m_client.GetResponseData(std::ref(parser));
  if (ok && _orangecellAiRefreshPending) _orangecellAiSnapshotRead = true;

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
        _StartComposition(editor,
                          _fCUASWorkaroundEnabled && !config.inline_preedit);
      }
      _InsertText(editor, commit);
      // Keep the candidate UI alive while the replacement composition is
      // being created; otherwise the key-down path destroys the old window
      // and the new one cannot be positioned until key-up.
      _EndComposition(editor, false, !_status.composing);
      compositionEnded = true;
      _committed = TRUE;
    } else {
      _committed = FALSE;
    }
    if (_status.composing && (compositionEnded || !_IsComposing())) {
      _StartComposition(editor,
                        _fCUASWorkaroundEnabled && !config.inline_preedit);
    } else if (!_status.composing && _IsComposing()) {
      _EndComposition(editor, true);
    }
    if (_IsComposing() && config.inline_preedit) {
      _ShowInlinePreedit(editor, context);
    }
  }

  // For a normal update, position the panel before publishing new candidates.
  // After a commit, the replacement composition's extent session flushes the
  // pending UI from _SetCompositionPosition().
  if (ok && _IsComposing() && !compositionEnded)
    _UpdateCompositionWindow(editor);

  // Wait for the current composition's real text extent before painting new
  // candidates. This avoids one frame at the previous caret position.
  if (!(_status.composing && _IsComposing())) {
    _UpdateUI(*context, _status);
  }

  // Cache the current composition's context locally so a manual AI shortcut
  // can use it immediately. The broker only sends it with an AI request.
  try {
    auto prefs=orangecell::currentKeyPreferences().value_or(orangecell::KeyPreferences{});
    std::wstring before,after;
    if(_status.composing && prefs.contextEnabled &&
       (prefs.aiEnabled || prefs.aiShortcut!="disabled") && !_IsKeyboardDisabled()) {
      com_ptr<ITfRange> anchor;
      if (_pComposition && SUCCEEDED(_pComposition->GetRange(&anchor)) && anchor) {
        com_ptr<ITfContext> anchorContext;
        if (FAILED(anchor->GetContext(&anchorContext)) || anchorContext != editor)
          anchor.Release();
      }
      if(!anchor) { TF_SELECTION selection{};ULONG fetched=0;
        if(SUCCEEDED(editor->GetSelection(ec,TF_DEFAULT_SELECTION,1,&selection,&fetched))&&fetched&&selection.range){selection.range->Clone(&anchor);selection.range->Release();}
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
    // Reading ranges can re-enter TSF. A subsequent focus change or refresh
    // must not attach this snapshot to its new request.
    if (_HasFocusedEditContext(editor) && epoch == _compositionRefreshEpoch &&
        serial == _compositionRefreshSerial)
      m_client.UpdateTextContext(before, after);
  } catch(...) { /* Context is optional. Never unwind through the host editor. */ }

  if (epoch == _compositionRefreshEpoch && serial == _compositionRefreshSerial)
    _orangecellRefreshPending = false;
  return TRUE;
}
