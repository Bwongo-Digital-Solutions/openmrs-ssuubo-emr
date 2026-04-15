import { type Page, type Locator, expect } from '@playwright/test';

export class RegistrationPage {
  readonly page: Page;

  // Section headings
  readonly scdScreeningSection: Locator;
  readonly scdKeyDatesSection: Locator;
  readonly scdTreatmentsSection: Locator;
  readonly primaryDiagnosesSection: Locator;

  constructor(page: Page) {
    this.page = page;
    this.scdScreeningSection = page.getByText('SCD Screening');
    this.scdKeyDatesSection = page.getByText('SCD Key Dates');
    this.scdTreatmentsSection = page.getByText('SCD Treatments');
    this.primaryDiagnosesSection = page.getByText('Primary Diagnoses');
  }

  async goto() {
    await this.page.goto('./patient-registration');
    await this.page.waitForLoadState('networkidle');
  }

  // ── Demographics helpers ──────────────────────────────────────────

  async fillFirstName(name: string) {
    await this.page.locator('#givenName').fill(name);
  }

  async fillLastName(name: string) {
    await this.page.locator('#familyName').fill(name);
  }

  async selectGender(gender: 'male' | 'female') {
    await this.page.getByLabel(gender === 'male' ? 'Male' : 'Female').click({ force: true });
  }

  async fillBirthYear(year: string) {
    // Toggle to estimated DOB mode if available, then fill just the year
    const estimatedToggle = this.page.getByText(/no/i).or(this.page.getByLabel(/estimated/i));
    if (await estimatedToggle.isVisible({ timeout: 3_000 }).catch(() => false)) {
      await estimatedToggle.click();
    }
    const yearField = this.page.getByLabel(/year/i).or(this.page.locator('[name="yearsEstimated"]'));
    if (await yearField.isVisible({ timeout: 3_000 }).catch(() => false)) {
      await yearField.fill(year);
    }
  }

  // ── SCD Screening helpers ─────────────────────────────────────────

  getFieldByLabel(label: string): Locator {
    return this.page.getByLabel(label);
  }

  getDropdownByLabel(label: string): Locator {
    return this.page.getByLabel(label);
  }

  async selectDropdownOption(fieldLabel: string, optionText: string) {
    const field = this.page.getByLabel(new RegExp(fieldLabel, 'i'));
    await field.scrollIntoViewIfNeeded();
    const tagName = await field.evaluate(el => el.tagName.toLowerCase());
    if (tagName === 'select') {
      await field.selectOption({ label: optionText });
    } else {
      await field.fill(optionText);
    }
  }

  async fillTextField(label: string, value: string) {
    const field = this.page.getByLabel(new RegExp(label, 'i'));
    await field.fill(value);
  }

  // ── Date field helpers ────────────────────────────────────────────

  async fillDateField(label: string, dateStr: string) {
    // O3 date fields use Carbon date pickers or native inputs
    const dateInput = this.page.getByLabel(new RegExp(label, 'i'));
    if (await dateInput.isVisible({ timeout: 5_000 }).catch(() => false)) {
      await dateInput.fill(dateStr);
    }
  }

  async fillDateByConceptUuid(conceptUuid: string, isoDate: string) {
    // Registration date fields have a hidden input[type=date][name=obs.UUID]
    const dateInput = this.page.locator(`input[type="date"][name="obs.${conceptUuid}"]`);
    await dateInput.fill(isoDate);
  }

  // ── Verification helpers ──────────────────────────────────────────

  async expectSectionVisible(sectionName: string) {
    await expect(
      this.page.getByRole('heading', { name: sectionName }).first()
    ).toBeVisible({ timeout: 15_000 });
  }

  async expectFieldVisible(label: string) {
    const field = this.page.getByText(label, { exact: false });
    await expect(field.first()).toBeVisible({ timeout: 10_000 });
  }

  async expectFieldsVisibleInSection(fieldLabels: string[]) {
    for (const label of fieldLabels) {
      await this.expectFieldVisible(label);
    }
  }

  // ── Form submission ───────────────────────────────────────────────

  async clickRegisterPatient() {
    await this.page.getByRole('button', { name: /register patient/i }).click();
  }

  async clickSubmit() {
    const submitButton = this.page.getByRole('button', { name: /register patient/i })
      .or(this.page.getByRole('button', { name: /submit/i }));
    await submitButton.click();
  }
}
