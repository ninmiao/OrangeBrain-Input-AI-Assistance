#include "ZephyrKeySettings.h"
// Included in RimeWithWeasel.cpp; all entry points already serialized by upstream IPC.
void RimeWithWeaselHandler::_ZephyrRefresh(WeaselSessionId id) {
  auto& z=m_zephyr[id];z.candidates.clear();z.comments.clear();z.rimeIndices.clear();z.preedit.clear();
  auto session=to_session_id(id);
  if(z.input.empty() || !z.chinese)rime_api->clear_composition(session);
  if(z.chinese&&!z.input.empty()) {
    std::string pinyin=z.input;std::replace(pinyin.begin(),pinyin.end(),' ','\'');
    rime_api->set_option(session,"ascii_mode",false);
    rime_api->set_option(session,"traditionalization",z.traditional);
    if(RIME_API_AVAILABLE(rime_api,set_input))rime_api->set_input(session,pinyin.c_str());
    RIME_STRUCT(RimeContext,ctx);
    if(rime_api->get_context(session,&ctx)) {
      for(int i=0;i<ctx.menu.num_candidates&&i<7;i++)z.add(u8tow(ctx.menu.candidates[i].text),L"Rime",i);
      if(z.partialSelection && ctx.composition.preedit) {
        z.preedit=u8tow(ctx.composition.preedit);
        z.preeditCaret=u8tow(std::string(ctx.composition.preedit).substr(0,ctx.composition.cursor_pos)).size();
      }
      rime_api->free_context(&ctx);
    }
  }
  if(!z.input.empty()) {
    z.add(u8tow(z.input),z.chinese?L"原文":L"Original");
    if(auto prefs=zephyr::currentKeyPreferences();prefs&&prefs->aiEnabled)
      m_zephyr_ai.submit({id,z.revision,z.partialSelection&&!z.preedit.empty()?wtou8(z.preedit):z.input,z.chinese,z.traditional,z.before,z.after});
  } else m_zephyr_ai.cancel(id);
}
bool RimeWithWeaselHandler::_ZephyrChoose(WeaselSessionId id,size_t index) {
  auto& z=m_zephyr[id];
  if(index>=z.candidates.size())return false;
  const int nativeIndex=z.rimeIndices[index];
  if(nativeIndex<0) {z.choose(index);return true;}
  const auto session=to_session_id(id);
  if(!rime_api->select_candidate(session,size_t(nativeIndex)))return false;
  RIME_STRUCT(RimeCommit,commit);
  if(rime_api->get_commit(session,&commit)) {
    if(commit.text)z.commit=u8tow(commit.text);
    rime_api->free_commit(&commit);z.clear();
  } else {
    z.partialSelection=true;z.changed();
  }
  return true;
}
bool RimeWithWeaselHandler::_ZephyrRespond(WeaselSessionId id,EatLine eat) {
  if(!eat)return false;
  auto& z=m_zephyr[id];auto& session=get_session_status(id);
  const auto prefs=zephyr::currentKeyPreferences().value_or(zephyr::KeyPreferences{});
  z.aiStatus=(prefs.aiEnabled||z.manualAi)?m_zephyr_ai.status(id,z.revision):L"手动";
  weasel::CandidateInfo info;info.is_last_page=(z.page+1)*5>=z.candidates.size();
  info.currentPage=int(z.page);info.totalPages=int((z.candidates.size()+4)/5);info.highlighted=int(z.selected%5);
  for(size_t i=z.page*5;i<z.candidates.size()&&i<(z.page+1)*5;i++) {
    info.candies.emplace_back(escape_string(z.candidates[i]));info.comments.emplace_back(escape_string(z.comments[i]));
    info.labels.emplace_back(std::to_wstring(i%5+1));
  }
  std::wstringstream cs;boost::archive::text_woarchive ca(cs);ca<<info;
  std::wstring header=L"action=status,ctx,config,style";
  if(!z.commit.empty())header+=L",commit";header+=L"\n";
  const auto display=z.preedit.empty()?u8tow(z.input):z.preedit;
  const auto cursor=z.preedit.empty()?z.caret:z.preeditCaret;
  std::wstring body=L"status.ascii_mode="+std::wstring(z.chinese?L"0":L"1")+L"\nstatus.disabled=0\nstatus.composing="+std::wstring(z.input.empty()?L"0":L"1")+
    L"\nstatus.schema_id=zephyr\nctx.preedit="+escape_string(display)+L"\nctx.preedit.cursor=0,"+
    std::to_wstring(display.size())+L","+std::to_wstring(cursor)+L"\nctx.aux="+
    std::wstring(z.chinese?(z.traditional?L"繁":L"简"):L"EN")+
    (zephyr::shortcutLabel(z.languageShortcut).empty()?L"":L" · "+zephyr::shortcutLabel(z.languageShortcut)+(z.chinese?L" → EN":L" → 中"))+
    L" · AI "+escape_string(z.aiStatus)+
    (zephyr::shortcutLabel(prefs.aiShortcut).empty()?L"":L" ("+zephyr::shortcutLabel(prefs.aiShortcut)+L")")+
    (z.aiError.empty()?L"":L" · "+escape_string(z.aiError))+
    L"\nctx.cand="+cs.str()+L"\nconfig.inline_preedit=0\n";
  auto style=session.style;style.inline_preedit=false;
  std::wstringstream ss;boost::archive::text_woarchive sa(ss);sa<<style;body+=L"style="+ss.str()+L"\n";
  if(!z.commit.empty()){body+=L"commit="+escape_string(z.commit)+L"\n";z.commit.clear();}
  body+=L".\n";return eat(header)&&eat(body);
}
BOOL RimeWithWeaselHandler::_ZephyrKey(weasel::KeyEvent key,WeaselSessionId id,EatLine eat) {
  auto& z=m_zephyr[id];int code=key.keycode;
  const auto prefs=zephyr::currentKeyPreferences();
  if(prefs){
    z.enterOriginal=prefs->enterOriginal;z.spaceOriginal=prefs->spaceOriginal;z.languageShortcut=prefs->languageShortcut;z.scriptShortcut=prefs->scriptShortcut;
    // Invalidate before processing a digit/selection, including idle poll messages.
    if(z.applyConfiguration(prefs->revision)) {
      m_zephyr_ai.cancel(id);
      if(prefs->aiEnabled&&!z.input.empty())m_zephyr_ai.submit({id,z.revision,z.partialSelection&&!z.preedit.empty()?wtou8(z.preedit):z.input,z.chinese,z.traditional,z.before,z.after});
    }
  }
  if(code==0) {
    if(!z.commit.empty()||z.refreshPending){z.refreshPending=false;_ZephyrRespond(id,eat);return TRUE;}
    auto result=m_zephyr_ai.take(id);
    if(!result||result->revision!=z.revision||z.input.empty()) {
      auto current=m_zephyr_ai.status(id,z.revision);
      if(!z.manualAi&&(!prefs||!prefs->aiEnabled))current=L"手动";
      if(!z.input.empty()&&current!=z.aiStatus){z.aiStatus=current;_ZephyrRespond(id,eat);return TRUE;}
      return FALSE;
    }
    z.aiError=result->error;z.segmentation=result->segmentation;z.enterOriginal=result->enterOriginal;z.spaceOriginal=result->spaceOriginal;z.adopt(result->revision,result->candidates,result->assistantEnabled,result->streaming);_ZephyrRespond(id,eat);return TRUE;
  }
  if(zephyr::shortcutChord(prefs?prefs->aiShortcut:"f8",code,key.mask)) {
    z.shortcuts.reset();
    if(z.input.empty())return FALSE;
    z.retryAi();
    m_zephyr_ai.submit({id,z.revision,z.partialSelection&&!z.preedit.empty()?wtou8(z.preedit):z.input,
                        z.chinese,z.traditional,z.before,z.after,true});
    _ZephyrRespond(id,eat);
    return TRUE;
  }
  bool ctrl=(key.mask&ibus::CONTROL_MASK)!=0,alt=(key.mask&ibus::MOD1_MASK)!=0;
  auto shortcut=z.shortcuts.process(code,key.mask,GetTickCount64(),z.languageShortcut,z.scriptShortcut);
  if(shortcut!=zephyr::ShortcutAction::None) {
    if(shortcut==zephyr::ShortcutAction::Language)z.language();
    else {z.traditional=!z.traditional;z.changed();}
    _ZephyrRefresh(id);_ZephyrRespond(id,eat);return TRUE;
  }
  if(key.mask&ibus::RELEASE_MASK){_ZephyrRespond(id,eat);return FALSE;}
  // Modifier key-down is not a shortcut by itself. Keep pending text until
  // the actual chord arrives (Ctrl+Enter, Alt+digit, Ctrl+Shift+Space, etc.).
  if(code>=ibus::Shift_L && code<=ibus::Hyper_R) {_ZephyrRespond(id,eat);return FALSE;}
  size_t requestedSlot=z.selected;
  bool selecting=(code==ibus::Tab || (code==ibus::Return&&!z.enterOriginal) || (code==' '&&!z.segmentation&&!z.spaceOriginal));
  if(!ctrl&&!(key.mask&ibus::SHIFT_MASK)&&code>='1'&&code<='5') {requestedSlot=z.page*5+size_t(code-'1');selecting=true;}
  if(selecting && requestedSlot<z.rimeIndices.size() && z.rimeIndices[requestedSlot]==-2) {_ZephyrRespond(id,eat);return TRUE;}
  bool changed=false,handled=true;
  if(ctrl&&code==ibus::Return&&!z.input.empty()) {z.commit=u8tow(z.input);z.clear();changed=true;}
  else if(alt&&!ctrl&&!(key.mask&(ibus::SHIFT_MASK|ibus::SUPER_MASK))&&code>='1'&&code<='5'&&!z.input.empty()&&_ZephyrChoose(id,z.page*5+size_t(code-'1'))) {changed=true;}
  else if(ctrl||alt||(key.mask&ibus::SUPER_MASK)) {if(!z.input.empty()){z.clear();changed=true;}handled=false;}
  // Number row selects an existing slot only while composing. No global
  // preserved digit keys: idle digits must reach the host application normally.
  else if(!(key.mask&ibus::SHIFT_MASK)&&code>='1'&&code<='5'&&!z.input.empty()&&_ZephyrChoose(id,z.page*5+size_t(code-'1'))) {changed=true;}
  else if(code>='0'&&code<='9'&&z.input.empty()) handled=false;
  // The numeric keypad remains a way to enter literal digits into composition.
  else if(code>=ibus::KP_0&&code<=ibus::KP_9) {
    if(z.input.empty()) handled=false;
    else {z.insert(char('0'+code-ibus::KP_0));changed=true;}
  }
  else if(code==ibus::Escape&&!z.input.empty()) {z.clear();changed=true;}
  else if(code==ibus::BackSpace&&!z.input.empty()) {z.backspace();changed=true;}
  else if(code==ibus::Delete&&!z.input.empty()) {z.erase();changed=true;}
  else if(code==ibus::Left&&!z.input.empty()) {if(z.caret)--z.caret;}
  else if(code==ibus::Right&&!z.input.empty()) {if(z.caret<z.input.size())++z.caret;}
  else if(code==ibus::Home&&!z.input.empty())z.caret=0;
  else if(code==ibus::End&&!z.input.empty())z.caret=z.input.size();
  else if((code==ibus::Down||code==ibus::Up)&&!z.candidates.empty()) {
    z.selected=(z.selected+z.candidates.size()+(code==ibus::Down?1:-1))%z.candidates.size();z.page=z.selected/5;
  }
  else if(z.originalKey(code==ibus::Return,code==' ')) {z.commit=u8tow(z.input)+(code==' '?L" ":L"");z.clear();changed=true;}
  else if((code==ibus::Return||code==ibus::Tab||(code==' '&&!z.segmentation))&&!z.input.empty()) {_ZephyrChoose(id,z.selected);changed=true;}
  else if(code>=32&&code<=126&&(code!=' '||!z.input.empty()||z.segmentation)) {z.insert(char(code));changed=true;}
  else handled=false;
  if(changed)_ZephyrRefresh(id);
  _ZephyrRespond(id,eat);return handled?TRUE:FALSE;
}

