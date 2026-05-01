const { chromium } = require('playwright');

const NOTEBOOK_URL = 'https://www.kaggle.com/code/marxchavez/predial-vision-mx-nicolas-romero/edit';

(async () => {
  const browser = await chromium.launch({ headless: false, slowMo: 300 });
  const page = await browser.newPage({ viewport: { width: 1400, height: 900 } });

  console.log('1. Opening Kaggle notebook...');
  await page.goto(NOTEBOOK_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });

  // Login check
  if (page.url().includes('account/login') || page.url().includes('sign-in')) {
    console.log('   LOGIN REQUIRED - log in manually in the browser');
    await page.waitForURL('**/edit**', { timeout: 180000 });
  }

  await page.waitForTimeout(8000);
  await page.screenshot({ path: '/tmp/kaggle-1.png' });
  console.log('2. Editor loaded. Screenshot: /tmp/kaggle-1.png');
  console.log('   Browser is open. Configure manually:');
  console.log('   - Settings > Accelerator > GPU T4 x2');
  console.log('   - Input > remove/re-add dataset');
  console.log('   - Run All');
  console.log('   Keeping browser open 10 min...');

  await page.waitForTimeout(600000);
  await browser.close();
})();
