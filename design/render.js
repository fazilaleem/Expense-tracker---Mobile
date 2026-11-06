const { chromium } = require('playwright');
(async () => {
  const [svg, out, size] = process.argv.slice(2);
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: +size, height: +size } });
  const fs = require('fs');
  await p.setContent(`<html><body style="margin:0">${fs.readFileSync(svg,'utf8').replace('width="1024" height="1024"',`width="${size}" height="${size}"`)}</body></html>`);
  await p.screenshot({ path: out, omitBackground: false });
  await b.close();
})();
