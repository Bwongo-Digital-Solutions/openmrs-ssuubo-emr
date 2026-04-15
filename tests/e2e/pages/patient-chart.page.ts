import { type Page, expect } from '@playwright/test';

// Maps dashboard display names to their config paths
const DASHBOARD_PATHS: Record<string, string> = {
  'General Information': 'scd-general-info',
  'Scd Overview': 'scd-overview',
  'Clinical Visits': 'scd-clinical-visits',
  'Crisis History': 'scd-crisis-history',
  'Treatments': 'scd-treatments',
  'Lab Monitoring': 'scd-labs',
  'Complications': 'scd-complications',
  'Family Screening': 'scd-family-screening',
};

export class PatientChartPage {
  private patientUuid = '';

  constructor(private page: Page) {}

  async gotoPatient(patientUuid: string) {
    this.patientUuid = patientUuid;
    await this.page.goto(`./patient/${patientUuid}/chart`);
    await this.page.waitForLoadState('networkidle');
  }

  async navigateToScdDashboard(dashboardName: string) {
    const path = DASHBOARD_PATHS[dashboardName];
    if (!path) throw new Error(`Unknown dashboard: ${dashboardName}`);
    await this.page.goto(`./patient/${this.patientUuid}/chart/${path}`);
    await this.page.waitForLoadState('networkidle');
    await this.page.waitForTimeout(3_000);
  }

  async expectEncounterListHeader(headerText: string) {
    await expect(
      this.page.getByRole('columnheader', { name: new RegExp(headerText, 'i') })
        .or(this.page.getByText(headerText))
    ).toBeVisible({ timeout: 10_000 });
  }

  async expectCellValueInTable(value: string) {
    await expect(
      this.page.getByRole('cell', { name: new RegExp(value, 'i') })
        .or(this.page.getByText(value, { exact: false }))
        .first()
    ).toBeVisible({ timeout: 10_000 });
  }

  async expectTextVisible(text: string) {
    await expect(
      this.page.getByText(text, { exact: false }).first()
    ).toBeVisible({ timeout: 10_000 });
  }

  async getBodyText(): Promise<string> {
    return this.page.locator('body').innerText();
  }
}
