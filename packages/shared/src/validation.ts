import { isValidPhone, isValidPincode } from "./phone";
import type { AddressInput } from "./types";

export type FieldErrors = Record<string, string>;

export function requireText(value: string | null | undefined, label: string, min = 1, max = 250): string | null {
  const text = String(value ?? "").trim();
  if (text.length < min) return min > 1 ? `${label} must be at least ${min} characters.` : `${label} is required.`;
  if (text.length > max) return `${label} must be at most ${max} characters.`;
  return null;
}

export function validateAddress(input: AddressInput): FieldErrors {
  const errors: FieldErrors = {};
  const label = requireText(input.label, "Address label", 1, 40);
  if (label) errors.label = label;
  const name = requireText(input.recipient_name, "Recipient name", 2, 160);
  if (name) errors.recipient_name = name;
  if (!isValidPhone(input.phone)) errors.phone = "Enter a valid mobile number.";
  const line1 = requireText(input.line1, "Address", 3, 250);
  if (line1) errors.line1 = line1;
  const line2 = requireText(input.line2, "Address line 2", 0, 250);
  if (line2) errors.line2 = line2;
  const landmark = requireText(input.landmark, "Landmark", 0, 160);
  if (landmark) errors.landmark = landmark;
  if (!input.town_id) errors.town_id = "Select a serviceable town.";
  if (!isValidPincode(input.pincode)) errors.pincode = "Enter a valid 6-digit PIN code.";
  return errors;
}

export function validateProfile(fullName: string, email: string): FieldErrors {
  const errors: FieldErrors = {};
  const name = requireText(fullName, "Full name", 2, 160);
  if (name) errors.full_name = name;
  if (email.trim() && !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email.trim())) {
    errors.email = "Enter a valid email address.";
  }
  return errors;
}

export function validateOrderNote(note: string): string | null {
  return note.length > 1000 ? "Order note must be at most 1000 characters." : null;
}

export function validateReturn(reason: string, description: string): FieldErrors {
  const errors: FieldErrors = {};
  const reasonError = requireText(reason, "Return reason", 3, 200);
  if (reasonError) errors.reason = reasonError;
  const descriptionError = requireText(description, "Description", 0, 1000);
  if (descriptionError) errors.description = descriptionError;
  return errors;
}

export function hasErrors(errors: FieldErrors): boolean {
  return Object.keys(errors).length > 0;
}
