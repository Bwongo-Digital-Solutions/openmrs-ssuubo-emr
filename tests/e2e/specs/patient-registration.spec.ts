import { test, expect } from '@playwright/test';
import { LoginPage } from '../pages/login.page';
import { RegistrationPage } from '../pages/registration.page';

test.describe('SSUUBO Patient Registration – SCD Fields', () => {
  let registrationPage: RegistrationPage;

  test.beforeEach(async ({ page }) => {
    const loginPage = new LoginPage(page);
    await loginPage.login();
    registrationPage = new RegistrationPage(page);
    await registrationPage.goto();
  });

  // ── Section visibility ────────────────────────────────────────────

  test('should display the Basic Info section', async () => {
    await registrationPage.expectSectionVisible('Basic Info');
  });

  test('should display the SCD Screening section', async () => {
    await registrationPage.expectSectionVisible('SCD Screening');
  });

  test('should display the SCD Key Dates section', async () => {
    await registrationPage.expectSectionVisible('SCD Key Dates');
  });

  test('should display the SCD Treatments section', async () => {
    await registrationPage.expectSectionVisible('SCD Treatments');
  });

  test('should display the Primary Diagnoses section', async () => {
    await registrationPage.expectSectionVisible('Primary Diagnoses');
  });

  // ── Demographics fields ───────────────────────────────────────────

  test('should display Name and Date of Birth fields in Basic Info', async ({ page }) => {
    await registrationPage.expectFieldVisible('First Name');
    await registrationPage.expectFieldVisible('Family Name');
    await registrationPage.expectFieldVisible('Date of birth');
  });

  // ── SCD Screening fields ─────────────────────────────────────────

  test('should display Tested for SCD dropdown with Yes/No options', async () => {
    await registrationPage.expectFieldVisible('Tested for SCD');
  });

  test('should display Result of the SCD Test dropdown with N/A, Negative, Positive', async () => {
    await registrationPage.expectFieldVisible('Result of the SCD Test');
  });

  test('should display SSUUBO No. text field', async () => {
    await registrationPage.expectFieldVisible('SSUUBO No.');
  });

  // ── SCD Key Dates fields ──────────────────────────────────────────

  test('should display Date of SCD Diagnosis date picker', async () => {
    await registrationPage.expectFieldVisible('Date of SCD Diagnosis');
  });

  test('should display Date of SSUUBO Care Enrollment date picker', async () => {
    await registrationPage.expectFieldVisible('Date of SSUUBO Care Enrollment');
  });

  test('should display PCV Vaccination Date date picker', async () => {
    await registrationPage.expectFieldVisible('PCV Vaccination Date');
  });

  // ── SCD Treatments fields ─────────────────────────────────────────

  test('should display Hydroxyurea Treatment and date fields', async () => {
    await registrationPage.expectFieldsVisibleInSection([
      'Hydroxyurea Treatment',
      'Hydroxyurea Start Date',
      'Hydroxyurea Stop Date',
    ]);
  });

  test('should display Chronic Transfusion Programme and date fields', async () => {
    await registrationPage.expectFieldsVisibleInSection([
      'Chronic Transfusion Programme',
      'Chronic Transfusion Start Date',
      'Chronic Transfusion Stop Date',
    ]);
  });

  test('should display Physiotherapy and date fields', async () => {
    await registrationPage.expectFieldsVisibleInSection([
      'Physiotherapy',
      'Physiotherapy Start Date',
      'Physiotherapy Stop Date',
    ]);
  });

  // ── Primary Diagnoses fields ──────────────────────────────────────

  test('should display all primary diagnosis date fields', async () => {
    await registrationPage.expectFieldsVisibleInSection([
      'SCD non-HU',
      'SCD on HU',
      'Conditional TCD',
      'Abnormal TCD',
      'Stroke',
      'Splenomegaly',
      'Chronic Sequestration',
      'Osteonecrosis',
      'Other – Diagnosed',
      'Other Complication Description',
    ]);
  });

  // ── Interaction tests ─────────────────────────────────────────────

  test('should allow filling in the SCD Screening fields', async ({ page }) => {
    await registrationPage.fillFirstName('TestSCD');
    await registrationPage.fillLastName('Patient');

    // Select "Tested for SCD" → Yes
    await registrationPage.selectDropdownOption('Tested for SCD', 'Yes');

    // Select "Result of the SCD Test" → Positive
    await registrationPage.selectDropdownOption('Result of the SCD Test', 'Positive');

    // Fill SSUUBO No.
    await registrationPage.fillTextField('SSUUBO No', 'SSUUBO-2025-001');
  });

  test('should allow selecting Hydroxyurea Treatment option', async () => {
    await registrationPage.selectDropdownOption('Hydroxyurea Treatment', 'Yes');
  });

  test('should allow selecting Chronic Transfusion Programme option', async () => {
    await registrationPage.selectDropdownOption('Chronic Transfusion Programme', 'Yes');
  });

  test('should allow selecting Physiotherapy option', async ({ page }) => {
    const field = page.getByLabel('Physiotherapy', { exact: true }).or(
      page.getByLabel('Physiotherapy (optional)', { exact: true })
    );
    await field.scrollIntoViewIfNeeded();
    await field.fill('Yes');
  });

  test('should allow entering Other Complication Description text', async ({ page }) => {
    const descField = page.getByLabel(/Other Complication Description/i);
    await descField.scrollIntoViewIfNeeded();
    await descField.fill('Rare cardiac complication');
    await expect(descField).toHaveValue('Rare cardiac complication');
  });

  // ── Full registration flow ────────────────────────────────────────

  test('should complete full SCD patient registration with all fields', async ({ page }) => {
    // Demographics
    await registrationPage.fillFirstName('Jane');
    await registrationPage.fillLastName('Nakato');
    await registrationPage.selectGender('female');

    // SCD Screening
    await registrationPage.selectDropdownOption('Tested for SCD', 'Yes');
    await registrationPage.selectDropdownOption('Result of the SCD Test', 'Positive');
    await registrationPage.fillTextField('SSUUBO No', 'SSUUBO-2025-100');

    // SCD Treatments – Hydroxyurea
    await registrationPage.selectDropdownOption('Hydroxyurea Treatment', 'Yes');

    // SCD Treatments – Chronic Transfusion
    await registrationPage.selectDropdownOption('Chronic Transfusion Programme', 'No');

    // SCD Treatments – Physiotherapy
    const physioField = page.getByLabel('Physiotherapy', { exact: true }).or(
      page.getByLabel('Physiotherapy (optional)', { exact: true })
    );
    await physioField.scrollIntoViewIfNeeded();
    await physioField.fill('Yes');

    // Other diagnosis description
    const descField = page.getByLabel(/Other Complication Description/i);
    await descField.scrollIntoViewIfNeeded();
    await descField.fill('Pulmonary hypertension');

    // Verify the register button is present
    const submitBtn = page.getByRole('button', { name: /register patient/i });
    await expect(submitBtn).toBeVisible();
  });
});
