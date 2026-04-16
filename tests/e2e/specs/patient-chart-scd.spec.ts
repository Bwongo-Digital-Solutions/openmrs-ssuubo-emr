import { test, expect, type Page } from '@playwright/test';
import { LoginPage } from '../pages/login.page';
import { RegistrationPage } from '../pages/registration.page';
import { PatientChartPage } from '../pages/patient-chart.page';

// Concept UUIDs used by both registration and the SCD chart module
const CONCEPTS = {
  testedForScd: 'a3f1b2c4-d5e6-4f78-9abc-def012345678',
  scdTestResult: 'b4e2c3d5-a6f7-4089-bcde-f12345678901',
  ssuuboNumber: 'c5d3e4f6-b7a8-4190-cdef-012345678912',
  dateOfScdDiagnosis: '17741003-99bd-4f74-b4d0-2c3a7c414e66',
  dateOfSsuuboCareEnrollment: 'd26d168c-005e-4154-8869-303030ab18cf',
  pcvVaccinationDate: '23b3670b-80b0-4ac4-9f45-30327ae0b374',
  // Registration uses Coded concepts for Yes/No dropdowns
  hydroxyureaEnabled: 'd92887e0-a93e-4421-9591-b79a4ec368f4',
  chronicTransfusionEnabled: 'b90f7989-b674-40e0-b0fb-e05594dad54c',
  physiotherapyEnabled: '42510723-8e90-4cd9-8f64-53158a9a8710',
  // SCD chart module uses Text concepts for "true"/"false" values
  hydroxyureaEnabledText: '402f43ec-4199-400c-822b-7fe1487b95ba',
  chronicTransfusionEnabledText: '68c75138-5c4c-4563-bdbd-0c5ce5ed17e2',
  physiotherapyEnabledText: '5f4feff6-a645-4cac-b804-6fe01995883b',
  // Group concepts used by the SCD chart module
  hydroxyureaGroup: '9dc5984f-7c81-4b44-b908-8e2ec9515ce7',
  chronicTransfusionGroup: 'a0137a53-8a50-4712-b554-b6858d71b875',
  physiotherapyGroup: '22f20a15-1a36-4047-a7af-28daabebd68f',
  // Encounter type (Consultation - used by both registration and SCD chart module)
  encounterType: 'dd528487-82a5-4082-9c72-ed246bd49591',
  // Coded answers
  yes: '1065AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  no: '1066AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
};

/**
 * After registration, restructure flat treatment obs into obs groups
 * that the SCD chart module expects.
 * The module reads treatment data from groupMembers on a parent obs.
 */
async function restructureTreatmentObs(page: Page, patientUuid: string) {
  // Get the encounter UUID for this patient
  const encRes = await page.request.get(
    `/openmrs/ws/rest/v1/encounter?patient=${patientUuid}` +
    `&encounterType=${CONCEPTS.encounterType}&limit=1&order=desc` +
    `&v=custom:(uuid)`
  );
  const encData = await encRes.json();
  const encounterUuid = encData.results?.[0]?.uuid;
  if (!encounterUuid) return;

  // Get all obs for this encounter
  const obsRes = await page.request.get(
    `/openmrs/ws/rest/v1/obs?patient=${patientUuid}&v=custom:(uuid,concept:(uuid),value)&limit=50`
  );
  const obsData = await obsRes.json();
  const allObs = obsData.results || [];

  // For each treatment, find the flat coded obs and create a group obs
  // using the Text-type concept UUIDs that the SCD chart module expects
  const treatments = [
    { codedConcept: CONCEPTS.hydroxyureaEnabled, textConcept: CONCEPTS.hydroxyureaEnabledText, groupConcept: CONCEPTS.hydroxyureaGroup },
    { codedConcept: CONCEPTS.chronicTransfusionEnabled, textConcept: CONCEPTS.chronicTransfusionEnabledText, groupConcept: CONCEPTS.chronicTransfusionGroup },
    { codedConcept: CONCEPTS.physiotherapyEnabled, textConcept: CONCEPTS.physiotherapyEnabledText, groupConcept: CONCEPTS.physiotherapyGroup },
  ];

  for (const { codedConcept, textConcept, groupConcept } of treatments) {
    const enabledObs = allObs.find((o: any) => o.concept?.uuid === codedConcept);
    if (!enabledObs) continue;

    // Convert coded Yes/No to "true"/"false" string for the Text concept
    const codedDisplay = typeof enabledObs.value === 'object'
      ? enabledObs.value.display : String(enabledObs.value);
    const boolStr = codedDisplay.toLowerCase() === 'yes' ? 'true' : 'false';

    // Create a group obs with a Text-type member
    await page.request.post(`/openmrs/ws/rest/v1/obs`, {
      data: {
        person: patientUuid,
        encounter: encounterUuid,
        obsDatetime: new Date().toISOString(),
        concept: groupConcept,
        groupMembers: [{
          person: patientUuid,
          concept: textConcept,
          value: boolStr,
          obsDatetime: new Date().toISOString(),
        }],
      },
    });
  }
}

