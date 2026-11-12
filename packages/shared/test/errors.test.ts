import test from "node:test";
import assert from "node:assert/strict";
import { errorMessage, errorCode, newIdempotencyKey } from "../src/errors";
import { initials, truncate, cx } from "../src/index";

test("errorMessage extracts useful messages", () => {
  assert.equal(errorMessage(new Error("Error: Stock changed")), "Stock changed");
  assert.equal(errorMessage({ message: "Enter a valid address." }), "Enter a valid address.");
  assert.equal(errorMessage(null, "Fallback"), "Fallback");
});

test("errorCode reads API and context codes", () => {
  assert.equal(errorCode({ error_code: "OTP_EXPIRED" }), "OTP_EXPIRED");
  assert.equal(errorCode({ context: { error_code: "phone_provider_unavailable" } }), "phone_provider_unavailable");
  assert.equal(errorCode("nope"), null);
});

test("idempotency keys fit database constraints", () => {
  const key = newIdempotencyKey("checkout");
  assert.ok(key.startsWith("checkout_"));
  assert.ok(key.length >= 8 && key.length <= 100);
  assert.notEqual(key, newIdempotencyKey("checkout"));
});

test("text helpers handle edge cases", () => {
  assert.equal(initials("Meera Krishnan"), "MK");
  assert.equal(initials(""), "IB");
  assert.equal(truncate("IndiaBizz", 4), "Ind…");
  assert.equal(cx("a", false, null, "b"), "a b");
});
