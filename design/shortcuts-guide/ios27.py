CSS="""
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,'SF Pro Text','Inter','Helvetica Neue',Arial,sans-serif;background:#EEF3F0;color:#0B1411;padding:36px 40px 40px;width:max-content}
h1{font-size:30px;font-weight:800;display:flex;align-items:center;gap:14px;letter-spacing:-.4px}
h1 img{width:44px;height:44px;border-radius:11px}
.sub{color:#5b6b64;font-size:16px;margin:6px 0 24px 58px;max-width:1700px}
.row{display:flex;gap:28px;align-items:flex-start}
.col{width:330px}
.label{font-weight:800;font-size:15px;margin-bottom:10px;display:flex;gap:8px;align-items:center}
.bad{color:#DC2626}.good{color:#059669}
.phone{width:330px;border-radius:44px;background:#000;padding:12px 12px 26px;box-shadow:0 18px 40px rgba(4,47,36,.2);min-height:560px}
.top{display:flex;align-items:center;gap:10px;padding:16px 10px 18px;color:#fff;font-weight:600;font-size:16px}
.top img{width:26px;height:26px;border-radius:7px}
.back{width:34px;height:34px;border-radius:17px;background:#1c1c1e;display:flex;align-items:center;justify-content:center;color:#fff}
.card{background:#2c2c2e;border-radius:26px;padding:16px 16px;margin:0 2px 14px;color:#fff;font-size:18px;line-height:1.75}
.card .div{border-top:1px solid #3a3a3c;margin:12px -16px;}
.tok{display:inline-block;background:#1f3046;color:#4aa3ff;border-radius:9px;padding:0 9px;line-height:1.5;margin:2px 0}
.tok.ph{color:#41658f}
.tok.var{background:#0a84ff;color:#fff;font-weight:600}
.tok.var .i{font-size:13px;margin-right:4px}
.x{float:right;width:24px;height:24px;border-radius:12px;background:#48484a;color:#1c1c1e;text-align:center;line-height:24px;font-size:13px;font-weight:800}
.more{display:inline-flex;width:24px;height:24px;border-radius:12px;border:2px solid #0a84ff;color:#0a84ff;align-items:center;justify-content:center;font-size:13px;vertical-align:-3px}
.sm{font-size:14.5px;color:#aeaeb2;line-height:1.6}
.ring{outline:3px solid #ff453a;outline-offset:2px;border-radius:10px}
.ringg{outline:3px solid #30d158;outline-offset:2px;border-radius:10px}
.cap{margin-top:14px;font-size:14.5px;line-height:1.45;color:#24302b}
.cap b{color:#047857}.cap .r{color:#DC2626;font-weight:700}
.icon{display:inline-block;width:22px;height:22px;border-radius:6px;vertical-align:-4px;margin-right:8px}
.note{margin-top:22px;background:#fff;border-radius:14px;padding:14px 18px;font-size:14px;line-height:1.5;color:#24302b;max-width:1440px;box-shadow:0 4px 14px rgba(0,0,0,.05)}
.disc{margin-top:16px;color:#6b7c74;font-size:12.5px}
"""
def phone(title, cards):
    return f'<div class="phone"><div class="top"><div class="back">‹</div><img src="logo.png">{title}</div>{cards}</div>'
msg_trigger='''<div class="card"><span class="x">✕</span><span style="color:#30d158">●</span> When I receive a message where <span class="more">›</span>
<div class="div"></div><span class="tok">Message</span> contains <span class="tok">debited from your account</span></div>'''
wallet_trigger='''<div class="card"><span class="x">✕</span><span style="color:#0a84ff">▬</span> When <span class="tok">Any Card</span> is tapped <span class="more">›</span></div>'''
cols=[
('<span class="bad">✕ Now (records nothing)</span>', phone('Log Expense from Mes…', msg_trigger+'''<div class="card"><span class="x">✕</span><img class="icon" src="logo.png">Log expense from <span class="tok ring">KFH</span> <span class="more">›</span></div>'''),
 'The action receives the <span class="r">word “KFH”</span>, not the SMS — there is no amount to read.'),
('<span class="good">✓ Fixed</span>', phone('Log Expense from Mes…', msg_trigger+'''<div class="card"><span class="x">✕</span><img class="icon" src="logo.png">Log expense from <span class="tok var ringg"><span class="i">💬</span>Message</span> <span class="more" style="transform:rotate(90deg)">›</span>
<div class="div"></div><div class="sm">Bank / account&nbsp; <span class="tok">KFH Credit Card</span><br>Sender&nbsp; <span class="tok ph">Sender</span></div></div>'''),
 '<b>1.</b> Tap the field → delete “KFH” → tap <b>Select Variable</b> (or the variable bar above the keyboard) → choose the trigger’s <b>Message</b>. It becomes a solid blue token.<br><b>2.</b> Tap <b>›</b> to expand → type <b>KFH Credit Card</b> in <b>Bank / account</b>.'),
('<span class="bad">✕ Now (empty fields)</span>', phone('Log Wallet Transactio…', wallet_trigger+'''<div class="card"><span class="x">✕</span><img class="icon" src="logo.png">Log <span class="tok ph ring">Amount</span> at <span class="tok ph ring">Merchant</span> <span class="more">›</span></div>'''),
 '<span class="r">Faded</span> Amount / Merchant are just placeholders — nothing is passed.'),
('<span class="good">✓ Fixed</span>', phone('Log Wallet Transactio…', wallet_trigger+'''<div class="card"><span class="x">✕</span><img class="icon" src="logo.png">Log <span class="tok var ringg"><span class="i">▬</span>Amount</span> at <span class="tok var ringg"><span class="i">▬</span>Merchant</span> <span class="more" style="transform:rotate(90deg)">›</span>
<div class="div"></div><div class="sm">Card&nbsp; <span class="tok var"><span class="i">▬</span>Card</span></div></div>'''),
 'Tap <b>Amount</b> → <b>Select Variable</b> → the Wallet trigger’s <b>Amount</b>. Do the same for <b>Merchant</b>, then tap <b>›</b> and set <b>Card</b> to the card/name variable.'),
]
html=f'''<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body>
<h1><img src="logo.png">iOS 27 · Fix your automations</h1>
<div class="sub">Your triggers are right. The action fields must use the trigger’s <b>variables</b> (solid blue tokens), not typed text. Put the bank name in the new <b>Bank / account</b> field.</div>
<div class="row">{''.join(f'<div class="col"><div class="label">{l}</div>{p}<div class="cap">{c}</div></div>' for l,p,c in cols)}</div>
<div class="note"><b>Filters:</b> keep “Message contains” short and generic so wording changes don’t break it — e.g. <b>debited from your account</b>, <b>Trx on your card</b>, <b>has been debited</b>. Leave out account numbers like XXXX81150000 unless you want only that one account. One automation per bank wording is fine.<br>
<b>Test:</b> after fixing, wait for a real SMS or Apple Pay tap. If something is still wired wrong, Expenses now sends an <b>“Automation needs fixing”</b> notification telling you which field.</div>
<div class="disc">Illustration based on your iOS 27.2 screenshots — exact variable names in the picker may differ slightly.</div>
</body></html>'''
open('4-ios27-fix.html','w').write(html)
