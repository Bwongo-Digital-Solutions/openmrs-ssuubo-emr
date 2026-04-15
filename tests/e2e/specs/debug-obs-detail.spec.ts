import { test } from '@playwright/test';
import { LoginPage } from '../pages/login.page';
import { RegistrationPage } from '../pages/registration.page';

test('debug: fill ALL SCD fields including dates and verify dashboard', async ({ page }) => {
  const loginPage = new LoginPage(page);
  await loginPage.login();

  const regPage = new RegistrationPage(page);
  await regPage.goto();

  await regPage.fillFirstName('FullSCD');
  await regPage.fillLastName('DataTest');
  await regPage.selectGender('female');

  // DOB
  await page.getByRole('tab', { name: 'No' }).nth(1).click();
  await page.waitForTimeout(500);
  await page.getByLabel(/years/i).or(page.locator('[name="yearsEstimated"]')).fill('20');

  // SCD Screening
  await regPage.selectDropdownOption('Tested for SCD', 'Yes');
  await regPage.selectDropdownOption('Result of the SCD Test', 'Positive');
  await regPage.fillTextField('SSUUBO No', 'SSUUBO-FULL-001');

  // Key Dates - fill using the hidden input[type=date] elements
  const dateFields = [
    { uuid: '17741003-99bd-4f74-b4d0-2c3a7c414e66', value: '2020-03-15', label: 'SCD Diagnosis' },
    { uuid: 'd26d168c-005e-4154-8869-303030ab18cf', value: '2021-06-01', label: 'SSUUBO Enrollment' },
    { uuid: '23b3670b-80b0-4ac4-9f45-30327ae0b374', value: '2022-01-10', label: 'PCV Vaccination' },
  ];
  for (const { uuid, value, label } of dateFields) {
    // Try the text input first (type=text with name=obs.UUID)
    const textInput = page.locator(`input[type="text"][name="obs.${uuid}"]`);
    if (await textInput.isVisible({ timeout: 2_000 }).catch(() => false)) {
      await textInput.scrollIntoViewIfNeeded();
      await textInput.click();
      // Type date in dd/MM/yyyy format
      const [y, m, d] = value.split('-');
      await textInput.fill(`${d}/${m}/${y}`);
      await page.keyboard.press('Tab');
      console.log(`Filled ${label} via text input: ${d}/${m}/${y}`);
    } else {
      // Try native date input
      const dateInput = page.locator(`input[type="date"][name="obs.${uuid}"]`);
      await dateInput.fill(value);
      console.log(`Filled ${label} via date input: ${value}`);
    }
  }

  // Treatments - select coded answers
  await regPage.selectDropdownOption('Hydroxyurea Treatment', 'Yes');
  await regPage.selectDropdownOption('Chronic Transfusion Programme', 'No');

  await page.waitForTimeout(1000);
  await page.screenshot({ path: 'debug-filled-form.png', fullPage: true });

  // Submit
  await page.getByRole('button', { name: /register patient/i }).click();
  await page.waitForURL(/.*\/patient\/[a-f0-9-]+\/chart.*/, { timeout: 30_000 });
  const match = page.url().match(/patient\/([a-f0-9-]+)\/chart/);
  const uuid = match![1];
  console.log('Registered patient UUID:', uuid);

  // Check obs detail
  const obsRes = await page.request.get(
    `/openmrs/ws/rest/v1/obs?patient=${uuid}&v=full&limit=50`
  );
  const obsData = await obsRes.json();
  console.log('=== Patient obs ===');
  for (const obs of obsData.results || []) {
    const conceptDisplay = obs.concept?.display;
    const valueType = typeof obs.value;
    let valueDetail;
    if (valueType === 'object' && obs.value !== null) {
      valueDetail = `CODED: ${obs.value.display}`;
    } else {
      valueDetail = `${obs.value}`;
    }
    console.log(`  [${conceptDisplay}] => ${valueDetail}`);
  }

  // Navigate to General Info dashboard
  await page.goto(`./patient/${uuid}/chart/scd-general-info`);
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(5_000);
  await page.screenshot({ path: 'debug-dashboard-full.png', fullPage: true });
  const bodyText = await page.locator('body').innerText();
  console.log('=== Dashboard text ===');
  console.log(bodyText.substring(0, 3000));
});
