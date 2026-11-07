# Generates an illustrated Shortcuts setup guide (HTML -> PNG via Playwright).
import html, json, subprocess, sys, pathlib

CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,'SF Pro Text','Inter','Helvetica Neue',Arial,sans-serif;background:#EEF3F0;color:#0B1411;padding:36px 40px 44px;width:max-content}
h1{font-size:30px;font-weight:800;letter-spacing:-.4px;display:flex;align-items:center;gap:14px}
h1 .logo{width:44px;height:44px;border-radius:11px}
.sub{color:#5b6b64;font-size:16px;margin:6px 0 26px 58px;max-width:1500px}
.row{display:flex;gap:26px;align-items:flex-start}
.step{width:300px}
.cap{margin-top:14px;font-size:14.5px;line-height:1.42;color:#24302b}
.cap b{color:#047857}
.num{display:inline-flex;width:24px;height:24px;border-radius:12px;background:#059669;color:#fff;font-weight:700;font-size:13px;align-items:center;justify-content:center;margin-right:6px;vertical-align:1px}
.phone{width:300px;height:620px;border-radius:44px;background:#000;padding:10px;box-shadow:0 18px 40px rgba(4,47,36,.18)}
.screen{width:100%;height:100%;border-radius:35px;background:#F2F2F7;overflow:hidden;position:relative;font-size:13px}
.status{height:40px;display:flex;justify-content:space-between;align-items:center;padding:0 24px;font-weight:600;font-size:13px}
.island{position:absolute;top:9px;left:50%;transform:translateX(-50%);width:86px;height:24px;border-radius:12px;background:#000}
.nav{display:flex;justify-content:space-between;align-items:center;padding:4px 16px 6px;color:#007AFF;font-size:14px;min-height:30px}
.nav .t{color:#000;font-weight:600}
.big{font-size:27px;font-weight:800;padding:2px 16px 10px;letter-spacing:-.3px}
.sec{color:#6b6b70;font-size:11px;text-transform:uppercase;padding:12px 30px 5px;letter-spacing:.2px}
.group{background:#fff;border-radius:11px;margin:0 14px}
.cell{display:flex;align-items:center;gap:10px;padding:10px 12px;border-bottom:.5px solid #e2e2e6;min-height:40px}
.cell:last-child{border-bottom:none}
.cell .ic{width:28px;height:28px;border-radius:7px;display:flex;align-items:center;justify-content:center;color:#fff;font-size:15px;flex:none}
.cell .grow{flex:1}
.cell .val{color:#8a8a8e}
.cell .blue{color:#007AFF}
.chev{color:#c4c4c7;font-weight:700}
.check{color:#007AFF;font-weight:800;font-size:15px}
.hl{outline:3px solid #10B981;outline-offset:-3px;border-radius:10px;background:#ECFDF5 !important;position:relative}
.tag{position:absolute;right:-6px;top:-10px;background:#059669;color:#fff;font-size:11px;font-weight:700;border-radius:10px;padding:2px 7px;box-shadow:0 2px 6px rgba(0,0,0,.2)}
.tabbar{position:absolute;bottom:0;left:0;right:0;height:62px;background:rgba(249,249,251,.96);border-top:.5px solid #d8d8dc;display:flex;justify-content:space-around;padding-top:8px;font-size:10px;color:#8e8e93}
.tabbar div{display:flex;flex-direction:column;align-items:center;gap:2px}
.tabbar .on{color:#007AFF}
.tabbar .i{font-size:18px}
.auto{background:#fff;border-radius:12px;margin:0 14px 8px;padding:8px 12px;display:flex;gap:10px;align-items:center}
.auto .ic{width:30px;height:30px;border-radius:8px;display:flex;align-items:center;justify-content:center;color:#fff;font-size:15px;flex:none}
.auto .tt{font-weight:600;font-size:12.5px;line-height:1.3}
.auto .dd{color:#8a8a8e;font-size:11.5px;margin-top:2px}
.plus{position:absolute;right:16px;top:44px;width:30px;height:30px;border-radius:15px;background:#007AFF;color:#fff;display:flex;align-items:center;justify-content:center;font-size:20px;font-weight:600}
.actioncard{background:#fff;border-radius:14px;margin:6px 14px;padding:14px;line-height:1.9;font-size:14px}
.tok{display:inline-block;background:#E5F0FF;color:#0062CC;border-radius:7px;padding:0 7px;font-weight:600;line-height:1.6;font-size:13px}
.tok.g{background:#E7F8F0;color:#047857}
.appicon{width:22px;height:22px;border-radius:6px;vertical-align:-5px;margin-right:6px}
.search{background:#e3e3e8;border-radius:10px;margin:4px 14px 10px;padding:8px 10px;color:#3c3c43}
.btn{margin:14px;background:#007AFF;color:#fff;text-align:center;border-radius:12px;padding:11px;font-weight:600}
.note{background:#FFF7E6;border:1px solid #F5D08A;border-radius:12px;padding:12px 14px;font-size:13.5px;line-height:1.45;color:#5c4400;margin-top:12px;width:300px}
.radio{width:18px;height:18px;border-radius:9px;border:2px solid #c7c7cc;flex:none}
.radio.on{border:6px solid #007AFF}
.toggle{width:40px;height:24px;border-radius:12px;background:#e5e5ea;position:relative;flex:none}
.toggle:after{content:'';position:absolute;width:20px;height:20px;border-radius:10px;background:#fff;top:2px;left:2px;box-shadow:0 1px 3px rgba(0,0,0,.25)}
.toggle.on{background:#34C759}.toggle.on:after{left:18px}
.foot{font-size:11px;color:#6b6b70;padding:6px 30px 0;line-height:1.35}
.cardart{width:40px;height:26px;border-radius:5px;flex:none}
.disc{margin-top:26px;color:#6b7c74;font-size:12.5px}
"""

def phone(inner, title_bar=True):
    return f'<div class="phone"><div class="screen"><div class="island"></div><div class="status"><span>9:41</span><span>●●● ▮</span></div>{inner}</div></div>'

def step(n, inner, caption):
    return f'<div class="step">{phone(inner)}<div class="cap"><span class="num">{n}</span>{caption}</div></div>'

def tabbar(active="Automation"):
    items=[("Shortcuts","▦"),("Automation","⏱"),("Gallery","✦")]
    return '<div class="tabbar">'+''.join(f'<div class="{"on" if n==active else ""}"><span class="i">{i}</span>{n}</div>' for n,i in items)+'</div>'

LOGO='logo.png'
def act_title(t): return f'<img class="appicon" src="{LOGO}">{t}'

# ---------- Shared screens ----------
def s_automation_tab(extra=""):
    return f'''<div class="plus" style="outline:3px solid #10B981;outline-offset:3px">+</div><span class="tag" style="position:absolute;right:8px;top:80px">Tap</span>
    <div class="big" style="padding-top:34px">Automation</div>
    <div class="sec">Personal</div>
    {extra}
    {tabbar()}'''

def s_new_automation(highlight):
    rows=[("Time of Day","#FF9500","☀"),("Alarm","#FF9500","⏰"),("Email","#007AFF","✉"),
          ("Message","#34C759","💬"),("Transaction","#000","▭"),("Wi-Fi","#007AFF","◉"),("NFC","#5856D6","◎"),("App","#5856D6","▢")]
    cells=''
    for name,c,i in rows:
        hl=' hl' if name==highlight else ''
        tag='<span class="tag">Tap</span>' if name==highlight else ''
        sub={'Transaction':'<div style="font-size:10.5px;color:#8a8a8e">When I tap a card in Wallet</div>','Message':'<div style="font-size:10.5px;color:#8a8a8e">When I get a message…</div>'}.get(name,'')
        cells+=f'<div class="cell{hl}">{tag}<div class="ic" style="background:{c}">{i}</div><div class="grow">{name}{sub}</div><span class="chev">›</span></div>'
    return f'''<div class="nav"><span>Cancel</span><span class="t">New Automation</span><span></span></div>
    <div class="search">⌕ Search</div>
    <div class="group">{cells}</div>'''

def s_blank():
    return f'''<div class="nav"><span>‹ Back</span><span class="t">New Automation</span><span></span></div>
    <div class="sec">Get started</div>
    <div class="group"><div class="cell hl"><span class="tag">Tap</span><div class="ic" style="background:#8E8E93">＋</div><div class="grow"><b>New Blank Automation</b></div></div></div>
    <div class="sec">Suggestions</div>
    <div class="group"><div class="cell" style="opacity:.5"><div class="ic" style="background:#FF9500">♪</div><div class="grow">Play Music</div></div>
    <div class="cell" style="opacity:.5"><div class="ic" style="background:#34C759">☎</div><div class="grow">Send Message</div></div></div>'''

def s_search(query, action, desc):
    return f'''<div class="nav"><span></span><span class="t">Add Action</span><span>Cancel</span></div>
    <div class="search">⌕ <span style="color:#000">{query}</span></div>
    <div class="sec">Expenses</div>
    <div class="group">
      <div class="cell hl"><span class="tag">Tap</span><img class="appicon" src="{LOGO}" style="width:28px;height:28px;border-radius:7px;margin:0"><div class="grow"><b>{action}</b><div style="font-size:10.5px;color:#8a8a8e">{desc}</div></div></div>
      <div class="cell" style="opacity:.55"><img class="appicon" src="{LOGO}" style="width:28px;height:28px;border-radius:7px;margin:0"><div class="grow">{"Log Wallet Transaction" if "Message" in action else "Log Expense from Message"}</div></div>
      <div class="cell" style="opacity:.55"><img class="appicon" src="{LOGO}" style="width:28px;height:28px;border-radius:7px;margin:0"><div class="grow">Add Expense</div></div>
    </div>'''

# ---------- SMS flow ----------
def sms_trigger(contains, sender_text, sender_hl=False):
    sh=' hl' if sender_hl else ''
    stag='<span class="tag">Optional</span>' if sender_hl else ''
    return f'''<div class="nav"><span>‹ Back</span><span class="t">Message</span><span style="font-weight:600">Next</span></div>
    <div class="sec">When</div>
    <div class="group">
      <div class="cell{sh}">{stag}<div class="grow">Sender</div><span class="blue">{sender_text}</span></div>
      <div class="cell hl"><span class="tag">Type</span><div class="grow">Message Contains</div><span class="blue">{contains}</span></div>
    </div>
    <div class="sec" style="margin-top:4px">&nbsp;</div>
    <div class="group">
      <div class="cell"><div class="radio"></div><div class="grow">Run After Confirmation</div></div>
      <div class="cell hl"><span class="tag">Select</span><div class="radio on"></div><div class="grow"><b>Run Immediately</b></div></div>
    </div>
    <div class="group" style="margin-top:12px"><div class="cell"><div class="grow">Notify When Run</div><div class="toggle"></div></div></div>
    <div class="foot">Turn off — Expenses sends its own, nicer notification.</div>'''

def sms_contacts():
    people=[("Emirates NBD","#0A3D91",True),("ADCB","#C8102E",True),("Mashreq","#F37021",True),("Ahmed (friend)","#8E8E93",False),("Dentist","#8E8E93",False)]
    cells=''.join(f'<div class="cell{" hl" if on else ""}"><div class="ic" style="background:{c};border-radius:14px">{n[0]}</div><div class="grow">{n}</div>{"<span class=check>✓</span>" if on else ""}</div>' for n,c,on in people)
    return f'''<div class="nav"><span>Cancel</span><span class="t">Choose Contacts</span><span style="font-weight:600">Done</span></div>
    <div class="search">⌕ Search contacts</div>
    <div class="group">{cells}</div>
    <div class="foot">Pick every bank that texts you. Only <b>saved contacts</b> appear here.</div>'''

def sms_action():
    return f'''<div class="nav"><span>‹ Back</span><span class="t">New Automation</span><span style="font-weight:600">Done</span></div>
    <div class="sec">When I get a message containing “debited”</div>
    <div class="actioncard">{act_title('<b>Log Expense from Message</b>')}<br>
      Log expense from <span class="tok hl" style="outline-offset:1px">◫ Shortcut Input › Content</span><br>
      <span style="color:#8a8a8e;font-size:12.5px">Sender</span> <span class="tok">◫ Shortcut Input › Sender</span>
    </div>
    <div class="foot" style="padding-top:10px">Tap <b>Message</b> → choose <b>Shortcut Input</b>, then tap the blue token again and pick <b>Content</b>.<br><br>Tap <b>Show More</b> → set <b>Sender</b> to <b>Shortcut Input › Sender</b> (lets the app detect the bank).</div>'''

def automations_list():
    autos=[("#34C759","💬","When I get a message containing “debited”","Log Expense from Message"),
           ("#34C759","💬","When I get a message containing “spent”","Log Expense from Message"),
           ("#34C759","💬","When I get a message containing “purchase”","Log Expense from Message"),
           ("#34C759","💬","When I get a message containing “withdrawn”","Log Expense from Message"),
           ("#000","▭","When I tap any of 3 cards","Log Wallet Transaction")]
    rows=''.join(f'<div class="auto"><div class="ic" style="background:{c}">{i}</div><div><div class="tt">{t}</div><div class="dd">{d} · Immediately</div></div></div>' for c,i,t,d in autos)
    return f'''<div class="big" style="padding-top:26px">Automation</div><div class="sec" style="padding-top:4px">Personal</div>{rows}{tabbar()}'''

# ---------- Wallet flow ----------
def wallet_trigger():
    cards=[("Emirates NBD Visa","linear-gradient(135deg,#0A3D91,#3A6FD8)",True),("ADCB Mastercard","linear-gradient(135deg,#7a0f1f,#C8102E)",True),
           ("Mashreq Debit","linear-gradient(135deg,#F37021,#f7a35c)",True),("Apple Cash","linear-gradient(135deg,#111,#444)",False)]
    cells=''.join(f'<div class="cell{" hl" if on else ""}"><div class="cardart" style="background:{g}"></div><div class="grow">{n}</div>{"<span class=check>✓</span>" if on else ""}</div>' for n,g,on in cards)
    return f'''<div class="nav"><span>‹ Back</span><span class="t">Transaction</span><span style="font-weight:600">Next</span></div>
    <div class="sec">When I tap any of these cards</div>
    <div class="group">{cells}</div>
    <div class="group" style="margin-top:12px">
      <div class="cell"><div class="grow">Merchant</div><span class="val">Any</span></div>
      <div class="cell"><div class="grow">Category</div><span class="val">Any</span></div>
    </div>
    <div class="group" style="margin-top:12px">
      <div class="cell"><div class="radio"></div><div class="grow">Run After Confirmation</div></div>
      <div class="cell hl"><span class="tag">Select</span><div class="radio on"></div><div class="grow"><b>Run Immediately</b></div></div>
    </div>'''

def wallet_action():
    return f'''<div class="nav"><span>‹ Back</span><span class="t">New Automation</span><span style="font-weight:600">Done</span></div>
    <div class="sec">When I tap any of 3 cards</div>
    <div class="actioncard">{act_title('<b>Log Wallet Transaction</b>')}<br>
      Log <span class="tok hl" style="outline-offset:1px">◫ Shortcut Input › Amount</span> at <span class="tok">◫ Shortcut Input › Merchant</span><br>
      <span style="color:#8a8a8e;font-size:12.5px">Card</span> <span class="tok">◫ Shortcut Input › Name</span>
    </div>
    <div class="foot" style="padding-top:10px">Tap each field → <b>Shortcut Input</b> → tap the token again and pick <b>Amount</b>, <b>Merchant</b>, and <b>Name</b> (the card’s name, used to fill the Bank field).<br><br>One automation covers <b>all the cards</b> you ticked.</div>'''

def page(title, sub, steps, note=None):
    note_html=f'<div class="note">{note}</div>' if note else ''
    return f'''<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body>
    <h1><img class="logo" src="{LOGO}">{title}</h1><div class="sub">{sub}</div>
    <div class="row">{''.join(steps)}</div>{note_html}
    <div class="disc">Illustration of the iOS 17/18 Shortcuts app — wording and layout may differ slightly on your iPhone.</div>
    </body></html>'''

pages = {
"1-bank-sms": page("Part 1 · Record bank SMS automatically",
  "Create one automation per keyword your banks use (e.g. “debited”, “spent”, “purchase”, “withdrawn”). Leave Sender empty to catch every bank — the app ignores OTPs and promos.",
  [step(1, s_automation_tab(), "Open <b>Shortcuts</b> → <b>Automation</b> tab → tap <b>+</b>."),
   step(2, s_new_automation("Message"), "Choose <b>Message</b>."),
   step(3, sms_trigger("debited","Any"), "<b>Message Contains</b>: type <b>debited</b>. Leave <b>Sender</b> as Any. Select <b>Run Immediately</b>, turn off <b>Notify When Run</b>, tap <b>Next</b>."),
   step(4, s_blank(), "Tap <b>New Blank Automation</b>."),
   step(5, s_search("log expense","Log Expense from Message","Expenses"), "Tap <b>Add Action</b>, search <b>log expense</b>, pick <b>Log Expense from Message</b>."),
   step(6, sms_action(), "Set <b>Message</b> = Shortcut Input › <b>Content</b> and <b>Sender</b> = Shortcut Input › <b>Sender</b>. Tap <b>Done</b>.")]),
"2-multiple-banks": page("Part 2 · Several banks / contacts",
  "Two ways to cover multiple banks. Option A (recommended): repeat Part 1 for each keyword. Option B: limit an automation to specific bank senders.",
  [step("A", automations_list(), "<b>Option A:</b> duplicate the SMS automation for each keyword — <b>debited</b>, <b>spent</b>, <b>purchase</b>, <b>withdrawn</b>, <b>paid</b>. Every bank is covered."),
   step("B1", sms_trigger("AED","Choose", sender_hl=True), "<b>Option B:</b> in the Message trigger tap <b>Sender › Choose</b>…"),
   step("B2", sms_contacts(), "…and tick <b>every bank</b> at once (multiple contacts allowed). Set <b>Message Contains</b> to a word all of them use, e.g. <b>AED</b> or your currency."),
  ],
  note="<b>About Sender:</b> Shortcuts only lists <b>saved contacts</b>. A bank that texts from a <b>number</b> (e.g. 2626 or +971…) can be saved as a contact named after the bank. Banks that send from a <b>name</b> (e.g. “ADCB”, “AD-HDFCBK”) can’t be saved — use Option A for those. Either way, the app reads the sender to fill in the <b>Bank</b> field."),
"3-wallet-cards": page("Part 3 · Apple Pay / Wallet cards",
  "One automation covers every card you pick. If your bank also texts you for the same purchase, the app merges them, so nothing is counted twice.",
  [step(1, s_new_automation("Transaction"), "Automation tab → <b>+</b> → choose <b>Transaction</b>."),
   step(2, wallet_trigger(), "Tick <b>all the cards</b> you pay with. Leave Merchant and Category as <b>Any</b>. Select <b>Run Immediately</b> → <b>Next</b>."),
   step(3, s_search("log wallet","Log Wallet Transaction","Expenses"), "<b>New Blank Automation</b> → Add Action → search <b>log wallet</b> → <b>Log Wallet Transaction</b>."),
   step(4, wallet_action(), "Set <b>Amount</b>, <b>Merchant</b>, and <b>Card</b> (= Shortcut Input › <b>Name</b>). Tap <b>Done</b>."),
   step(5, automations_list(), "All done — your automations list should look like this. Test it by paying with Apple Pay or pasting a bank SMS in the app.")]),
}
out=pathlib.Path('.')
for name,h in pages.items():
    (out/f'{name}.html').write_text(h)
print(json.dumps(list(pages)))
