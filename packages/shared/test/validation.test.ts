import test from "node:test";
import assert from "node:assert/strict";
import { validateAddress, validateProfile, validateReturn, hasErrors } from "../src/validation";
import type { AddressInput } from "../src/types";

const base: AddressInput = {
  label: "Home",
  recipient_name: "Meera Krishnan",
  phone: "9876543210",
  line1: "12, Lake View Road",
  line2: "Near bus stand",
  landmark: "Opposite pharmacy",
  town_id: "5e7d5e70-8df8-4f5f-9f6a-2efd23f8ac55",
  pincode: "600001",
  is_default: true,
};

test("valid address has no errors", () => {
  assert.equal(hasErrors(validateAddress(base)), false);
});

test("address validates phone, pincode, town and required fields", () => {
  const errors = validateAddress({ ...base, phone: "123", pincode: "000001", town_id: "", line1: "" });
  assert.ok(errors.phone);
  assert.ok(errors.pincode);
  assert.ok(errors.town_id);
  assert.ok(errors.line1);
});

test("profile email is optional but must be valid when provided", () => {
  assert.equal(hasErrors(validateProfile("Meera Krishnan", "")), false);
  assert.ok(validateProfile("M", "bad-email").full_name);
  assert.ok(validateProfile("Meera Krishnan", "bad-email").email);
});

test("return reason is required", () => {
  assert.ok(validateReturn("", "").reason);
  assert.equal(hasErrors(validateReturn("Damaged on arrival", "Outer box crushed")), false);
});
