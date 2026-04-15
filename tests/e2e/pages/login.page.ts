import { type Page, expect } from '@playwright/test';

export class LoginPage {
  constructor(private page: Page) {}

  async goto() {
    await this.page.goto('./login');
    await this.page.waitForLoadState('networkidle');
  }

  async login(
    username = process.env.OPENMRS_USER ?? 'admin',
    password = process.env.OPENMRS_PASSWORD ?? 'Admin123',
  ) {
    await this.goto();

    const usernameField = this.page.locator('#username');
    await usernameField.fill(username);
    await this.page.getByRole('button', { name: /continue/i }).click();

    const passwordField = this.page.locator('#password');
    await passwordField.fill(password);
    await this.page.getByRole('button', { name: /log in/i }).click();

    // Handle location selection page
    await this.page.waitForLoadState('networkidle');
    await this.page.getByText('Outpatient Clinic').click({ timeout: 15_000 });

    const confirmButton = this.page.getByRole('button', { name: /confirm/i });
    await confirmButton.click({ timeout: 10_000 });

    // Wait for navigation to home page
    await this.page.waitForURL('**/home', { timeout: 60_000 });
  }
}
