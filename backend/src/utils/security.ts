export class SecurityUtils {
  /**
   * Validates password strength:
   * - At least 12 characters long
   * - Contains at least 1 uppercase letter
   * - Contains at least 1 lowercase letter
   * - Contains at least 1 number
   * - Contains at least 1 special character
   */
  public static validatePasswordStrength(password: string): boolean {
    if (password.length < 12) return false;
    const hasUpper = /[A-Z]/.test(password);
    const hasLower = /[a-z]/.test(password);
    const hasNumber = /[0-9]/.test(password);
    const hasSpecial = /[^A-Za-z0-9]/.test(password);
    return hasUpper && hasLower && hasNumber && hasSpecial;
  }
}
