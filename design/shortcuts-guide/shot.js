const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 2200, height: 1200 }, deviceScaleFactor: 2 });
  for (const n of process.argv.slice(2)) {
    await p.goto('file://' + process.cwd() + '/' + n + '.html');
    const el = await p.$('body');
    await el.screenshot({ path: n + '.png' });
  }
  await b.close();
})();
