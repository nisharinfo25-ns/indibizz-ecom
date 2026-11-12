"use client";

import { useMemo, useState } from "react";
import {
  errorMessage,
  hasErrors,
  isValidPincode,
  type Address,
  type AddressInput,
  type FieldErrors,
  type Town,
} from "@indibizz/shared";
import { createAddress } from "@/lib/api";

interface AddressFormProps {
  towns: Town[];
  initial?: Address | null;
  defaultPhone?: string;
  onSaved: (address: Address) => void;
  onCancel?: () => void;
}

function emptyState(defaultPhone?: string): AddressInput {
  return {
    label: "Home",
    recipient_name: "",
    phone: defaultPhone ?? "",
    line1: "",
    line2: "",
    landmark: "",
    town_id: "",
    pincode: "",
    is_default: false,
    id: null,
  };
}

export function AddressForm({ towns, initial, defaultPhone, onSaved, onCancel }: AddressFormProps) {
  const [form, setForm] = useState<AddressInput>(() =>
    initial
      ? {
          label: initial.label,
          recipient_name: initial.recipient_name,
          phone: initial.phone,
          line1: initial.line1,
          line2: initial.line2,
          landmark: initial.landmark,
          town_id: initial.town_id,
          pincode: initial.pincode,
          is_default: initial.is_default,
          id: initial.id,
        }
      : emptyState(defaultPhone),
  );
  const [errors, setErrors] = useState<FieldErrors>({});
  const [serverError, setServerError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const selectedTown = useMemo(() => towns.find((town) => town.id === form.town_id) ?? null, [towns, form.town_id]);
  const pincodeHint =
    selectedTown && isValidPincode(form.pincode) && !selectedTown.pincodes.includes(form.pincode.trim())
      ? `PIN ${form.pincode.trim()} is not listed for ${selectedTown.name}. Available: ${selectedTown.pincodes.join(", ") || "none published"}.`
      : null;

  function update<K extends keyof AddressInput>(key: K, value: AddressInput[K]) {
    setForm((current) => ({ ...current, [key]: value }));
    setErrors((current) => {
      if (!current[key as string]) return current;
      const next = { ...current };
      delete next[key as string];
      return next;
    });
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setServerError(null);
    const nextErrors = validateAddressLocal(form);
    setErrors(nextErrors);
    if (hasErrors(nextErrors)) return;

    setSaving(true);
    try {
      const saved = await createAddress(form);
      onSaved(saved);
    } catch (error) {
      setServerError(errorMessage(error));
    } finally {
      setSaving(false);
    }
  }

  return (
    <form onSubmit={submit} className="stack" noValidate>
      {serverError && <div className="alert error">{serverError}</div>}

      <div className="form-grid">
        <div className={`field ${errors.label ? "invalid" : ""}`}>
          <label className="label" htmlFor="address-label">Label</label>
          <input
            id="address-label"
            className="input"
            value={form.label}
            onChange={(event) => update("label", event.target.value)}
            placeholder="Home, Work, Hostel"
            maxLength={40}
            autoComplete="off"
          />
          {errors.label && <span className="error-text">{errors.label}</span>}
        </div>

        <div className={`field ${errors.recipient_name ? "invalid" : ""}`}>
          <label className="label" htmlFor="address-name">Recipient name</label>
          <input
            id="address-name"
            className="input"
            value={form.recipient_name}
            onChange={(event) => update("recipient_name", event.target.value)}
            placeholder="Full name"
            maxLength={160}
            autoComplete="name"
          />
          {errors.recipient_name && <span className="error-text">{errors.recipient_name}</span>}
        </div>

        <div className={`field ${errors.phone ? "invalid" : ""}`}>
          <label className="label" htmlFor="address-phone">Mobile number</label>
          <input
            id="address-phone"
            className="input"
            value={form.phone}
            onChange={(event) => update("phone", event.target.value)}
            placeholder="10-digit mobile number"
            inputMode="tel"
            autoComplete="tel"
          />
          {errors.phone && <span className="error-text">{errors.phone}</span>}
        </div>

        <div className={`field ${errors.town_id ? "invalid" : ""}`}>
          <label className="label" htmlFor="address-town">Town</label>
          <select
            id="address-town"
            className="select"
            value={form.town_id}
            onChange={(event) => update("town_id", event.target.value)}
          >
            <option value="">Select a serviceable town</option>
            {towns.map((town) => (
              <option key={town.id} value={town.id}>
                {town.name}, {town.district}
              </option>
            ))}
          </select>
          {errors.town_id && <span className="error-text">{errors.town_id}</span>}
          {towns.length === 0 && <span className="help">The seller has not published a serviceable town yet.</span>}
        </div>

        <div className={`field span-2 ${errors.line1 ? "invalid" : ""}`}>
          <label className="label" htmlFor="address-line1">Address</label>
          <input
            id="address-line1"
            className="input"
            value={form.line1}
            onChange={(event) => update("line1", event.target.value)}
            placeholder="House / flat, street, area"
            maxLength={250}
            autoComplete="address-line1"
          />
          {errors.line1 && <span className="error-text">{errors.line1}</span>}
        </div>

        <div className={`field ${errors.line2 ? "invalid" : ""}`}>
          <label className="label" htmlFor="address-line2">Address line 2 <span className="muted">(optional)</span></label>
          <input
            id="address-line2"
            className="input"
            value={form.line2}
            onChange={(event) => update("line2", event.target.value)}
            placeholder="Apartment, floor, block"
            maxLength={250}
            autoComplete="address-line2"
          />
          {errors.line2 && <span className="error-text">{errors.line2}</span>}
        </div>

        <div className={`field ${errors.landmark ? "invalid" : ""}`}>
          <label className="label" htmlFor="address-landmark">Landmark <span className="muted">(optional)</span></label>
          <input
            id="address-landmark"
            className="input"
            value={form.landmark}
            onChange={(event) => update("landmark", event.target.value)}
            placeholder="Near the school, opposite the bank"
            maxLength={160}
          />
          {errors.landmark && <span className="error-text">{errors.landmark}</span>}
        </div>

        <div className={`field ${errors.pincode ? "invalid" : ""}`}>
          <label className="label" htmlFor="address-pincode">PIN code</label>
          <input
            id="address-pincode"
            className="input"
            value={form.pincode}
            onChange={(event) => update("pincode", event.target.value.replace(/\D/g, "").slice(0, 6))}
            placeholder="600001"
            inputMode="numeric"
            autoComplete="postal-code"
          />
          {errors.pincode && <span className="error-text">{errors.pincode}</span>}
          {!errors.pincode && pincodeHint && <span className="error-text" style={{ color: "var(--pending)" }}>{pincodeHint}</span>}
        </div>

        <label className="checkbox-row span-2">
          <input
            type="checkbox"
            checked={form.is_default}
            onChange={(event) => update("is_default", event.target.checked)}
          />
          Use this as my default delivery address
        </label>
      </div>

      <div className="row">
        <button type="submit" className="btn btn-primary" disabled={saving || towns.length === 0}>
          {saving ? <span className="spinner" /> : null}
          {saving ? "Saving…" : initial ? "Save address" : "Add address"}
        </button>
        {onCancel && (
          <button type="button" className="btn btn-ghost" onClick={onCancel} disabled={saving}>
            Cancel
          </button>
        )}
      </div>
    </form>
  );
}

function validateAddressLocal(input: AddressInput): FieldErrors {
  const errors: FieldErrors = {};
  if (!input.label.trim()) errors.label = "Address label is required.";
  else if (input.label.trim().length > 40) errors.label = "Address label must be at most 40 characters.";
  if (input.recipient_name.trim().length < 2) errors.recipient_name = "Enter the recipient name.";
  else if (input.recipient_name.trim().length > 160) errors.recipient_name = "Recipient name is too long.";
  if (!/^(\+91)?[6-9][0-9]{9}$/.test(input.phone.replace(/[^0-9+]/g, ""))) errors.phone = "Enter a valid Indian mobile number.";
  if (input.line1.trim().length < 3) errors.line1 = "Enter the delivery address.";
  else if (input.line1.length > 250) errors.line1 = "Address is too long.";
  if (input.line2.length > 250) errors.line2 = "Address line 2 is too long.";
  if (input.landmark.length > 160) errors.landmark = "Landmark is too long.";
  if (!input.town_id) errors.town_id = "Select a serviceable town.";
  if (!isValidPincode(input.pincode)) errors.pincode = "Enter a valid 6-digit PIN code.";
  return errors;
}
