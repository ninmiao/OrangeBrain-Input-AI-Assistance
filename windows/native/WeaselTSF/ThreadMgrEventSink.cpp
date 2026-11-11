#include "stdafx.h"
#include "WeaselTSF.h"

STDMETHODIMP WeaselTSF::OnInitDocumentMgr(ITfDocumentMgr* pDocMgr) {
  return S_OK;
}

STDMETHODIMP WeaselTSF::OnUninitDocumentMgr(ITfDocumentMgr* pDocMgr) {
  return S_OK;
}

STDMETHODIMP WeaselTSF::OnSetFocus(ITfDocumentMgr* pDocMgrFocus,
                                   ITfDocumentMgr* pDocMgrPrevFocus) {
  // Moving between controls in one application does not necessarily produce
  // ITfKeyEventSink::OnSetFocus(FALSE). Cancel the server composition here,
  // rather than merely hiding its UI and reviving it on a later focus.
  if (pDocMgrFocus != pDocMgrPrevFocus) {
    if (_status.composing || _IsComposing() || _hasPendingUI) _AbortComposition(true);
    else m_client.ClearComposition();
  }
  _InitTextEditSink(pDocMgrFocus);

  com_ptr<ITfDocumentMgr> pCandidateListDocumentMgr;
  com_ptr<ITfContext> pTfContext = _GetUIContextDocument();
  if ((nullptr != pTfContext) &&
      SUCCEEDED(pTfContext->GetDocumentMgr(&pCandidateListDocumentMgr))) {
    if (pCandidateListDocumentMgr != pDocMgrFocus) {
      _HideUI();
    } else {
      _ShowUI();
    }
  }

  return S_OK;
}

STDMETHODIMP WeaselTSF::OnPushContext(ITfContext* pContext) {
  com_ptr<ITfDocumentMgr> focused;
  com_ptr<ITfContext> top;
  if (_status.composing && _pThreadMgr &&
      SUCCEEDED(_pThreadMgr->GetFocus(&focused)) && focused &&
      SUCCEEDED(focused->GetTop(&top)) && top != _pEditSessionContext)
    _AbortComposition(true);
  return S_OK;
}

STDMETHODIMP WeaselTSF::OnPopContext(ITfContext* pContext) {
  if (pContext == _pEditSessionContext &&
      (_status.composing || _IsComposing() || _hasPendingUI))
    _AbortComposition(true);
  return S_OK;
}

BOOL WeaselTSF::_InitThreadMgrEventSink() {
  ITfSource* pSource;
  if (_pThreadMgr->QueryInterface(IID_ITfSource, (void**)&pSource) != S_OK)
    return FALSE;
  if (pSource->AdviseSink(IID_ITfThreadMgrEventSink,
                          (ITfThreadMgrEventSink*)this,
                          &_dwThreadMgrEventSinkCookie) != S_OK) {
    _dwThreadMgrEventSinkCookie = TF_INVALID_COOKIE;
    pSource->Release();
    return FALSE;
  }
  pSource->Release();
  return TRUE;
}

void WeaselTSF::_UninitThreadMgrEventSink() {
  ITfSource* pSource;
  if (_dwThreadMgrEventSinkCookie == TF_INVALID_COOKIE)
    return;
  if (SUCCEEDED(_pThreadMgr->QueryInterface(IID_ITfSource, (void**)&pSource))) {
    pSource->UnadviseSink(_dwThreadMgrEventSinkCookie);
    pSource->Release();
  }
  _dwThreadMgrEventSinkCookie = TF_INVALID_COOKIE;
}
