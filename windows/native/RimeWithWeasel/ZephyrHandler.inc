#include "ZephyrKeySettings.h"
// Included in RimeWithWeasel.cpp; all entry points already serialized by upstream IPC.
void RimeWithWeaselHandler::_ZephyrRefresh(WeaselSessionId id) {
  auto& z=m_zephyr[id];z.candidates.clear();z.comments.clear();
  auto session=to_session_id(id);
  rime_api->clear_composition(session);
  if(z.chinese&&!z.input.empty()) {
    std::string pinyin=z.input;std::replace(pinyin.begin(),pinyin.end(),' ','\'');
    rime_api->set_option(session,"ascii_mode",false);
    rime_api->set_option(session,"traditionalization",z.traditional);
    if(RIME_API_AVAILABLE(rime_api,set_input))rime_api->set_input(session,pinyin.c_str());
    RIME_STRUCT(RimeContext,ctx);
    if(rime_api->get_context(session,&ctx)) {
      for(int i=0;i<ctx.menu.num_candidates&&i<7;i++)z.add(u8tow(ctx.menu.candidates[i].text),L"Rime");
      rime_api->free_context(&ctx);
    }
  }
  if(!z.input.empty()) {
    z.add(u8tow(z.input),z.chinese?L"原文":L"Original");
    m_zephyr_ai.submit({id,z.revision,z.input,z.chinese,z.traditional});
  } else m_zephyr_ai.cancel(id);
}
bool RimeWithWeaselHandler::_ZephyrRespond(WeaselSessionId id,EatLine eat) {
  if(!eat)return false;
  auto& z=m_zephyr[id];auto& session=get_session_status(id);
  weasel::CandidateInfo info;info.is_last_page=(z.page+1)*5>=z.candidates.size();
  info.currentPage=int(z.page);info.totalPages=int((z.candidates.size()+4)/5);info.highlighted=int(z.selected%5);
  for(size_t i=z.page*5;i<z.candidates.size()&&i<(z.page+1)*5;i++) {
    info.candies.emplace_back(escape_string(z.candidates[i]));info.comments.emplace_back(escape_string(z.comments[i]));
    info.labels.emplace_back(std::to_wstring(i%5+1));
  }
  std::wstringstream cs;boost::archive::text_woarchive ca(cs);ca<<info;
  std::wstring header=L"action=status,ctx,config,style";
  if(!z.commit.empty())header+=L",commit";header+=L"\n";
  std::wstring body=L"status.ascii_mode="+std::wstring(z.chinese?L"0":L"1")+L"\nstatus.disabled=0\nstatus.composing="+std::wstring(z.input.empty()?L"0":L"1")+
    L"\nstatus.schema_id=zephyr\nctx.preedit="+escape_string(u8tow(z.input))+L"\nctx.preedit.cursor=0,"+
    std::to_wstring(z.input.size())+L","+std::to_wstring(z.caret)+L"\nctx.aux="+
    std::wstring(z.chinese?(z.traditional?L"繁":L"简"):L"EN")+
    (zephyr::shortcutLabel(z.languageShortcut).empty()?L"":L" · "+zephyr::shortcutLabel(z.languageShortcut)+(z.chinese?L" → EN":L" → 中"))+
    L"\nctx.cand="+cs.str()+L"\nconfig.inline_preedit=0\n";
  auto style=session.style;style.inline_preedit=false;
  std::wstringstream ss;boost::archive::text_woarchive sa(ss);sa<<style;body+=L"style="+ss.str()+L"\n";
  if(!z.commit.empty()){body+=L"commit="+escape_string(z.commit)+L"\n";z.commit.clear();}
  body+=L".\n";return eat(header)&&eat(body);
}
BOOL RimeWithWeaselHandler::_ZephyrKey(weasel::KeyEvent key,WeaselSessionId id,EatLine eat) {
  auto& z=m_zephyr[id];int code=key.keycode;
  if(auto prefs=zephyr::currentKeyPreferences()){z.enterOriginal=prefs->enterOriginal;z.spaceOriginal=prefs->spaceOriginal;z.languageShortcut=prefs->languageShortcut;z.scriptShortcut=prefs->scriptShortcut;}
  if(code==0) {
    if(!z.commit.empty()){_ZephyrRespond(id,eat);return TRUE;}
    auto result=m_zephyr_ai.take(id);
    if(!result||result->revision!=z.revision||z.input.empty())return FALSE;
    z.segmentation=result->segmentation;z.enterOriginal=result->enterOriginal;z.spaceOriginal=result->spaceOriginal;z.adopt(result->revision,result->candidates);_ZephyrRespond(id,eat);return TRUE;
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
  bool changed=false,handled=true;
  if(ctrl&&code==ibus::Return&&!z.input.empty()) {z.commit=u8tow(z.input);z.clear();changed=true;}
  else if(alt&&!ctrl&&!(key.mask&(ibus::SHIFT_MASK|ibus::SUPER_MASK))&&code>='1'&&code<='5'&&z.chooseDigit(code-'0')) {changed=true;}
  else if(ctrl||alt||(key.mask&ibus::SUPER_MASK)) {if(!z.input.empty()){z.clear();changed=true;}handled=false;}
  // Number row selects an existing slot only while composing. No global
  // preserved digit keys: idle digits must reach the host application normally.
  else if(!(key.mask&ibus::SHIFT_MASK)&&code>='1'&&code<='5'&&z.chooseDigit(code-'0')) {changed=true;}
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
  else if((code==ibus::Return||code==ibus::Tab||(code==' '&&!z.segmentation))&&!z.input.empty()) {z.choose(z.selected);changed=true;}
  else if(code>=32&&code<=126&&(code!=' '||!z.input.empty()||z.segmentation)) {z.insert(char(code));changed=true;}
  else handled=false;
  if(changed)_ZephyrRefresh(id);
  _ZephyrRespond(id,eat);return handled?TRUE:FALSE;
}
