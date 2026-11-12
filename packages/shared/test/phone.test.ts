import test from "node:test";
import assert from "node:assert/strict";
import {
  normalizePhone,
  isValidPhone,
  isIndianMobile,
  maskPhone,
  isValidPincode,
  formatPhoneDisplay,
} from "../src/phone";

test("normalizePhone mirrors database normalization", () => {
  assert.equal(normalizePhone("9876543210"), "+919876543210");
  assert.equal(normalizePhone("09876543210"), "+919876543210");
  assert.equal(normalizePhone("919876543210"), "+919876543210");
  assert.equal(normalizePhone("+91 98765 43210"), "+919876543210");
  assert.equal(normalizePhone("+44 20 7946 0958"), "+442079460958");
  assert.equal(normalizePhone(""), null);
});

test("isValidPhone rejects short or malformed numbers", () => {
  assert.equal(isValidPhone("9876543210"), true);
  assert.equal(isValidPhone("12345"), false);
  assert.equal(isValidPhone(null), false);
});

test("isIndianMobile enforces Indian mobile prefixes", () => {
  assert.equal(isIndianMobile("9876543210"), true);
  assert.equal(isIndianMobile("5876543210"), false);
});

test("maskPhone never exposes the middle digits", () => {
  assert.equal(maskPhone("9876543210"), "+91••••••10");
  assert.equal(maskPhone(null), "—");
});

test("formatPhoneDisplay splits the Indian number", () => {
  assert.equal(formatPhoneDisplay("9876543210"), "+91 98765 43210");
});

test("isValidPincode rejects leading zero", () => {
  assert.equal(isValidPincode("600001"), true);
  assert.equal(isValidPincode("060001"), false);
});