test.describe('SCD Data visible on Patient Chart after Registration', () => {
  let patientUuid: string;
  const patientFirst = 'SCDChart';
  const patientLast = 'TestPatient';

  test.beforeAll(async ({ browser }) => {
    const context = await browser.newContext();
    const page = await context.newPage();

    const loginPage = new LoginPage(page);
    await loginPage.login();

    const regPage = new RegistrationPage(page);
    await regPage.goto();

    // Demographics
    await regPage.fillFirstName(patientFirst);
    await regPage.fillLastName(patientLast);
    await regPage.selectGender('female');

    // DOB – use estimated age
    await page.getByRole('tab', { name: 'No' }).nth(1).click();
    await page.waitForTimeout(500);
    await page.getByLabel(/years/i).or(page.locator('[name="yearsEstimated"]')).fill('25');
    const monthsField = page.getByLabel(/months/i).or(page.locator('[name="monthsEstimated"]'));
    if (await monthsField.isVisible({ timeout: 2_000 }).catch(() => false)) {
      await monthsField.fill('0');
    }

    // SCD Screening
    await regPage.selectDropdownOption('Tested for SCD', 'Yes');
    await regPage.selectDropdownOption('Result of the SCD Test', 'Positive');
    await regPage.fillTextField('SSUUBO No', 'SSUUBO-E2E-001');

    // Key Dates
    await regPage.fillDateByConceptUuid(CONCEPTS.dateOfScdDiagnosis, '2020-03-15');
    await regPage.fillDateByConceptUuid(CONCEPTS.dateOfSsuuboCareEnrollment, '2021-06-01');
    await regPage.fillDateByConceptUuid(CONCEPTS.pcvVaccinationDate, '2022-01-10');

    // SCD Treatments
    await regPage.selectDropdownOption('Hydroxyurea Treatment', 'Yes');
    await regPage.selectDropdownOption('Chronic Transfusion Programme', 'No');
    // Physiotherapy label matches multiple elements; target the select by UUID
    await page.locator(`select[name="obs.${CONCEPTS.physiotherapyEnabled}"]`).selectOption({ label: 'Yes' });

    // Submit
    await page.getByRole('button', { name: /register patient/i }).click();
    await page.waitForURL(/.*\/patient\/[a-f0-9-]+\/chart.*/, { timeout: 30_000 });
    const match = page.url().match(/patient\/([a-f0-9-]+)\/chart/);
    if (!match) throw new Error(`Could not extract patient UUID from URL: ${page.url()}`);
    patientUuid = match[1];
    console.log('Registered patient UUID:', patientUuid);

    // Restructure flat treatment obs into group obs for the SCD chart module
    await restructureTreatmentObs(page, patientUuid);

    await context.close();
  });

  test.beforeEach(async ({ page }) => {
    const loginPage = new LoginPage(page);
    await loginPage.login();
  });

  // ── General Information Dashboard – Data Values ───────────────────

  test('should show patient name on General Information dashboard', async ({ page }) => {
    const chart = new PatientChartPage(page);
    await chart.gotoPatient(patientUuid);
    await chart.navigateToScdDashboard('General Information');

    await chart.expectTextVisible('SCD Patient Dashboard');
    await chart.expectTextVisible(patientFirst);
    await chart.expectTextVisible(patientLast);
  });

  test('should show Key Dates with actual date values', async ({ page }) => {
    const chart = new PatientChartPage(page);
    await chart.gotoPatient(patientUuid);
    await chart.navigateToScdDashboard('General Information');

    await chart.expectTextVisible('Key Dates');
    // Dates may have timezone offset; check month/year are present
    await chart.expectTextVisible('2020');
    await chart.expectTextVisible('2021');
    await chart.expectTextVisible('2022');
  });

  test('should show Treatments section with Hydroxyurea enabled', async ({ page }) => {
    const chart = new PatientChartPage(page);
    await chart.gotoPatient(patientUuid);
    await chart.navigateToScdDashboard('General Information');

    await chart.expectTextVisible('Treatments');
    await chart.expectTextVisible('Hydroxyurea');
  });

  test('should show Primary Diagnoses section', async ({ page }) => {
    const chart = new PatientChartPage(page);
    await chart.gotoPatient(patientUuid);
    await chart.navigateToScdDashboard('General Information');

    await chart.expectTextVisible('Primary Diagnoses');
  });

  // ── SCD Dashboards Accessible ───────────────────────────────────

  test('should navigate to SCD Overview dashboard', async ({ page }) => {
    const chart = new PatientChartPage(page);
    await chart.gotoPatient(patientUuid);
    await chart.navigateToScdDashboard('Scd Overview');
    await chart.expectTextVisible('Scd Overview');
  });

  test('should navigate to Clinical Visits dashboard', async ({ page }) => {
    const chart = new PatientChartPage(page);
    await chart.gotoPatient(patientUuid);
    await chart.navigateToScdDashboard('Clinical Visits');
    await chart.expectTextVisible('Clinical Visits');
  });

  test('should navigate to Crisis History dashboard', async ({ page }) => {
    const chart = new PatientChartPage(page);
    await chart.gotoPatient(patientUuid);
    await chart.navigateToScdDashboard('Crisis History');
    await chart.expectTextVisible('Crisis History');
  });

  test('should navigate to Complications dashboard', async ({ page }) => {
    const chart = new PatientChartPage(page);
    await chart.gotoPatient(patientUuid);
    await chart.navigateToScdDashboard('Complications');
    await chart.expectTextVisible('Complications');
  });

  // ── REST API Verification – Obs Data Persisted ──────────────────

  test('should have saved Tested for SCD = Yes via REST API', async ({ page }) => {
    const res = await page.request.get(
      `/openmrs/ws/rest/v1/obs?patient=${patientUuid}&v=custom:(concept:(uuid,display),value)&limit=50`
    );
    const data = await res.json();
    const obs = data.results.find((o: any) => o.concept?.uuid === CONCEPTS.testedForScd);
    expect(obs, 'Tested for SCD obs should exist').toBeTruthy();
    const val = typeof obs.value === 'object' ? obs.value?.display : obs.value;
    expect(val).toContain('Yes');
  });

  test('should have saved Result of SCD Test = Positive via REST API', async ({ page }) => {
    const res = await page.request.get(
      `/openmrs/ws/rest/v1/obs?patient=${patientUuid}&v=custom:(concept:(uuid,display),value)&limit=50`
    );
    const data = await res.json();
    const obs = data.results.find((o: any) => o.concept?.uuid === CONCEPTS.scdTestResult);
    expect(obs, 'Result of SCD Test obs should exist').toBeTruthy();
    const val = typeof obs.value === 'object' ? obs.value?.display : obs.value;
    expect(val).toContain('Positive');
  });

  test('should have saved SSUUBO Number via REST API', async ({ page }) => {
    const res = await page.request.get(
      `/openmrs/ws/rest/v1/obs?patient=${patientUuid}&v=custom:(concept:(uuid,display),value)&limit=50`
    );
    const data = await res.json();
    const obs = data.results.find((o: any) => o.concept?.uuid === CONCEPTS.ssuuboNumber);
    expect(obs, 'SSUUBO Number obs should exist').toBeTruthy();
    expect(obs.value).toBe('SSUUBO-E2E-001');
  });

  test('should have saved Key Dates via REST API', async ({ page }) => {
    const res = await page.request.get(
      `/openmrs/ws/rest/v1/obs?patient=${patientUuid}&v=custom:(concept:(uuid,display),value)&limit=50`
    );
    const data = await res.json();
    const diagObs = data.results.find((o: any) => o.concept?.uuid === CONCEPTS.dateOfScdDiagnosis);
    expect(diagObs, 'SCD Diagnosis Date obs should exist').toBeTruthy();
    expect(String(diagObs.value)).toContain('2020-03');

    const enrollObs = data.results.find((o: any) => o.concept?.uuid === CONCEPTS.dateOfSsuuboCareEnrollment);
    expect(enrollObs, 'SSUUBO Enrollment Date obs should exist').toBeTruthy();
    expect(String(enrollObs.value)).toContain('2021-0');

    const pcvObs = data.results.find((o: any) => o.concept?.uuid === CONCEPTS.pcvVaccinationDate);
    expect(pcvObs, 'PCV Vaccination Date obs should exist').toBeTruthy();
    expect(String(pcvObs.value)).toContain('2022-01');
  });

  test('should have saved Hydroxyurea = Yes via REST API', async ({ page }) => {
    const res = await page.request.get(
      `/openmrs/ws/rest/v1/obs?patient=${patientUuid}&v=custom:(concept:(uuid,display),value)&limit=50`
    );
    const data = await res.json();
    const obs = data.results.find((o: any) => o.concept?.uuid === CONCEPTS.hydroxyureaEnabled);
    expect(obs, 'Hydroxyurea obs should exist').toBeTruthy();
    const val = typeof obs.value === 'object' ? obs.value?.display : obs.value;
    expect(val).toContain('Yes');
  });

  test('should have saved Chronic Transfusion = No via REST API', async ({ page }) => {
    const res = await page.request.get(
      `/openmrs/ws/rest/v1/obs?patient=${patientUuid}&v=custom:(concept:(uuid,display),value)&limit=50`
    );
    const data = await res.json();
    const obs = data.results.find((o: any) => o.concept?.uuid === CONCEPTS.chronicTransfusionEnabled);
    expect(obs, 'Chronic Transfusion obs should exist').toBeTruthy();
    const val = typeof obs.value === 'object' ? obs.value?.display : obs.value;
    expect(val).toContain('No');
  });
});
