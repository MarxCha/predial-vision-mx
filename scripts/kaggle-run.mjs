// Playwright script to configure and run Kaggle notebook
// Usage: npx playwright test scripts/kaggle-run.mjs
import { chromium } from 'playwright';

const NOTEBOOK_URL = 'https://www.kaggle.com/code/marxchavez/predial-vision-mx-nicolas-romero/edit';

(async () => {
  const browser = await chromium.launch({ headless: false, slowMo: 500 });
  const context = await browser.newContext({
    storageState: undefined,
    viewport: { width: 1400, height: 900 }
  });
  const page = await context.newPage();

  console.log('1. Opening Kaggle notebook editor...');
  await page.goto(NOTEBOOK_URL, { waitUntil: 'networkidle', timeout: 60000 });

  // Check if we need to login
  if (page.url().includes('account/login')) {
    console.log('   Need to login - please login manually in the browser window');
    console.log('   Waiting up to 120s for login...');
    await page.waitForURL('**/code/**', { timeout: 120000 });
    console.log('   Login successful!');
  }

  // Wait for editor to load
  await page.waitForTimeout(5000);
  console.log('2. Notebook editor loaded');

  // Take screenshot for debug
  await page.screenshot({ path: '/tmp/kaggle-step1.png' });
  console.log('   Screenshot: /tmp/kaggle-step1.png');

  // Try to find and click Settings/Accelerator
  console.log('3. Looking for Settings panel...');

  // Click on Settings tab in right panel
  const settingsTab = page.locator('text=Settings').first();
  if (await settingsTab.isVisible()) {
    await settingsTab.click();
    await page.waitForTimeout(2000);
    console.log('   Settings panel opened');
  }

  // Look for Accelerator dropdown
  const acceleratorLabel = page.locator('text=Accelerator').first();
  if (await acceleratorLabel.isVisible()) {
    console.log('   Found Accelerator setting');
    // Click the dropdown near it
    const acceleratorSection = acceleratorLabel.locator('..').locator('..');
    const dropdown = acceleratorSection.locator('select, [role="listbox"], button').first();
    if (await dropdown.isVisible()) {
      await dropdown.click();
      await page.waitForTimeout(1000);
      // Select GPU T4
      const gpuOption = page.locator('text=GPU T4').first();
      if (await gpuOption.isVisible()) {
        await gpuOption.click();
        console.log('   GPU T4 selected!');
      }
    }
  }

  await page.screenshot({ path: '/tmp/kaggle-step2.png' });
  console.log('   Screenshot: /tmp/kaggle-step2.png');

  // Look for Run All button
  console.log('4. Looking for Run All...');
  const runAll = page.locator('text=Run All').first();
  if (await runAll.isVisible()) {
    console.log('   Found Run All button - clicking...');
    await runAll.click();
    console.log('   Run All clicked!');
  } else {
    console.log('   Run All not found - check screenshots');
  }

  await page.waitForTimeout(5000);
  await page.screenshot({ path: '/tmp/kaggle-step3.png' });
  console.log('   Screenshot: /tmp/kaggle-step3.png');

  console.log('\nDone! Check screenshots in /tmp/kaggle-step*.png');
  console.log('Browser stays open - close manually when ready');

  // Keep browser open for manual interaction
  await page.waitForTimeout(300000); // 5 min
  await browser.close();
})();