void RimeWithWeaselHandler::UpdateTextContext(const std::wstring& data,DWORD id) {
  auto found=m_zephyr.find(id);if(found==m_zephyr.end())return;
  auto split=data.find(L'\t');if(split==data.npos)return;
  auto decode=[](const std::wstring& hex){std::wstring out;if(hex.size()%4||hex.size()>4000)throw std::runtime_error("context");for(size_t i=0;i<hex.size();i+=4){unsigned n=0;for(size_t j=0;j<4;++j){auto c=hex[i+j];int v=c>=L'0'&&c<=L'9'?c-L'0':c>=L'a'&&c<=L'f'?c-L'a'+10:-1;if(v<0)throw std::runtime_error("context");n=(n<<4)|v;}out+=wchar_t(n);}return wtou8(out);};
  try {
    auto before=decode(data.substr(0,split)),after=decode(data.substr(split+1));auto&z=found->second;
    if(z.before==before&&z.after==after)return;z.before=before;z.after=after;
    // A manual request uses the snapshot at the key press. An edit-session
    // context reply must not cause a second request for the same key press.
    if(z.manualAi)return;
    ++z.revision;z.aiError.clear();z.adopt(z.revision,{});
    if(auto prefs=zephyr::currentKeyPreferences();prefs&&prefs->aiEnabled&&!z.input.empty())
      m_zephyr_ai.submit({id,z.revision,z.partialSelection&&!z.preedit.empty()?wtou8(z.preedit):z.input,z.chinese,z.traditional,z.before,z.after});
  }catch(...){m_zephyr_ai.cancel(id);}
}
