/** Phone normalization mirrors public.normalize_phone() in the database. */
export function normalizePhone(input: string | null | undefined): string | null {
  if (!input) return null;
  let digits = String(input).replace(/[^0-9+]/g, "");
  if (digits.startsWith("+")) {
    digits = "+" + digits.slice(1).replace(/[^0-9]/g, "");
  } else {
    digits = digits.replace(/[^0-9]/g, "");
    if (digits.length === 10) digits = "+91" + digits;
    else if (digits.length === 11 && digits.startsWith("0")) digits = "+91" + digits.slice(1);
    else if (digits.length === 12 && digits.startsWith("91")) digits = "+" + digits;
    else if (digits.length === 13 && digits.startsWith("091")) digits = "+91" + digits.slice(3);
    else digits = "+" + digits;
  }
  return /^\+[1-9][0-9]{7,14}$/.test(digits) ? digits : null;
}

export function isValidPhone(input: string | null | undefined): boolean {
  return normalizePhone(input) !== null;
}

export function isIndianMobile(input: string | null | undefined): boolean {
  return /^\+91[6-9][0-9]{9}$/.test(normalizePhone(input) ?? "");
}

export function maskPhone(input: string | null | undefined): string {
  const phone = normalizePhone(input);
  if (!phone || phone.length < 6) return "—";
  return `${phone.slice(0, 3)}••••••${phone.slice(-2)}`;
}

export function formatPhoneDisplay(input: string | null | undefined): string {
  const phone = normalizePhone(input);
  if (!phone) return "—";
  if (phone.startsWith("+91") && phone.length === 13) {
    return `+91 ${phone.slice(3, 8)} ${phone.slice(8)}`;
  }
  return phone;
}

export function isValidPincode(input: string | null | undefined): boolean {
  return /^[1-9][0-9]{5}$/.test(String(input ?? "").trim());
}
