const fs = require('node:fs');
const path = require('node:path');
// Install Playwright locally, or point NODE_PATH at an existing installation.
const { chromium } = require('playwright');

(async () => {
  const destination = path.resolve(__dirname, '../pdf/ChessEver_Publishing_Guide.pdf');
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  const executablePath = process.env.CHESSEVER_PDF_CHROME_PATH;
  const browser = await chromium.launch({
    ...(executablePath ? { executablePath } : {}),
    headless: true,
  });
  try {
    const page = await browser.newPage();
    await page.setContent(fs.readFileSync(path.join(__dirname, 'publishing-guide.html'), 'utf8'));
    await page.emulateMedia({ media: 'print' });
    await page.evaluate(() => document.fonts.ready);
    await page.pdf({
      path: destination,
      format: 'A4',
      preferCSSPageSize: true,
      printBackground: true,
      displayHeaderFooter: true,
      headerTemplate: '<span></span>',
      footerTemplate: '<div style="font-family:Arial,sans-serif;font-size:9px;width:100%;padding:0 64px;color:#62625d;display:flex;justify-content:space-between"><span>ChessEver · Publishing guide · 13 October 2026</span><span><span class="pageNumber"></span> / <span class="totalPages"></span></span></div>',
    });
    console.log(destination);
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
